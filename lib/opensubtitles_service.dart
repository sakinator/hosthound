import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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
  static const int _maxCachedSubtitles = 20;

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

  /// Downloads a subtitle file to a temporary cache, decompresses if gzipped,
  /// limits total cached subtitles to [_maxCachedSubtitles] (clearing oldest),
  /// and returns the local file path for libmpv.
  Future<String?> downloadSubtitle(String url, {String? subId}) async {
    if (url.isEmpty) return null;
    try {
      final cacheDir = Directory('${Directory.systemTemp.path}/hostreamio_subs');
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      final key = subId != null && subId.isNotEmpty
          ? subId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')
          : md5.convert(utf8.encode(url)).toString();
      final filePath = '${cacheDir.path}/sub_$key.srt';
      final file = File(filePath);

      if (file.existsSync() && file.lengthSync() > 0) {
        try {
          file.setLastModifiedSync(DateTime.now());
        } catch (_) {}
        return file.path;
      }

      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        List<int> bytes = res.bodyBytes;
        // Check if payload is gzip-compressed (magic bytes 0x1f, 0x8b)
        if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
          try {
            bytes = gzip.decode(bytes);
          } catch (_) {}
        }

        await file.writeAsBytes(bytes);
        try {
          file.setLastModifiedSync(DateTime.now());
        } catch (_) {}

        // Prune cache to maximum 20 downloaded subtitle files in total
        _pruneSubtitleCache(cacheDir);

        return file.path;
      }
    } catch (e) {
      print('[OpenSubtitles] Download error for $url: $e');
    }
    return null;
  }

  void _pruneSubtitleCache(Directory cacheDir) {
    try {
      if (!cacheDir.existsSync()) return;
      final files = cacheDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.srt'))
          .toList();

      if (files.length > _maxCachedSubtitles) {
        files.sort((a, b) {
          try {
            return a.lastModifiedSync().compareTo(b.lastModifiedSync());
          } catch (_) {
            return 0;
          }
        });

        final toDeleteCount = files.length - _maxCachedSubtitles;
        for (int i = 0; i < toDeleteCount; i++) {
          try {
            files[i].deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      print('[OpenSubtitles] Cache pruning error: $e');
    }
  }
}
