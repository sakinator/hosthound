import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class DtddTrigger {
  final String topic;
  final int yesVotes;
  final int noVotes;
  final String? comment;

  DtddTrigger({
    required this.topic,
    required this.yesVotes,
    required this.noVotes,
    this.comment,
  });

  Map<String, dynamic> toJson() => {
    'topic': topic,
    'yes': yesVotes,
    'no': noVotes,
    if (comment != null && comment!.isNotEmpty) 'comment': comment,
  };
}

class DtddService {
  static final DtddService instance = DtddService._();
  DtddService._();

  static const String _apiBase = 'https://api.doesthedogdie.com';
  static final Map<String, Map<String, dynamic>> _cache = {};
  static final Map<String, DateTime> _cacheExpiry = {};
  static const Duration _cacheTtl = Duration(days: 7);

  /// Fetches content warnings and trigger advisories from DoesTheDogDie for a given IMDb ID or title.
  Future<Map<String, dynamic>> getContentWarnings(
    String rawId, {
    String? title,
    int? year,
  }) async {
    String imdbId = rawId.trim();
    if (imdbId.contains(':')) {
      imdbId = imdbId.split(':')[0];
    }

    final cacheKey = imdbId.isNotEmpty ? imdbId : (title ?? '').toLowerCase();
    final now = DateTime.now();

    if (_cache.containsKey(cacheKey)) {
      final expiry = _cacheExpiry[cacheKey];
      if (expiry != null && now.isBefore(expiry)) {
        return _cache[cacheKey]!;
      }
    }

    final apiKey = AddonConfig.instance.dtddApiKey.trim();

    // If no API key configured, check if FlareSolverr is available or prompt user
    if (apiKey.isEmpty) {
      if (AddonConfig.instance.proxyResolverUrl.isNotEmpty) {
        final fsResult = await _fetchViaFlareSolverr(imdbId, title: title);
        if (fsResult != null) {
          _cache[cacheKey] = fsResult;
          _cacheExpiry[cacheKey] = now.add(_cacheTtl);
          return fsResult;
        }
      }

      return {
        'success': false,
        'needKey': true,
        'message': 'Enter your free DoesTheDogDie API key in Settings (doesthedogdie.com/profile)',
        'signupUrl': 'https://www.doesthedogdie.com/profile',
      };
    }

    try {
      final headers = {
        'Accept': 'application/json',
        'X-API-KEY': apiKey,
        'User-Agent': 'Hostreamio/1.0',
      };

      int? mediaId;
      String? mediaName;

      // 1. Search by IMDb ID if available
      if (imdbId.startsWith('tt')) {
        final searchUri = Uri.parse('$_apiBase/dddsearch?imdb=$imdbId');
        final res = await http.get(searchUri, headers: headers).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final items = (data['items'] as List?) ?? [];
          if (items.isNotEmpty) {
            mediaId = items[0]['id'] as int?;
            mediaName = items[0]['name']?.toString();
          }
        }
      }

      // 2. Fall back to title search if no match by IMDb ID
      if (mediaId == null && title != null && title.trim().isNotEmpty) {
        final searchUri = Uri.parse('$_apiBase/dddsearch?q=${Uri.encodeComponent(title.trim())}');
        final res = await http.get(searchUri, headers: headers).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final items = (data['items'] as List?) ?? [];
          if (items.isNotEmpty) {
            if (year != null) {
              for (final it in items) {
                final itYear = it['releaseYear']?.toString();
                if (itYear != null && itYear.contains(year.toString())) {
                  mediaId = it['id'] as int?;
                  mediaName = it['name']?.toString();
                  break;
                }
              }
            }
            if (mediaId == null) {
              mediaId = items[0]['id'] as int?;
              mediaName = items[0]['name']?.toString();
            }
          }
        }
      }

      if (mediaId == null) {
        final notFound = {
          'success': true,
          'matched': false,
          'message': 'No entry found on DoesTheDogDie for this title',
          'triggers': <dynamic>[],
          'safe': <dynamic>[],
        };
        _cache[cacheKey] = notFound;
        _cacheExpiry[cacheKey] = now.add(const Duration(hours: 12));
        return notFound;
      }

      // 3. Fetch detailed triggers for the media item
      final mediaUri = Uri.parse('$_apiBase/media/$mediaId');
      final res = await http.get(mediaUri, headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        return {
          'success': false,
          'message': 'DTDD API returned HTTP ${res.statusCode}',
        };
      }

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

      // Sort triggers by yes vote count descending
      triggers.sort((a, b) => (b['yes'] as int).compareTo(a['yes'] as int));
      safe.sort((a, b) => (b['no'] as int).compareTo(a['no'] as int));

      final result = {
        'success': true,
        'matched': true,
        'mediaId': mediaId,
        'title': mediaName ?? data['name']?.toString() ?? '',
        'url': 'https://www.doesthedogdie.com/media/$mediaId',
        'triggers': triggers,
        'safe': safe.take(10).toList(),
        'totalTriggers': triggers.length,
      };

      _cache[cacheKey] = result;
      _cacheExpiry[cacheKey] = now.add(_cacheTtl);
      return result;
    } catch (e) {
      return {
        'success': false,
        'message': 'Error querying DoesTheDogDie: $e',
      };
    }
  }

  /// Optional fallback via FlareSolverr proxy solver if available
  Future<Map<String, dynamic>?> _fetchViaFlareSolverr(String imdbId, {String? title}) async {
    try {
      final fsUrl = AddonConfig.instance.proxyResolverUrl;
      final endpoint = fsUrl.endsWith('/v1') ? fsUrl : '$fsUrl/v1';
      final targetUrl = imdbId.startsWith('tt')
          ? 'https://www.doesthedogdie.com/search?q=$imdbId'
          : 'https://www.doesthedogdie.com/search?q=${Uri.encodeComponent(title ?? '')}';

      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'cmd': 'request.get',
          'url': targetUrl,
          'maxTimeout': 15000,
        }),
      ).timeout(const Duration(seconds: 16));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final html = data['solution']?['response']?.toString() ?? '';
        final mediaMatch = RegExp(r'/media/(\d+)').firstMatch(html);
        if (mediaMatch != null) {
          final mediaId = mediaMatch.group(1);
          return {
            'success': true,
            'matched': true,
            'mediaId': int.tryParse(mediaId ?? '0'),
            'url': 'https://www.doesthedogdie.com/media/$mediaId',
            'message': 'View full warnings on DoesTheDogDie',
            'triggers': <dynamic>[],
            'safe': <dynamic>[],
          };
        }
      }
    } catch (_) {}
    return null;
  }
}
