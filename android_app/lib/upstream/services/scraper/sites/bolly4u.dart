import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// Bolly4u High-Speed Stream Scraper for PlayTorrio / Hostreamio.
/// Uses instant static JSON search index (35,000+ titles) + high-speed torrent & cloud links.
class Bolly4uScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'bolly4u';

  @override
  String get providerName => 'Bolly4u';

  static const List<String> _indexUrls = [
    'https://bolly4u.day/wp-content/uploads/search-index.json',
    'https://bolly4u.org/wp-content/uploads/search-index.json',
  ];

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  // In-memory cache for search index so it's only fetched once per session
  static List<Map<String, dynamic>>? _cachedIndex;
  static DateTime? _lastFetch;

  Future<List<Map<String, dynamic>>> _loadIndex() async {
    if (_cachedIndex != null && _lastFetch != null && DateTime.now().difference(_lastFetch!).inMinutes < 60) {
      return _cachedIndex!;
    }

    for (final u in _indexUrls) {
      try {
        final res = await http.get(Uri.parse(u), headers: _headers).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final rawList = (data is List ? data : data['items']) as List;
          _cachedIndex = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _lastFetch = DateTime.now();
          return _cachedIndex!;
        }
      } catch (_) {}
    }
    return _cachedIndex ?? [];
  }

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async* {
    final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), ' ').trim().toLowerCase();
    final firstWord = cleanTitle.split(' ').first;
    if (firstWord.isEmpty) return;

    final index = await _loadIndex();
    if (index.isEmpty) return;

    final matches = <Map<String, dynamic>>[];
    for (final item in index) {
      final itemTitle = (item['t'] ?? '').toString().toLowerCase();
      if (!itemTitle.contains(firstWord)) continue;

      // Check full title match
      if (cleanTitle.split(' ').every((w) => itemTitle.contains(w))) {
        if (year != null && itemTitle.contains(year.toString())) {
          matches.insert(0, item); // Exact year match prioritized
        } else {
          matches.add(item);
        }
      }
    }

    final seenHashes = <String>{};

    for (final m in matches.take(3)) {
      final postUrl = (m['u'] ?? '').toString();
      if (postUrl.isEmpty || !postUrl.startsWith('http')) continue;

      http.Response postRes;
      try {
        postRes = await http.get(Uri.parse(postUrl), headers: _headers).timeout(const Duration(seconds: 5));
      } catch (_) {
        continue;
      }
      if (postRes.statusCode != 200) continue;

      final postDoc = html_parser.parse(postRes.body);
      final rawTitle = (m['t'] ?? title).toString();
      final isHindi = rawTitle.toLowerCase().contains('hindi') || rawTitle.toLowerCase().contains('dual');

      // Look for torrent infohashes
      final torrentLinks = postDoc.querySelectorAll('a[href*="/save/"], a[href*="magnet:"]');
      for (final tl in torrentLinks) {
        final href = tl.attributes['href'] ?? '';
        final hashMatch = RegExp(r'[a-fA-F0-9]{40}').firstMatch(href);
        if (hashMatch != null) {
          final hash = hashMatch.group(0)!.toLowerCase();
          if (!seenHashes.add(hash)) continue;

          final btnText = tl.parent?.text.trim() ?? tl.text.trim();
          final quality = btnText.contains('2160p') || btnText.contains('4K')
              ? '4K UHD'
              : btnText.contains('1080p')
                  ? '1080p FHD'
                  : btnText.contains('720p')
                      ? '720p HD'
                      : btnText.contains('480p')
                          ? '480p SD'
                          : 'HD';

          final magnet = 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(rawTitle)}&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce';

          yield StreamSource(
            name: 'Bolly4u ($quality)',
            title: '⚡ ${isHindi ? "🇮🇳 Hindi • " : ""}$quality Bolly4u Direct Stream (Cloud/Debrid)',
            url: magnet,
            addonName: 'PlayTorrioHTTP',
            providerId: providerId,
            providerName: providerName,
            behaviorHints: {
              'notWebReady': false,
            },
          );
        }
      }
    }
  }
}
