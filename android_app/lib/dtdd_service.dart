import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class DtddService {
  static final DtddService instance = DtddService._();
  DtddService._();

  static const String _apiBase = 'https://api.doesthedogdie.com';
  static final Map<String, Map<String, dynamic>> _cache = {};
  static final Map<String, DateTime> _cacheExpiry = {};
  static const Duration _cacheTtl = Duration(days: 7);

  static const Map<String, String> _browserHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  /// Fetches content warnings and trigger advisories from DoesTheDogDie for a given IMDb ID or title.
  /// Works automatically ZERO-KEY via public web resolution, or via official API if user entered a key.
  Future<Map<String, dynamic>> getContentWarnings(
    String rawId, {
    String? title,
    int? year,
  }) async {
    String imdbId = rawId.trim();
    if (imdbId.contains(':')) {
      imdbId = imdbId.split(':')[0];
    }

    final query = (title != null && title.trim().isNotEmpty) ? title.trim() : imdbId;
    final defaultSearchUrl = 'https://www.doesthedogdie.com/search?q=${Uri.encodeComponent(query)}';

    final cacheKey = imdbId.isNotEmpty ? imdbId : (title ?? '').toLowerCase();
    final now = DateTime.now();

    if (_cache.containsKey(cacheKey)) {
      final expiry = _cacheExpiry[cacheKey];
      if (expiry != null && now.isBefore(expiry)) {
        return _cache[cacheKey]!;
      }
    }

    final apiKey = AddonConfig.instance.dtddApiKey.trim();

    // 1. If user provided a key, query official DTDD JSON API
    if (apiKey.isNotEmpty) {
      try {
        final headers = {
          'Accept': 'application/json',
          'X-API-KEY': apiKey,
          'User-Agent': 'Hostreamio/1.0',
        };

        int? mediaId;
        String? mediaName;

        if (imdbId.startsWith('tt')) {
          final searchUri = Uri.parse('$_apiBase/dddsearch?imdb=$imdbId');
          final res = await http.get(searchUri, headers: headers).timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final items = (data['items'] as List?) ?? [];
            if (items.isNotEmpty) {
              mediaId = items[0]['id'] as int?;
              mediaName = items[0]['name']?.toString();
            }
          }
        }

        if (mediaId == null && title != null && title.trim().isNotEmpty) {
          final searchUri = Uri.parse('$_apiBase/dddsearch?q=${Uri.encodeComponent(title.trim())}');
          final res = await http.get(searchUri, headers: headers).timeout(const Duration(seconds: 5));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final items = (data['items'] as List?) ?? [];
            if (items.isNotEmpty) {
              mediaId = items[0]['id'] as int?;
              mediaName = items[0]['name']?.toString();
            }
          }
        }

        if (mediaId != null) {
          final mediaUri = Uri.parse('$_apiBase/media/$mediaId');
          final res = await http.get(mediaUri, headers: headers).timeout(const Duration(seconds: 6));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final stats = (data['topicItemStats'] as List?) ?? [];
            final triggers = <Map<String, dynamic>>[];
            final safe = <Map<String, dynamic>>[];

            for (final s in stats) {
              if (s is! Map) continue;
              final yesSum = (s['yesSum'] as num?)?.toInt() ?? 0;
              final noSum = (s['noSum'] as num?)?.toInt() ?? 0;
              final topic = s['topic']?['name']?.toString() ?? '';
              final comment = s['comment']?.toString();
              if (topic.isEmpty || (yesSum == 0 && noSum == 0)) continue;

              final total = yesSum + noSum;
              final ratio = total > 0 ? yesSum / total : 0.0;

              if (yesSum > noSum && yesSum >= 1 && ratio >= 0.5) {
                triggers.add({
                  'topic': topic,
                  'yes': yesSum,
                  'no': noSum,
                  if (comment != null && comment.isNotEmpty) 'comment': comment,
                });
              } else if (noSum > yesSum && noSum >= 2 && (1.0 - ratio) >= 0.7) {
                safe.add({
                  'topic': topic,
                  'yes': yesSum,
                  'no': noSum,
                });
              }
            }

            triggers.sort((a, b) => (b['yes'] as int).compareTo(a['yes'] as int));
            safe.sort((a, b) => (b['no'] as int).compareTo(a['no'] as int));

            final result = {
              'success': true,
              'matched': true,
              'mediaId': mediaId,
              'title': mediaName ?? data['name']?.toString() ?? query,
              'url': 'https://www.doesthedogdie.com/media/$mediaId',
              'searchUrl': defaultSearchUrl,
              'triggers': triggers,
              'safe': safe.take(10).toList(),
              'totalTriggers': triggers.length,
            };

            _cache[cacheKey] = result;
            _cacheExpiry[cacheKey] = now.add(_cacheTtl);
            return result;
          }
        }
      } catch (_) {}
    }

    // 2. Zero-Key Fallback: Scrape public DoesTheDogDie media page directly
    final zeroKeyResult = await _fetchZeroKeyWeb(imdbId, title: title, year: year, defaultSearchUrl: defaultSearchUrl);
    if (zeroKeyResult != null) {
      _cache[cacheKey] = zeroKeyResult;
      _cacheExpiry[cacheKey] = now.add(_cacheTtl);
      return zeroKeyResult;
    }

    // 3. Fallback: Provide direct link to DoesTheDogDie search
    final fallback = {
      'success': true,
      'matched': false,
      'title': query,
      'url': defaultSearchUrl,
      'searchUrl': defaultSearchUrl,
      'triggers': <dynamic>[],
      'safe': <dynamic>[],
      'totalTriggers': 0,
      'message': 'Open on DoesTheDogDie to view content advisories',
    };
    _cache[cacheKey] = fallback;
    _cacheExpiry[cacheKey] = now.add(const Duration(hours: 6));
    return fallback;
  }

  static const Map<String, String> _ajaxHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'text/html, */*; q=0.01',
    'X-Requested-With': 'XMLHttpRequest',
  };

  /// Scrapes DoesTheDogDie public pages without needing an API key
  Future<Map<String, dynamic>?> _fetchZeroKeyWeb(
    String imdbId, {
    String? title,
    int? year,
    required String defaultSearchUrl,
  }) async {
    try {
      final query = (title != null && title.trim().isNotEmpty) ? title.trim() : imdbId;
      if (query.trim().isEmpty) return null;

      final searchUrl = Uri.parse('https://www.doesthedogdie.com/search?q=${Uri.encodeComponent(query.trim())}');
      final searchRes = await http.get(searchUrl, headers: _ajaxHeaders).timeout(const Duration(seconds: 5));
      if (searchRes.statusCode != 200) return null;

      final html = searchRes.body;
      final mediaMatch = RegExp(r'data-item-id="(\d+)"').firstMatch(html) ?? RegExp(r'href="/media/(\d+)"').firstMatch(html);
      if (mediaMatch == null) return null;

      final mediaIdStr = mediaMatch.group(1);
      final mediaId = int.tryParse(mediaIdStr ?? '0');
      if (mediaId == null || mediaId == 0) return null;

      final itemUrl = Uri.parse('https://www.doesthedogdie.com/media/$mediaId');
      final itemRes = await http.get(itemUrl, headers: _browserHeaders).timeout(const Duration(seconds: 6));
      if (itemRes.statusCode != 200) return null;

      final itemHtml = itemRes.body;
      final titleMatch = RegExp(r'<title>(.*?)<\/title>').firstMatch(itemHtml);
      var pageTitle = titleMatch?.group(1) ?? query;
      pageTitle = pageTitle.replaceAll(' - DoesTheDogDie.com', '').trim();

      final triggers = <Map<String, dynamic>>[];
      final safe = <Map<String, dynamic>>[];

      final containerRegex = RegExp(r'<div class="topicRowContainerContainer"[^>]*data-answer="(yes|no)"[^>]*>([\s\S]*?)(?=<div class="topicRowContainerContainer"|<div class="topicGroup"|<\/body|$)');
      for (final containerMatch in containerRegex.allMatches(itemHtml)) {
        final answer = containerMatch.group(1);
        final block = containerMatch.group(2) ?? '';
        final topicMatch = RegExp(r'<div class="name"><a[^>]*>(.*?)<\/a><\/div>').firstMatch(block);
        if (topicMatch == null) continue;
        final topic = topicMatch.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
        if (topic.isEmpty) continue;

        final commentMatch = RegExp(r'<div class="commentText"><span>(.*?)<\/span>').firstMatch(block);
        final comment = commentMatch?.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim();

        if (answer == 'yes') {
          triggers.add({
            'topic': topic,
            'yes': 1,
            'no': 0,
            if (comment != null && comment.isNotEmpty) 'comment': comment,
          });
        } else if (answer == 'no') {
          safe.add({
            'topic': topic,
            'yes': 0,
            'no': 1,
            if (comment != null && comment.isNotEmpty) 'comment': comment,
          });
        }
      }

      return {
        'success': true,
        'matched': true,
        'mediaId': mediaId,
        'title': pageTitle,
        'url': itemUrl.toString(),
        'searchUrl': defaultSearchUrl,
        'triggers': triggers,
        'safe': safe.take(10).toList(),
        'totalTriggers': triggers.length,
        'isZeroKey': true,
      };
    } catch (_) {
      return null;
    }
  }
}
