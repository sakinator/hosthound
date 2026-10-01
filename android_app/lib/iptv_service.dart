import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class IptvChannel {
  final String id;
  final String name;
  final String logo;
  final String category;
  final String country;
  final String url;

  IptvChannel({
    required this.id,
    required this.name,
    required this.logo,
    required this.category,
    required this.country,
    required this.url,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'logo': logo,
        'category': category,
        'country': country,
        'url': url,
      };

  factory IptvChannel.fromJson(Map<String, dynamic> j) => IptvChannel(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        logo: j['logo']?.toString() ?? '',
        category: j['category']?.toString() ?? 'General',
        country: j['country']?.toString() ?? 'Global',
        url: j['url']?.toString() ?? '',
      );
}

/// IptvService: Loads, parses, caches, and filters 8,000+ free global broadcast
/// streams from the open-source iptv-org project with category, country, and search filters.
class IptvService {
  static final IptvService instance = IptvService._();
  IptvService._();

  static const String _m3uUrl = 'https://iptv-org.github.io/iptv/index.category.m3u';
  static const String _indiaM3uUrl = 'https://iptv-org.github.io/iptv/countries/in.m3u';
  static final File _cacheFile = File('data/iptv_cache.json');

  List<IptvChannel> _channels = [];
  DateTime? _lastLoaded;
  bool _isLoading = false;

  List<IptvChannel> get allChannels => _channels;

  Completer<void>? _loadCompleter;

  /// Loads channels from memory, local cache, or remote iptv-org M3U.
  Future<List<IptvChannel>> loadChannels({bool forceRefresh = false}) async {
    if (!forceRefresh && _channels.isNotEmpty && _lastLoaded != null) {
      if (DateTime.now().difference(_lastLoaded!).inHours < 12) {
        return _channels;
      }
    }

    if (_isLoading) {
      // Wait for the current load to complete (no CPU spin-wait)
      await _loadCompleter?.future;
      return _channels;
    }

    _isLoading = true;
    _loadCompleter = Completer<void>();
    try {
      // 1. Try reading local cache file if fresh (< 24h)
      if (!forceRefresh && await _cacheFile.exists()) {
        try {
          final content = await _cacheFile.readAsString();
          final list = jsonDecode(content) as List;
          _channels = list.map((e) => IptvChannel.fromJson(e as Map<String, dynamic>)).toList();
          _lastLoaded = DateTime.now();
          if (_channels.isNotEmpty) {
            _isLoading = false;
            // Background refresh if older than 12 hours
            final modified = await _cacheFile.lastModified();
            if (DateTime.now().difference(modified).inHours >= 12) {
              unawaited(_fetchRemoteM3u());
            }
            return _channels;
          }
        } catch (_) {}
      }

      // 2. Fetch from remote iptv-org
      await _fetchRemoteM3u();
    } finally {
      _isLoading = false;
      _loadCompleter?.complete();
      _loadCompleter = null;
    }

    return _channels;
  }

  Future<void> _fetchRemoteM3u() async {
    final Map<String, IptvChannel> channelMap = {};

    // 1. Dedicated India Playlist (738+ high-speed Indian regional live channels)
    try {
      final inRes = await http.get(Uri.parse(_indiaM3uUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
      }).timeout(const Duration(seconds: 15));
      if (inRes.statusCode == 200) {
        final inChannels = parseM3u(inRes.body, defaultCountry: 'IN');
        for (final ch in inChannels) {
          final key = ch.id.isNotEmpty ? ch.id : ch.url;
          channelMap[key] = ch;
        }
        print('[IptvService] Loaded ${inChannels.length} Indian live channels from iptv-org.');
      }
    } catch (e) {
      print('[IptvService] India M3U fetch error: $e');
    }

    // 2. Global Category Playlist (Worldwide channels)
    try {
      final res = await http.get(Uri.parse(_m3uUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
      }).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final parsed = parseM3u(res.body);
        for (final ch in parsed) {
          final key = ch.id.isNotEmpty ? ch.id : ch.url;
          if (!channelMap.containsKey(key)) {
            channelMap[key] = ch;
          }
        }
        print('[IptvService] Total unified channels loaded: ${channelMap.length}.');
      }
    } catch (e) {
      print('[IptvService] Remote global M3U fetch error: $e');
    }

    if (channelMap.isNotEmpty) {
      _channels = channelMap.values.toList();
      _lastLoaded = DateTime.now();
      try {
        if (!_cacheFile.parent.existsSync()) {
          _cacheFile.parent.createSync(recursive: true);
        }
        final jsonStr = jsonEncode(_channels.map((c) => c.toJson()).toList());
        await _cacheFile.writeAsString(jsonStr, flush: true);
      } catch (_) {}
    } else if (_channels.isEmpty) {
      _channels = _getFallbackChannels();
    }
  }

  /// Parses M3U content into structured IptvChannel objects
  static List<IptvChannel> parseM3u(String body, {String defaultCountry = 'Global'}) {
    final lines = body.split('\n');
    final List<IptvChannel> list = [];

    String? currentName;
    String currentLogo = '';
    String currentCategory = 'General';
    String currentCountry = defaultCountry;
    String currentId = '';

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final logoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
        currentLogo = logoMatch != null ? logoMatch.group(1)! : '';

        final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
        currentCategory = groupMatch != null ? groupMatch.group(1)! : 'General';

        final idMatch = RegExp(r'tvg-id="([^"]*)"').firstMatch(line);
        currentId = idMatch != null ? idMatch.group(1)! : '';

        currentCountry = _extractCountry(currentId, line, fallback: defaultCountry);

        final commaIdx = line.indexOf(',');
        if (commaIdx != -1 && commaIdx + 1 < line.length) {
          currentName = line.substring(commaIdx + 1).trim();
        } else {
          currentName = currentId.isNotEmpty ? currentId : 'Live Channel';
        }
      } else if (!line.startsWith('#') && line.startsWith('http')) {
        if (currentName != null && currentName.isNotEmpty) {
          list.add(IptvChannel(
            id: currentId.isNotEmpty ? currentId : 'ch_${list.length}',
            name: currentName,
            logo: currentLogo,
            category: currentCategory,
            country: currentCountry,
            url: line,
          ));
        }
        currentName = null;
        currentLogo = '';
        currentCategory = 'General';
        currentCountry = defaultCountry;
        currentId = '';
      }
    }

    return list;
  }

  static String _extractCountry(String tvgId, String extInfLine, {String fallback = 'Global'}) {
    final lowerId = tvgId.toLowerCase();
    final lowerLine = extInfLine.toLowerCase();
    if (lowerId.contains('.in@') || lowerId.endsWith('.in') || lowerId.contains('@in') || lowerId.contains('@india') || lowerLine.contains('country="in"') || lowerLine.contains('tvg-country="in"') || lowerLine.contains('(india)') || lowerLine.contains(' india') || lowerLine.contains('[india]') || lowerLine.contains('hindi') || lowerLine.contains('tamil') || lowerLine.contains('telugu') || lowerLine.contains('malayalam') || lowerLine.contains('kannada') || lowerLine.contains('bengali') || lowerLine.contains('marathi') || lowerLine.contains('punjabi')) return 'IN';
    if (lowerId.contains('.us@') || lowerId.endsWith('.us') || lowerLine.contains('country="us"') || lowerLine.contains('tvg-country="us"')) return 'US';
    if (lowerId.contains('.uk@') || lowerId.endsWith('.uk') || lowerId.contains('.gb@') || lowerLine.contains('country="uk"') || lowerLine.contains('country="gb"')) return 'UK';
    if (lowerId.contains('.ca@') || lowerId.endsWith('.ca') || lowerLine.contains('country="ca"')) return 'CA';
    if (lowerId.contains('.fr@') || lowerId.endsWith('.fr') || lowerLine.contains('country="fr"')) return 'FR';
    if (lowerId.contains('.de@') || lowerId.endsWith('.de') || lowerLine.contains('country="de"')) return 'DE';
    if (lowerId.contains('.es@') || lowerId.endsWith('.es') || lowerLine.contains('country="es"')) return 'ES';
    if (lowerId.contains('.it@') || lowerId.endsWith('.it') || lowerLine.contains('country="it"')) return 'IT';
    if (lowerId.contains('.au@') || lowerId.endsWith('.au') || lowerLine.contains('country="au"')) return 'AU';
    if (lowerId.contains('.jp@') || lowerId.endsWith('.jp') || lowerLine.contains('country="jp"')) return 'JP';
    if (lowerId.contains('.br@') || lowerId.endsWith('.br') || lowerLine.contains('country="br"')) return 'BR';
    if (lowerId.contains('.mx@') || lowerId.endsWith('.mx') || lowerLine.contains('country="mx"')) return 'MX';
    if (lowerId.contains('.kr@') || lowerId.endsWith('.kr') || lowerLine.contains('country="kr"')) return 'KR';
    if (lowerId.contains('.ru@') || lowerId.endsWith('.ru') || lowerLine.contains('country="ru"')) return 'RU';
    if (lowerId.contains('.tr@') || lowerId.endsWith('.tr') || lowerLine.contains('country="tr"')) return 'TR';
    if (lowerId.contains('.ae@') || lowerId.endsWith('.ae') || lowerLine.contains('country="ae"')) return 'AE';
    if (lowerId.contains('.pk@') || lowerId.endsWith('.pk') || lowerLine.contains('country="pk"')) return 'PK';
    if (lowerId.contains('.bd@') || lowerId.endsWith('.bd') || lowerLine.contains('country="bd"')) return 'BD';
    if (lowerId.contains('.nl@') || lowerId.endsWith('.nl') || lowerLine.contains('country="nl"')) return 'NL';
    return fallback;
  }

  /// Filters channels in memory by search query, category, and country
  List<IptvChannel> filterChannels({
    String? search,
    String? category,
    String? country,
  }) {
    final query = (search ?? '').toLowerCase().trim();
    final cat = (category ?? 'All').toLowerCase();
    final ctry = (country ?? 'All').toUpperCase();

    return _channels.where((c) {
      if (cat != 'all' && !c.category.toLowerCase().contains(cat)) {
        return false;
      }
      if (ctry != 'ALL' && c.country.toUpperCase() != ctry) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesName = c.name.toLowerCase().contains(query);
        final matchesCategory = c.category.toLowerCase().contains(query);
        final matchesCountry = c.country.toLowerCase().contains(query);
        if (!matchesName && !matchesCategory && !matchesCountry) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Finds a channel by its ID
  Future<IptvChannel?> getChannelById(String id) async {
    await loadChannels();
    for (final c in _channels) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Built-in high-availability fallback channels (News, Sports, Entertainment)
  List<IptvChannel> _getFallbackChannels() {
    return [
      IptvChannel(
        id: 'sky_news_uk',
        name: 'Sky News (UK)',
        logo: 'https://i.imgur.com/7bK7QYI.png',
        category: 'News',
        country: 'UK',
        url: 'https://linear417-gb-dash1-prd-cf.cdn.sky.com/17404/SkyNews_G8_HD.isml/SkyNews_G8_HD.m3u8',
      ),
      IptvChannel(
        id: 'al_jazeera_eng',
        name: 'Al Jazeera English',
        logo: 'https://i.imgur.com/rN9kZgM.png',
        category: 'News',
        country: 'Global',
        url: 'https://live-hls-web-aje.getaj.net/AJE/03.m3u8',
      ),
      IptvChannel(
        id: 'dw_english',
        name: 'DW English HD',
        logo: 'https://i.imgur.com/uR4XfVp.png',
        category: 'News',
        country: 'DE',
        url: 'https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8',
      ),
      IptvChannel(
        id: 'france24_en',
        name: 'France 24 English',
        logo: 'https://i.imgur.com/h5T2Jsl.png',
        category: 'News',
        country: 'FR',
        url: 'https://static.france24.com/live/F24_EN_LO_HLS/live_tv.m3u8',
      ),
      IptvChannel(
        id: 'redbull_tv',
        name: 'Red Bull TV Sports & Adventure',
        logo: 'https://i.imgur.com/B7sXW8D.png',
        category: 'Sports',
        country: 'Global',
        url: 'https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8',
      ),
      IptvChannel(
        id: 'ndtv_24x7',
        name: 'NDTV 24x7 India',
        logo: 'https://i.imgur.com/9C3iKeq.png',
        category: 'News',
        country: 'IN',
        url: 'https://ndtv24x7elemadmin.akamaized.net/hls/live/2003678/ndtv24x7/ndtv24x7master.m3u8',
      ),
      IptvChannel(
        id: 'nasa_tv',
        name: 'NASA TV HD',
        logo: 'https://i.imgur.com/X2f8V5t.png',
        category: 'Documentary',
        country: 'US',
        url: 'https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8',
      ),
    ];
  }
}
