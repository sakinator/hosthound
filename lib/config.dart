import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AddonConfig {
  static final AddonConfig instance = AddonConfig._();

  int port = 7000;
  String host = '0.0.0.0';
  int timeoutSeconds = 9;
  bool enableProxyForHeaders = true;
  Set<String> disabledProviders = {};
  List<String> providerOrder = [];
  bool autoCheckUpdates = true;

  /// TMDB API key used by metadata_service.dart.
  /// Override in data/config.json with your own key if the default is rate-limited.
  String tmdbApiKey = 'b3556f3b206e16f82df4d1f6fd4545e6';
  String torboxApiKey = '';

  /// API 5: OMDb & IMDb Ratings API Key
  String omdbApiKey = 'b9a5e69d';

  /// API 6: Fanart.tv ClearLogo & High-Res Artwork API Key
  String fanartApiKey = '';

  /// API 4: TheTVDB API Key (Episode Mappings & Alternate Ordering)
  String tvdbApiKey = '';

  // Stream Filtering Profiles & Optimization
  bool excludeCams = true;
  String maxResolution = 'all'; // 'all', '1080p', '720p'
  String preferredLanguage = 'any'; // 'any', 'hindi', 'english', 'tamil', 'telugu', 'malayalam', 'kannada', 'bengali', 'punjabi', 'dual'
  bool enableDeduplication = true;
  bool enableDeadLinkFilter = true;
  bool showRatingsInStreams = false;
  bool enableOpenSubtitles = true;
  bool enableTorboxCachedTorrents = false; // By default OFF (100% direct hosters)
  bool enableCacheBypass = true; // Prowlarr-style Cache escape (no-cache headers + query nonce)
  String proxyResolverUrl = ''; // FlareSolverr / Proxy URL (e.g. http://localhost:8191/v1)

  static final File _configFile = File('data/config.json');

  AddonConfig._();

  Future<void> load() async {
    try {
      if (await _configFile.exists()) {
        final content = await _configFile.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        port = map['port'] is int ? map['port'] : port;
        host = map['host']?.toString() ?? host;
        timeoutSeconds = map['timeoutSeconds'] is int ? map['timeoutSeconds'] : timeoutSeconds;
        enableProxyForHeaders = map['enableProxyForHeaders'] is bool
            ? map['enableProxyForHeaders']
            : enableProxyForHeaders;
        if (map['disabledProviders'] is List) {
          disabledProviders =
              (map['disabledProviders'] as List).map((e) => e.toString().toLowerCase()).toSet();
        }
        if (map['providerOrder'] is List) {
          providerOrder =
              (map['providerOrder'] as List).map((e) => e.toString().toLowerCase()).toList();
        }
        autoCheckUpdates =
            map['autoCheckUpdates'] is bool ? map['autoCheckUpdates'] : autoCheckUpdates;
        if (map['tmdbApiKey'] is String && (map['tmdbApiKey'] as String).isNotEmpty) {
          tmdbApiKey = map['tmdbApiKey'];
        }
        if (map['torboxApiKey'] is String) {
          torboxApiKey = map['torboxApiKey'];
        }
        if (map['omdbApiKey'] is String && (map['omdbApiKey'] as String).isNotEmpty) {
          omdbApiKey = map['omdbApiKey'];
        }
        if (map['fanartApiKey'] is String) {
          fanartApiKey = map['fanartApiKey'];
        }
        if (map['tvdbApiKey'] is String) {
          tvdbApiKey = map['tvdbApiKey'];
        }
        if (map['showRatingsInStreams'] is bool) {
          showRatingsInStreams = map['showRatingsInStreams'];
        }
        if (map['excludeCams'] is bool) {
          excludeCams = map['excludeCams'];
        }
        if (map['maxResolution'] is String) {
          maxResolution = map['maxResolution'];
        }
        if (map['preferredLanguage'] is String) {
          preferredLanguage = map['preferredLanguage'];
        }
        if (map['enableDeduplication'] is bool) {
          enableDeduplication = map['enableDeduplication'];
        }
        if (map['enableDeadLinkFilter'] is bool) {
          enableDeadLinkFilter = map['enableDeadLinkFilter'];
        }
        if (map['enableOpenSubtitles'] is bool) {
          enableOpenSubtitles = map['enableOpenSubtitles'];
        }
        if (map['enableTorboxCachedTorrents'] is bool) {
          enableTorboxCachedTorrents = map['enableTorboxCachedTorrents'];
        }
        if (map['enableCacheBypass'] is bool) {
          enableCacheBypass = map['enableCacheBypass'];
        }
        if (map['proxyResolverUrl'] is String) {
          proxyResolverUrl = map['proxyResolverUrl'];
        }
      }
    } catch (e) {
      print('[AddonConfig] Error loading config: $e');
    }
  }

  Timer? _saveDebounceTimer;

  void scheduleSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      save();
    });
  }

  Future<void> save() async {
    try {
      if (!await _configFile.parent.exists()) {
        await _configFile.parent.create(recursive: true);
      }
      final data = {
        'port': port,
        'host': host,
        'timeoutSeconds': timeoutSeconds,
        'enableProxyForHeaders': enableProxyForHeaders,
        'disabledProviders': disabledProviders.toList(),
        'providerOrder': providerOrder,
        'autoCheckUpdates': autoCheckUpdates,
        'tmdbApiKey': tmdbApiKey,
        'torboxApiKey': torboxApiKey,
        'omdbApiKey': omdbApiKey,
        'fanartApiKey': fanartApiKey,
        'tvdbApiKey': tvdbApiKey,
        'showRatingsInStreams': showRatingsInStreams,
        'excludeCams': excludeCams,
        'maxResolution': maxResolution,
        'preferredLanguage': preferredLanguage,
        'enableDeduplication': enableDeduplication,
        'enableDeadLinkFilter': enableDeadLinkFilter,
        'enableOpenSubtitles': enableOpenSubtitles,
        'enableTorboxCachedTorrents': enableTorboxCachedTorrents,
        'enableCacheBypass': enableCacheBypass,
        'proxyResolverUrl': proxyResolverUrl,
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final tmpFile = File('${_configFile.path}.tmp');
      await tmpFile.writeAsString(jsonStr, flush: true);
      try {
        await tmpFile.rename(_configFile.path);
      } catch (_) {
        // Fallback for Windows file lock on atomic rename
        await tmpFile.copy(_configFile.path);
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
    } catch (e) {
      print('[AddonConfig] Error saving config: $e');
    }
  }

  bool isProviderEnabled(String providerId) {
    return !disabledProviders.contains(providerId.toLowerCase());
  }

  void toggleProvider(String providerId, bool enabled) {
    final id = providerId.toLowerCase();
    if (enabled) {
      disabledProviders.remove(id);
    } else {
      disabledProviders.add(id);
    }
    scheduleSave(); // debounced & non-blocking
  }
}
