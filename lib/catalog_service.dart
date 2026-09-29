import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'omdb_service.dart';
import 'torbox_service.dart';
import 'iptv_service.dart';

class CatalogService {
  static final CatalogService instance = CatalogService._();

  CatalogService._();

  // Invidious public instances with automatic fallback
  static const List<String> _invidiousInstances = [
    'https://invidious.projectsegfau.lt',
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://vid.puffyan.us',
    'https://inv.tux.pizza',
  ];

  static final Map<String, dynamic> _cache = {};
  static final Map<String, Map<String, dynamic>> _enrichmentCache = {};

  /// Returns catalog specifications for manifest.json
  static List<Map<String, dynamic>> getCatalogs() {
    return [
      {
        'type': 'movie',
        'id': 'yt_indian',
        'name': 'YouTube Indian Cinema',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Bollywood Full Movies',
              'South Hindi Dubbed',
              'Indian Web Series',
              'Classic Hindi',
              'Comedy Hindi Movies',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'yt_international',
        'name': 'YouTube International',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Action Movies',
              'Sci-Fi & Thriller',
              'Documentaries',
              'Indie Cinema',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'vimeo_picks',
        'name': 'Vimeo Staff Picks & Shorts',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Staff Picks',
              'Short of the Week',
              'Animation',
              'Documentaries',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'archive_movies',
        'name': 'Internet Archive Movies',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Indian Classics',
              'Golden Era Hollywood',
              'Film Noir',
              'Sci-Fi & Horror',
              'Silent Era',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'dm_movies',
        'name': 'Dailymotion Indian & Global',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Hindi Movies & Dramas',
              'Pakistani Dramas',
              'International Movies',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'tv',
        'id': 'iptv_global',
        'name': 'Free Global Live IPTV',
        'posterShape': 'square',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'India (All Regional)',
              'News',
              'Sports',
              'Movies',
              'Animation',
              'Music',
              'Entertainment',
              'Documentary',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
    ];
  }

  /// Handles /catalog/:type/:id.json and /catalog/:type/:id/:extra.json
  Future<List<Map<String, dynamic>>> getCatalogItems({
    required String type,
    required String id,
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    final cacheKey = '$id:$search:$genre:$skip';
    if (_cache.containsKey(cacheKey)) {
      return List<Map<String, dynamic>>.from(_cache[cacheKey]);
    }

    List<Map<String, dynamic>> items = [];

    try {
      if (id == 'yt_indian') {
        items = await _fetchYouTubeIndian(search: search, genre: genre, skip: skip);
      } else if (id == 'yt_international') {
        items = await _fetchYouTubeInternational(search: search, genre: genre, skip: skip);
      } else if (id == 'vimeo_picks') {
        items = await _fetchVimeo(search: search, genre: genre, skip: skip);
      } else if (id == 'archive_movies') {
        items = await _fetchArchiveOrg(search: search, genre: genre, skip: skip);
      } else if (id == 'dm_movies') {
        items = await _fetchDailymotion(search: search, genre: genre, skip: skip);
      } else if (id == 'iptv_global') {
        items = await _fetchIptvCatalog(search: search, genre: genre, skip: skip);
      }
    } catch (e) {
      print('[CatalogService] Error fetching catalog $id: $e');
    }

    if (items.isNotEmpty && id != 'iptv_global') {
      try {
        final enriched = await Future.wait(
          items.map((it) => _enrichItem(it)),
        ).timeout(const Duration(seconds: 10), onTimeout: () => items);
        items = enriched;
      } catch (e) {
        print('[CatalogService] Catalog enrichment timeout/error (using fallbacks): $e');
      }
    }

    _cache[cacheKey] = items;
    return items;
  }

  Future<List<Map<String, dynamic>>> _fetchIptvCatalog({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    await IptvService.instance.loadChannels();
    final isIndia = genre == 'India' || genre == 'Indian' || genre == 'India (All Regional)';
    final filtered = IptvService.instance.filterChannels(
      search: search,
      category: (genre == 'All' || isIndia) ? null : genre,
      country: isIndia ? 'IN' : null,
    );
    final slice = filtered.skip(skip).take(50);
    return slice.map((c) => {
      'id': 'iptv:${c.id}',
      'type': 'tv',
      'name': c.name,
      'poster': c.logo.isNotEmpty ? c.logo : 'https://i.imgur.com/7bK7QYI.png',
      'genres': [c.category, c.country],
      'description': 'Live TV broadcast: ${c.name} (${c.category} - ${c.country})',
      'posterShape': 'square',
    }).toList();
  }

  // ── YouTube Indian Fetcher ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchYouTubeIndian({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String query;
    if (search != null && search.isNotEmpty) {
      query = '$search full movie hindi';
    } else {
      switch (genre) {
        case 'South Hindi Dubbed':
          query = 'south indian full movie hindi dubbed hd';
          break;
        case 'Indian Web Series':
          query = 'hindi web series full episodes hd';
          break;
        case 'Classic Hindi':
          query = 'old classic hindi full movie';
          break;
        case 'Comedy Hindi Movies':
          query = 'comedy full movie hindi';
          break;
        case 'Bollywood Full Movies':
        default:
          query = 'bollywood full movie hd';
          break;
      }
    }

    return _searchInvidious(query, genre: genre ?? 'Indian');
  }

  // ── YouTube International Fetcher ───────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchYouTubeInternational({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String query;
    if (search != null && search.isNotEmpty) {
      query = '$search full movie';
    } else {
      switch (genre) {
        case 'Sci-Fi & Thriller':
          query = 'sci-fi thriller full movie english';
          break;
        case 'Documentaries':
          query = 'documentary full movie english hd';
          break;
        case 'Indie Cinema':
          query = 'award winning indie full movie';
          break;
        case 'Action Movies':
        default:
          query = 'action full movie english hd';
          break;
      }
    }

    return _searchInvidious(query, genre: genre ?? 'International');
  }

  Future<List<Map<String, dynamic>>> _searchInvidious(String query, {required String genre}) async {
    for (final instance in _invidiousInstances) {
      try {
        final url = Uri.parse('$instance/api/v1/search?q=${Uri.encodeComponent(query)}&type=video');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List;
          final metas = <Map<String, dynamic>>[];
          for (final item in list) {
            final vId = item['videoId']?.toString() ?? '';
            final title = item['title']?.toString() ?? '';
            if (vId.isEmpty || title.isEmpty) continue;

            // Prefer HD 720p crisp thumbnail for YouTube
            final thumbs = item['videoThumbnails'] as List?;
            String poster = 'https://i.ytimg.com/vi/$vId/hq720.jpg';
            if (thumbs != null && thumbs.isNotEmpty) {
              final raw = thumbs.last['url']?.toString() ?? '';
              if (raw.startsWith('http') && !raw.contains('mqdefault') && !raw.contains('default.jpg')) {
                poster = raw;
              } else if (raw.isNotEmpty && !raw.contains('mqdefault')) {
                poster = 'https://i.ytimg.com$raw';
              }
            }

            metas.add({
              'id': 'yt:$vId',
              'type': 'movie',
              'name': title,
              'poster': poster,
              'nativePoster': poster,
              'background': 'https://i.ytimg.com/vi/$vId/maxresdefault.jpg',
              'description': item['description']?.toString() ?? 'YouTube Media ($genre)',
              'releaseInfo': item['publishedText']?.toString() ?? '',
              'genres': ['YouTube', genre],
              'posterShape': 'landscape',
            });
          }
          if (metas.isNotEmpty) return metas;
        }
      } catch (_) {}
    }
    return [];
  }

  // ── Internet Archive Fetcher ────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchArchiveOrg({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String q;
    if (search != null && search.isNotEmpty) {
      q = 'mediatype:movies AND (title:${Uri.encodeComponent(search)} OR description:${Uri.encodeComponent(search)})';
    } else {
      switch (genre) {
        case 'Indian Classics':
          q = 'mediatype:movies AND (title:hindi OR title:india OR title:bollywood OR collection:hindi_movies)';
          break;
        case 'Film Noir':
          q = 'mediatype:movies AND (collection:Film_Noir OR subject:film-noir)';
          break;
        case 'Sci-Fi & Horror':
          q = 'mediatype:movies AND (collection:SciFi_Horror OR subject:horror)';
          break;
        case 'Silent Era':
          q = 'mediatype:movies AND collection:silent_films';
          break;
        case 'Golden Era Hollywood':
        default:
          q = 'mediatype:movies AND collection:feature_films';
          break;
      }
    }

    final page = (skip / 20).floor() + 1;
    final url = Uri.parse(
        'https://archive.org/advancedsearch.php?q=$q&fl[]=identifier,title,description,year&sort[]=downloads+desc&rows=20&page=$page&output=json');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['response']['docs'] as List;
        return docs.map<Map<String, dynamic>>((doc) {
          final id = doc['identifier']?.toString() ?? '';
          final title = doc['title']?.toString() ?? id;
          final year = doc['year']?.toString() ?? '';
          final desc = doc['description']?.toString() ?? 'Internet Archive Classic';
          final poster = 'https://archive.org/download/$id/__ia_thumb.jpg';

          return {
            'id': 'archive:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc,
            'releaseInfo': year,
            'genres': ['Archive.org', genre ?? 'Classic'],
            'posterShape': 'landscape',
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Archive.org error: $e');
    }
    return [];
  }

  // ── Vimeo Fetcher ───────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchVimeo({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String channel = 'staffpicks';
    if (genre == 'Short of the Week') {
      channel = 'shortsoftheweek';
    } else if (genre == 'Animation') {
      channel = 'animation';
    } else if (genre == 'Documentaries') {
      channel = 'documentary';
    }
    final page = (skip / 20).floor() + 1;
    final url = Uri.parse('https://vimeo.com/api/v2/channel/$channel/videos.json?page=$page');
    try {
      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        return list.map<Map<String, dynamic>>((item) {
          final id = item['id'].toString();
          final title = item['title']?.toString() ?? 'Vimeo Video';
          final desc = (item['description']?.toString() ?? '')
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim();
          final poster = item['thumbnail_large']?.toString() ?? item['thumbnail_medium']?.toString() ?? '';
          final durationSec = item['duration'] is int ? item['duration'] as int : 0;
          final durationMin = (durationSec / 60).round();
          return {
            'id': 'vimeo:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc.isNotEmpty ? desc : 'Vimeo Staff Pick',
            'releaseInfo': durationMin > 0 ? '$durationMin min' : '',
            'genres': ['Vimeo', genre ?? 'Staff Picks'],
            'posterShape': 'landscape',
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Vimeo error: $e');
    }
    return [];
  }

  // ── Dailymotion Fetcher ─────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchDailymotion({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String q;
    if (search != null && search.isNotEmpty) {
      q = search;
    } else {
      switch (genre) {
        case 'Pakistani Dramas':
          q = 'pakistani drama full episode';
          break;
        case 'International Movies':
          q = 'full movie english';
          break;
        case 'Hindi Movies & Dramas':
        default:
          q = 'hindi full movie hd';
          break;
      }
    }

    final page = (skip / 20).floor() + 1;
    final url = Uri.parse(
        'https://api.dailymotion.com/videos?fields=id,title,description,thumbnail_1080_url,thumbnail_720_url,thumbnail_480_url,thumbnail_url,created_time&search=${Uri.encodeComponent(q)}&limit=20&page=$page');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['list'] as List;
        return list.map<Map<String, dynamic>>((item) {
          final id = item['id']?.toString() ?? '';
          final title = item['title']?.toString() ?? id;
          final desc = item['description']?.toString() ?? 'Dailymotion Stream';
          final poster = item['thumbnail_1080_url']?.toString() ??
              item['thumbnail_720_url']?.toString() ??
              item['thumbnail_480_url']?.toString() ??
              item['thumbnail_url']?.toString() ??
              '';

          return {
            'id': 'dm:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc,
            'genres': ['Dailymotion', genre ?? 'Video'],
            'posterShape': 'landscape',
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Dailymotion error: $e');
    }
    return [];
  }

  // ── Meta Details Resolver (/meta/:type/:id.json) ───────────────────────────
  Future<Map<String, dynamic>?> getMetaDetail(String type, String id) async {
    if (id.startsWith('iptv:')) {
      final chId = id.replaceFirst('iptv:', '');
      final ch = await IptvService.instance.getChannelById(chId);
      if (ch != null) {
        return {
          'id': id,
          'type': type,
          'name': ch.name,
          'poster': ch.logo.isNotEmpty ? ch.logo : 'https://i.imgur.com/7bK7QYI.png',
          'background': ch.logo.isNotEmpty ? ch.logo : 'https://i.imgur.com/7bK7QYI.png',
          'description': 'Live TV broadcast: ${ch.name} (${ch.category} - ${ch.country})',
          'genres': [ch.category, ch.country],
        };
      }
    }

    if (id.startsWith('yt:')) {
      final vId = id.replaceFirst('yt:', '');
      String title = 'YouTube Video';
      String desc = 'Direct YouTube Stream';
      String poster = 'https://i.ytimg.com/vi/$vId/hq720.jpg';
      String bg = 'https://i.ytimg.com/vi/$vId/maxresdefault.jpg';

      for (final instance in _invidiousInstances) {
        try {
          final res = await http.get(Uri.parse('$instance/api/v1/videos/$vId')).timeout(const Duration(seconds: 3));
          if (res.statusCode == 200) {
            final json = jsonDecode(res.body);
            title = json['title']?.toString() ?? title;
            desc = json['description']?.toString() ?? desc;
            break;
          }
        } catch (_) {}
      }

      final rawMeta = {
        'id': id,
        'type': type,
        'name': title,
        'poster': poster,
        'nativePoster': poster,
        'background': bg,
        'description': desc,
      };
      return await _enrichItem(rawMeta);
    }

    if (id.startsWith('archive:')) {
      final ident = id.replaceFirst('archive:', '');
      try {
        final res = await http.get(Uri.parse('https://archive.org/metadata/$ident')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final meta = json['metadata'] ?? {};
          final title = meta['title'] ?? ident;
          final desc = meta['description'] ?? 'Internet Archive Classic';
          final year = meta['year'] ?? '';
          final poster = 'https://archive.org/services/img/$ident';
          final rawMeta = {
            'id': id,
            'type': type,
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc,
            'releaseInfo': year,
          };
          return await _enrichItem(rawMeta);
        }
      } catch (_) {}
      final rawMeta = {
        'id': id,
        'type': type,
        'name': ident,
        'poster': 'https://archive.org/services/img/$ident',
        'nativePoster': 'https://archive.org/services/img/$ident',
        'description': 'Internet Archive Media',
      };
      return await _enrichItem(rawMeta);
    }

    if (id.startsWith('dm:')) {
      final vId = id.replaceFirst('dm:', '');
      try {
        final res = await http.get(Uri.parse('https://api.dailymotion.com/video/$vId?fields=title,description,thumbnail_720_url')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final poster = json['thumbnail_720_url'] ?? '';
          final rawMeta = {
            'id': id,
            'type': type,
            'name': json['title'] ?? 'Dailymotion Video',
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': json['description'] ?? '',
          };
          return await _enrichItem(rawMeta);
        }
      } catch (_) {}
      final rawMeta = {
        'id': id,
        'type': type,
        'name': 'Dailymotion Video',
        'description': 'Dailymotion Stream',
      };
      return await _enrichItem(rawMeta);
    }

    if (id.startsWith('vimeo:')) {
      final vId = id.replaceFirst('vimeo:', '');
      try {
        final res = await http.get(Uri.parse('https://vimeo.com/api/oembed.json?url=https://vimeo.com/$vId')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final title = json['title']?.toString() ?? 'Vimeo Video';
          final poster = json['thumbnail_url']?.toString() ?? '';
          final author = json['author_name']?.toString() ?? '';
          final desc = json['description']?.toString() ?? (author.isNotEmpty ? 'By $author on Vimeo' : 'Vimeo Staff Pick');
          final rawMeta = {
            'id': id,
            'type': type,
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc,
          };
          return await _enrichItem(rawMeta);
        }
      } catch (_) {}
      final rawMeta = {
        'id': id,
        'type': type,
        'name': 'Vimeo Video',
        'description': 'Vimeo Stream',
      };
      return await _enrichItem(rawMeta);
    }

    return null;
  }

  // ── Poster & Rating Enrichment Helpers ─────────────────────────────────────
  static Map<String, dynamic> _cleanTitleAndExtractYear(String rawTitle) {
    var title = rawTitle;

    // 1. Extract 4-digit year (1900-2099)
    int? year;
    final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(title);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1)!);
    }

    // 2. Cut off channel/actors/trailers after common separator symbols
    for (final sep in ['|', ' - ', '–', '—', '•', '//', '\\']) {
      if (title.contains(sep)) {
        final candidate = title.split(sep).first.trim();
        if (candidate.length >= 3) {
          title = candidate;
          break;
        }
      }
    }

    // 3. Strip foreign script noise (e.g. Hindi Devanagari, Urdu) from search query
    title = title.replaceAll(RegExp(r'[\u0900-\u097F\u0600-\u06FF]'), ' ');

    // 4. Strip common leading noise prefixes
    title = title.replaceAll(RegExp(r'^(new\s+hindi\s+movie\s*[:\s]*|latest\s+hindi\s+movie\s*[:\s]*|hindi\s+movie\s*[:\s]*)', caseSensitive: false), '');

    // 5. Remove text in brackets like [HD], (1975), [Full Movie]
    title = title.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ');

    // 6. Strip common public catalog video noise phrases
    title = title.replaceAll(RegExp(
      r'\b(full movie|full hindi movie|hindi dubbed|hindi movie|south indian movie|south indian|south movie|south dubbed|tamil dubbed|telugu dubbed|kannada dubbed|malayalam dubbed|bengali movie|bollywood movie|hollywood movie|indian movie|blockbuster movie|superhit movie|classic movie|full episodes?|complete movie|award winning|official video|official trailer|official movie|with english subtitles?|english subtitles?|eng subs?|remastered|restored|colorized|restoration|4k uhd|4k hdr|1080p|720p|480p|4k|uhd|hdr|bluray|blu-ray|web-dl|webrip|dvdrip|hd|hq)\b',
      caseSensitive: false,
    ), ' ');

    // 7. Strip common distributor / studio / actor tags
    title = title.replaceAll(RegExp(
      r'\b(shemaroo|goldmines|pen movies|rajshri|yash raj films|yrf|t-series|ultra bollywood|venus|eros now|eros|satyajit ray|guru dutt|amitabh bachchan|dharmendra|shah rukh khan|salman khan|aamir khan)\b',
      caseSensitive: false,
    ), ' ');

    // 8. Clean punctuation & extra whitespace
    title = title.replaceAll(RegExp(r'["#%*<>:;=\\_{}]'), ' ');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    return {'title': title, 'year': year};
  }

  Future<Map<String, dynamic>> _enrichItem(Map<String, dynamic> item) async {
    final rawName = item['name']?.toString() ?? '';
    if (rawName.isEmpty) return item;

    final parsed = _cleanTitleAndExtractYear(rawName);
    final cleanTitle = parsed['title'] as String;
    final year = parsed['year'] as int?;

    if (cleanTitle.length < 2) return item;

    final cacheKey = '$cleanTitle:${year ?? ''}';
    if (_enrichmentCache.containsKey(cacheKey)) {
      final cached = _enrichmentCache[cacheKey]!;
      return _applyEnrichment(item, cached);
    }

    Map<String, dynamic>? enriched;

    // ── Tier 1: OMDb & TMDB (User API key or built-in reliable key) ──
    try {
      final omdb = await OmdbService.instance.getMetadata(null, title: cleanTitle, year: year);
      if (omdb != null && omdb.title != null && omdb.title!.isNotEmpty) {
        final poster = (omdb.poster != null && omdb.poster != 'N/A' && omdb.poster!.startsWith('http'))
            ? omdb.poster!
            : null;
        final rating = (omdb.imdbRating != null && omdb.imdbRating != 'N/A' && omdb.imdbRating!.isNotEmpty)
            ? omdb.imdbRating!
            : null;
        final yearStr = (omdb.year != null && omdb.year != 'N/A') ? omdb.year! : (year?.toString() ?? '');
        final plot = (omdb.plot != null && omdb.plot != 'N/A') ? omdb.plot! : null;

        enriched = {
          'name': omdb.title,
          if (omdb.imdbId != null) 'imdbId': omdb.imdbId,
          if (poster != null) 'poster': poster,
          if (rating != null) 'imdbRating': rating,
          if (rating != null) 'rating': rating,
          'year': yearStr,
          'releaseInfo': yearStr,
          if (plot != null) 'description': plot,
          if (omdb.genre != null && omdb.genre != 'N/A')
            'genres': omdb.genre!.split(', ').map((g) => g.trim()).toList(),
          if (poster != null) 'posterShape': 'poster',
        };
      }
    } catch (_) {}

    // TMDB Lookup (if poster or rating still missing)
    if (enriched == null || enriched['poster'] == null) {
      final tmdbKey = AddonConfig.instance.tmdbApiKey.trim();
      final apiKey = tmdbKey.isNotEmpty ? tmdbKey : 'b3556f3b206e16f82df4d1f6fd4545e6';
      for (final host in ['https://api.themoviedb.org/3', 'https://db.speedracelight.com/3']) {
        try {
          final yParam = year != null ? '&year=$year' : '';
          final uri = Uri.parse('$host/search/movie?api_key=$apiKey&query=${Uri.encodeComponent(cleanTitle)}$yParam');
          final res = await http.get(uri).timeout(const Duration(milliseconds: 2500));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = data['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final first = results.first;
              final pPath = first['poster_path']?.toString();
              final bPath = first['backdrop_path']?.toString();
              final vote = first['vote_average'];
              final rating = (vote is num && vote > 0) ? vote.toStringAsFixed(1) : null;
              final rDate = first['release_date']?.toString() ?? '';
              final rYear = rDate.length >= 4 ? rDate.substring(0, 4) : (year?.toString() ?? '');
              final title = (first['title'] ?? first['name'])?.toString() ?? cleanTitle;
              final overview = first['overview']?.toString();

              String? tmdbImdbId;
              try {
                final extUri = Uri.parse('$host/movie/${first['id']}/external_ids?api_key=$apiKey');
                final extRes = await http.get(extUri).timeout(const Duration(milliseconds: 1500));
                if (extRes.statusCode == 200) {
                  final extData = jsonDecode(extRes.body);
                  final idStr = extData['imdb_id']?.toString();
                  if (idStr != null && idStr.startsWith('tt')) {
                    tmdbImdbId = idStr;
                  }
                }
              } catch (_) {}

              enriched = {
                'name': title,
                if (tmdbImdbId != null) 'imdbId': tmdbImdbId,
                if (pPath != null) 'poster': 'https://image.tmdb.org/t/p/w500$pPath',
                if (bPath != null) 'background': 'https://image.tmdb.org/t/p/w1280$bPath',
                if (rating != null) 'imdbRating': rating,
                if (rating != null) 'rating': rating,
                'year': rYear,
                'releaseInfo': rYear,
                if (overview != null && overview.isNotEmpty) 'description': overview,
                if (pPath != null) 'posterShape': 'poster',
              };
              break;
            }
          }
        } catch (_) {}
      }
    }

    // ── Tier 2: 100% Free / Zero-Key API Fallback (Cinemeta / Metahub) ──
    if (enriched == null || enriched['poster'] == null) {
      try {
        final uri = Uri.parse('https://v3-cinemeta.strem.io/catalog/movie/top/search=${Uri.encodeComponent(cleanTitle)}.json');
        final res = await http.get(uri).timeout(const Duration(milliseconds: 2500));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final metas = data['metas'] as List?;
          if (metas != null && metas.isNotEmpty) {
            final m = metas.first;
            final poster = m['poster']?.toString();
            var rating = m['imdbRating']?.toString();
            final imdbId = m['id']?.toString();
            if ((rating == null || rating.isEmpty) && imdbId != null && imdbId.startsWith('tt')) {
              try {
                final omdb = await OmdbService.instance.getMetadata(imdbId);
                rating = omdb?.imdbRating;
              } catch (_) {}
            }
            final yStr = m['year']?.toString() ?? (year?.toString() ?? '');
            enriched = {
              'name': m['name']?.toString() ?? cleanTitle,
              if (imdbId != null && imdbId.startsWith('tt')) 'imdbId': imdbId,
              if (poster != null && poster.isNotEmpty) 'poster': poster,
              if (rating != null && rating.isNotEmpty && rating != 'N/A') 'imdbRating': rating,
              if (rating != null && rating.isNotEmpty && rating != 'N/A') 'rating': rating,
              'year': yStr,
              'releaseInfo': yStr,
              if (m['description'] != null) 'description': m['description'].toString(),
              if (poster != null && poster.isNotEmpty) 'posterShape': 'poster',
            };
          }
        }
      } catch (_) {}
    }

    // ── Tier 3: Last Fallback (Native website video thumbnail itself) ──
    if (enriched != null) {
      _enrichmentCache[cacheKey] = enriched;
      return _applyEnrichment(item, enriched);
    }

    // Cache empty map so we don't re-query missing items repeatedly
    _enrichmentCache[cacheKey] = {};
    return item;
  }

  Map<String, dynamic> _applyEnrichment(Map<String, dynamic> original, Map<String, dynamic> enriched) {
    if (enriched.isEmpty) return original;
    final merged = Map<String, dynamic>.from(original);
    // Preserve original native video poster as fallback
    merged['nativePoster'] ??= original['poster'];

    if (enriched['name'] != null) merged['name'] = enriched['name'];
    if (enriched['imdbId'] != null) merged['imdbId'] = enriched['imdbId'];
    if (enriched['poster'] != null) merged['poster'] = enriched['poster'];
    if (enriched['background'] != null) merged['background'] = enriched['background'];
    if (enriched['imdbRating'] != null) merged['imdbRating'] = enriched['imdbRating'];
    if (enriched['rating'] != null) merged['rating'] = enriched['rating'];
    if (enriched['year'] != null && enriched['year'].toString().isNotEmpty) {
      merged['year'] = enriched['year'];
      merged['releaseInfo'] = enriched['year'];
    }
    if (enriched['description'] != null && enriched['description'].toString().isNotEmpty) {
      merged['description'] = enriched['description'];
    }
    if (enriched['genres'] != null && enriched['genres'] is List) {
      final List existing = (merged['genres'] as List?) ?? [];
      final List toAdd = enriched['genres'] as List;
      final set = <String>{...existing.map((e) => e.toString()), ...toAdd.map((e) => e.toString())};
      merged['genres'] = set.toList();
    }
    if (enriched['posterShape'] != null) {
      merged['posterShape'] = enriched['posterShape'];
    }
    return merged;
  }

  // ── Stream Resolvers (/stream/:type/:id.json) ──────────────────────────────
  Future<List<Map<String, dynamic>>> resolveCustomStreams(
    String type, 
    String id, 
    {String? localBaseUrl}
  ) async {
    List<Map<String, dynamic>> streams = [];

    // 1. YouTube Stream Resolver
    if (id.startsWith('yt:')) {
      final vId = id.replaceFirst('yt:', '');
      streams = await _resolveYouTubeStreams(vId);
    } else if (id.startsWith('vimeo:')) {
      // 2. Vimeo Stream Resolver
      final vId = id.replaceFirst('vimeo:', '');
      streams = await _resolveVimeoStreams(vId);
    } else if (id.startsWith('archive:')) {
      // 3. Internet Archive Stream Resolver
      final ident = id.replaceFirst('archive:', '');
      streams = await _resolveArchiveStreams(ident);
    } else if (id.startsWith('dm:')) {
      // 4. Dailymotion Stream Resolver
      final vId = id.replaceFirst('dm:', '');
      streams = await _resolveDailymotionStreams(vId);
    } else if (id.startsWith('iptv:')) {
      // 5. Free Global Live IPTV Resolver
      final chId = id.replaceFirst('iptv:', '');
      final ch = await IptvService.instance.getChannelById(chId);
      if (ch != null) {
        streams.add({
          'name': '📺 ${ch.name}',
          'title': '⚡ Live HLS Stream • ${ch.category} • ${ch.country}\n🌐 Source: iptv-org Broadcast',
          'url': ch.url,
          'behaviorHints': const {'notWebReady': false},
        });
      }
    }

    return await _applyTorboxOptions(streams, localBaseUrl);
  }

  Future<List<Map<String, dynamic>>> _resolveYouTubeStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    for (final instance in _invidiousInstances) {
      try {
        final url = Uri.parse('$instance/api/v1/videos/$vId');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final formatStreams = json['formatStreams'] as List?;
          if (formatStreams != null) {
            for (final f in formatStreams) {
              final streamUrl = f['url']?.toString();
              final quality = f['qualityLabel']?.toString() ?? f['resolution']?.toString() ?? 'Direct';
              if (streamUrl != null && streamUrl.isNotEmpty) {
                streams.add({
                  'name': 'YouTube ($quality)',
                  'title': '⚡ Direct Stream • $quality\n🌐 Source: YouTube\n📦 Host: Google Video CDN',
                  'url': streamUrl,
                  'behaviorHints': {'notWebReady': false},
                });
              }
            }
          }
          final hlsUrl = json['hlsUrl']?.toString();
          if (hlsUrl != null && hlsUrl.isNotEmpty) {
            streams.insert(0, {
              'name': 'YouTube HLS',
              'title': '⚡ Adaptive HLS Master Stream\n🌐 Source: YouTube\n📦 Host: Google Video CDN',
              'url': hlsUrl,
              'behaviorHints': {'notWebReady': false},
            });
          }
          if (streams.isNotEmpty) return streams;
        }
      } catch (_) {}
    }

    // Fallback: direct invidious playback url
    streams.add({
      'name': 'YouTube Web Player',
      'title': 'Direct Stream Link\n🌐 Source: YouTube\n📦 Host: YouTube Web',
      'url': 'https://www.youtube.com/watch?v=$vId',
    });
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveVimeoStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final url = Uri.parse('https://player.vimeo.com/video/$vId');
      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://vimeo.com/$vId',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final html = res.body;
        final m = RegExp(r'(\{"cdn_url":.+?\})\s*</script>').firstMatch(html);
        if (m != null) {
          final data = jsonDecode(m.group(1)!);
          final files = data['request']?['files'] as Map?;
          if (files != null) {
            final hls = files['hls'] as Map?;
            if (hls != null) {
              final cdns = hls['cdns'] as Map?;
              if (cdns != null && cdns.isNotEmpty) {
                final defaultCdn = hls['default_cdn']?.toString() ?? cdns.keys.first;
                final cdnObj = cdns[defaultCdn] ?? cdns.values.first;
                final m3u8Url = cdnObj?['url']?.toString();
                if (m3u8Url != null && m3u8Url.isNotEmpty) {
                  streams.add({
                    'name': '⚡ Vimeo Master HLS',
                    'title': '⚡ Adaptive Quality Master Stream\n🌐 Source: Vimeo\n📦 Host: Vimeo CDN',
                    'url': m3u8Url,
                    'behaviorHints': {'notWebReady': false},
                  });
                }
              }
            }
            final progressive = files['progressive'] as List?;
            if (progressive != null) {
              for (final p in progressive) {
                if (p is Map) {
                  final q = p['quality']?.toString() ?? 'HD';
                  final pUrl = p['url']?.toString();
                  if (pUrl != null && pUrl.isNotEmpty) {
                    streams.add({
                      'name': '🌐 Vimeo Direct ($q)',
                      'title': '🌐 Direct MP4 Video • $q\n🌐 Source: Vimeo\n📦 Host: Vimeo CDN',
                      'url': pUrl,
                      'behaviorHints': {'notWebReady': false},
                    });
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Vimeo resolve error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Vimeo Web Player',
        'title': '⚡ Direct Web Stream\n🌐 Source: Vimeo\n📦 Host: Vimeo Web',
        'url': 'https://vimeo.com/$vId',
      });
    }
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveArchiveStreams(String ident) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final res = await http.get(Uri.parse('https://archive.org/metadata/$ident')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final files = data['files'] as List?;
        if (files != null) {
          // Find MP4 or MKV video files
          for (final f in files) {
            final name = f['name']?.toString() ?? '';
            final format = f['format']?.toString() ?? '';
            if (name.endsWith('.mp4') || format.contains('MPEG4') || format.contains('h.264')) {
              final size = f['size'] != null ? ' (${(int.parse(f['size'].toString()) / (1024 * 1024)).toStringAsFixed(1)} MB)' : '';
              streams.add({
                'name': 'Archive.org',
                'title': '⚡ $name$size • Direct Cloud Stream\n🌐 Source: Archive.org\n📦 Host: Archive.org',
                'url': 'https://archive.org/download/$ident/$name',
                'behaviorHints': {'notWebReady': false},
              });
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Archive stream resolve error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Archive.org',
        'title': '⚡ Direct Video Download/Stream\n🌐 Source: Archive.org\n📦 Host: Archive.org',
        'url': 'https://archive.org/download/$ident/$ident.mp4',
      });
    }
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveDailymotionStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final metaUrl = Uri.parse('https://www.dailymotion.com/player/metadata/video/$vId');
      final res = await http.get(metaUrl).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final qualities = json['qualities'] as Map?;
        if (qualities != null) {
          final auto = qualities['auto'] as List?;
          if (auto != null && auto.isNotEmpty) {
            final hlsUrl = auto.first['url']?.toString();
            if (hlsUrl != null && hlsUrl.isNotEmpty) {
              streams.add({
                'name': 'Dailymotion HLS',
                'title': '⚡ Adaptive Auto Quality HLS • Direct Stream\n🌐 Source: Dailymotion\n📦 Host: Dailymotion CDN',
                'url': hlsUrl,
                'behaviorHints': {'notWebReady': false},
              });
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Dailymotion stream error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Dailymotion Direct',
        'title': '⚡ Direct Web Stream\n🌐 Source: Dailymotion\n📦 Host: Dailymotion CDN',
        'url': 'https://www.dailymotion.com/video/$vId',
      });
    }
    return streams;
  }

  /// Searches YouTube, Archive.org, and Dailymotion for a given movie/show title
  /// and returns playable direct cloud streams to display in Stremio & Nuvio!
  Future<List<Map<String, dynamic>>> searchPublicStreams({
    required String title,
    int? year,
    String type = 'movie',
    String? localBaseUrl,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return [];

    final cacheKey = 'pub_streams:$type:$cleanTitle:$year';
    if (_cache.containsKey(cacheKey)) {
      return List<Map<String, dynamic>>.from(_cache[cacheKey]);
    }

    final publicStreams = <Map<String, dynamic>>[];
    final futures = <Future<void>>[];

    // 1. YouTube Search & Stream Resolution
    futures.add(() async {
      try {
        final query = '$cleanTitle ${year ?? ''} full movie'.trim();
        final metas = await _searchInvidious(query, genre: 'Cinema');
        if (metas.isNotEmpty) {
          for (final item in metas.take(2)) {
            final vId = (item['id']?.toString() ?? '').replaceFirst('yt:', '');
            if (vId.isNotEmpty) {
              final ytStreams = await _resolveYouTubeStreams(vId);
              for (final s in ytStreams) {
                final q = s['name']?.toString() ?? 'Direct';
                publicStreams.add({
                  'name': '⚡ YouTube ($q)',
                  'title': '⚡ Direct Cloud Stream (Non-Torrent) • ${item['name']}',
                  'url': s['url'],
                  'behaviorHints': {'notWebReady': false},
                });
              }
              if (publicStreams.isNotEmpty) break;
            }
          }
        }
      } catch (_) {}
    }());

    // 2. Internet Archive Search & Stream Resolution
    if (type == 'movie') {
      futures.add(() async {
        try {
          final archiveItems = await _fetchArchiveOrg(search: cleanTitle);
          if (archiveItems.isNotEmpty) {
            final matched = archiveItems.firstWhere(
              (it) => it['name']?.toString().toLowerCase().contains(cleanTitle.toLowerCase()) ?? false,
              orElse: () => archiveItems.first,
            );
            final ident = (matched['id']?.toString() ?? '').replaceFirst('archive:', '');
            if (ident.isNotEmpty) {
              final aStreams = await _resolveArchiveStreams(ident);
              for (final s in aStreams.take(3)) {
                publicStreams.add({
                  'name': '🏛️ Archive.org [Direct]',
                  'title': '🏛️ Internet Archive Video • Direct Cloud Stream (Non-Torrent)',
                  'url': s['url'],
                  'behaviorHints': {'notWebReady': false},
                });
              }
            }
          }
        } catch (_) {}
      }());
    }

    // 3. Dailymotion Search & Stream Resolution
    futures.add(() async {
      try {
        final dmItems = await _fetchDailymotion(search: '$cleanTitle ${year ?? ''}');
        if (dmItems.isNotEmpty) {
          for (final item in dmItems.take(1)) {
            final vId = (item['id']?.toString() ?? '').replaceFirst('dm:', '');
            if (vId.isNotEmpty) {
              final dmStreams = await _resolveDailymotionStreams(vId);
              for (final s in dmStreams) {
                publicStreams.add({
                  'name': '📺 Dailymotion [HLS]',
                  'title': '📺 Dailymotion Cloud Stream • ${item['name']}',
                  'url': s['url'],
                  'behaviorHints': {'notWebReady': false},
                });
              }
            }
          }
        }
      } catch (_) {}
    }());

    try {
      await Future.wait(futures).timeout(const Duration(milliseconds: 3500));
    } catch (_) {}

    final enrichedWithTorbox = await _applyTorboxOptions(publicStreams, localBaseUrl);
    _cache[cacheKey] = enrichedWithTorbox;
    return enrichedWithTorbox;
  }

  /// Checks TorBox cache state for supported direct streams and provides:
  /// 1. ⚡ TorBox [Cached] (instant CDN play)
  /// 2. ☁️⬆️ TorBox [Start Caching] (click to cloud cache)
  /// 3. Direct Play (native cloud stream)
  Future<List<Map<String, dynamic>>> _applyTorboxOptions(
    List<Map<String, dynamic>> streams,
    String? localBaseUrl,
  ) async {
    final torboxKey = AddonConfig.instance.torboxApiKey.trim();
    if (torboxKey.isEmpty || streams.isEmpty) return streams;

    final baseUrl = localBaseUrl ?? 'http://localhost:${AddonConfig.instance.port}';
    final candidateUrls = <String>[];

    for (final s in streams) {
      final url = s['url']?.toString() ?? '';
      if (url.isEmpty || url.contains('.m3u8')) continue;
      if (TorboxService.instance.isSupportedHoster(url)) {
        candidateUrls.add(url);
      }
    }

    Map<String, bool> cacheMap = {};
    if (candidateUrls.isNotEmpty) {
      try {
        cacheMap = await TorboxService.instance.checkCachedBatch(candidateUrls, torboxKey)
            .timeout(const Duration(milliseconds: 1500), onTimeout: () => {});
      } catch (_) {}
    }

    final enrichedStreams = <Map<String, dynamic>>[];

    for (final s in streams) {
      final url = s['url']?.toString() ?? '';
      final name = s['name']?.toString() ?? 'Stream';
      final title = s['title']?.toString() ?? '';
      final isSupported = candidateUrls.contains(url);
      final isCached = cacheMap[url] == true;

      if (isSupported && isCached) {
        enrichedStreams.add({
          'name': '⚡ TorBox [Cached]\n$name',
          'title': '⚡ Cached on TorBox Cloud CDN • Instant Playback\n$title',
          'url': '$baseUrl/torbox/play?url=${Uri.encodeComponent(url)}',
          'behaviorHints': const {'notWebReady': false},
        });
      } else if (isSupported) {
        enrichedStreams.add({
          'name': '☁️⬆️ TorBox [Start Caching]\n$name',
          'title': '☁️⬆️ TorBox Cachable • Click to cache on TorBox cloud & stream\n$title',
          'url': '$baseUrl/torbox/play?url=${Uri.encodeComponent(url)}',
          'behaviorHints': const {'notWebReady': false},
        });
      }

      enrichedStreams.add(s);
    }

    return enrichedStreams;
  }
}
