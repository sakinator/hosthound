import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class _CachedSubs {
  final List<Map<String, dynamic>> subs;
  final DateTime expiresAt;
  _CachedSubs(this.subs, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// OpenSubtitlesService: Integrates OpenSubtitles v3 REST API to fetch
/// multi-language subtitles for movies and series episodes with zero rate limits.
class OpenSubtitlesService {
  static final OpenSubtitlesService instance = OpenSubtitlesService._();
  OpenSubtitlesService._();

  static const String _baseUrl = 'https://opensubtitles-v3.strem.io/subtitles';
  static final Map<String, _CachedSubs> _cache = {};

  /// Fetches subtitles for a given type (movie / series) and IMDb/Stremio ID.
  /// Example id: "tt1375666" (movie) or "tt0903747:1:1" (series S01E01).
  Future<List<Map<String, dynamic>>> getSubtitles({
    required String type,
    required String id,
  }) async {
    final cfg = AddonConfig.instance;
    if (!cfg.enableOpenSubtitles) return [];

    final cacheKey = '$type:$id';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.subs;
    }

    try {
      final cleanType = type == 'series' || type == 'tv' ? 'series' : 'movie';
      final url = Uri.parse('$_baseUrl/$cleanType/${Uri.encodeComponent(id)}.json');

      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['subtitles'] is List) {
          final rawList = data['subtitles'] as List;
          final List<Map<String, dynamic>> parsed = [];
          for (final item in rawList) {
            if (item is Map && item['url'] != null) {
              parsed.add({
                'id': item['id']?.toString() ?? '',
                'url': item['url'].toString(),
                'lang': item['lang']?.toString() ?? 'eng',
              });
            }
          }

          _cache[cacheKey] = _CachedSubs(parsed, DateTime.now().add(const Duration(hours: 2)));
          return parsed;
        }
      }
    } catch (e) {
      print('[OpenSubtitles] Error fetching subtitles for $id: $e');
    }

    return [];
  }
}
