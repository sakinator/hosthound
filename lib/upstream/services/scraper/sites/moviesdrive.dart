import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// MoviesDrive Scraper for Hostreamio.
/// Instant Typesense JSON search + HubCloud / PixelDrain / 10Gbps stream extraction.
class MoviesDriveScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'moviesdrive';

  @override
  String get providerName => 'MoviesDrive';

  static const List<String> _baseUrls = [
    'https://new4.moviesdrive.christmas',
    'https://moviesdrive.world',
    'https://moviesdrives.cfd',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async* {
    final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final query = cleanTitle.split(' ').take(3).join(' ');

    for (final base in _baseUrls) {
      try {
        final searchUrl = Uri.parse('$base/search.php?q=${Uri.encodeComponent(query)}&page=1');
        final res = await http.get(searchUrl, headers: {
          ..._headers,
          'Referer': '$base/',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 4));

        if (res.statusCode != 200) continue;

        final searchJson = jsonDecode(res.body) as Map<String, dynamic>;
        final hits = searchJson['hits'] as List?;
        if (hits == null || hits.isEmpty) continue;

        for (final hit in hits) {
          final doc = hit['document'] as Map<String, dynamic>?;
          if (doc == null) continue;

          final postTitle = (doc['post_title'] ?? '').toString();
          final permalink = (doc['permalink'] ?? '').toString();
          final hitImdb = (doc['imdb_id'] ?? '').toString();

          if (permalink.isEmpty) continue;

          // Validate title or imdbId
          if (imdbId != null && hitImdb.isNotEmpty && hitImdb != imdbId) {
            continue;
          }
          if (!postTitle.toLowerCase().contains(cleanTitle.split(' ').first.toLowerCase())) {
            continue;
          }

          // Fetch detail page
          final pageUrl = permalink.startsWith('http') ? permalink : '$base$permalink';
          final pageRes = await http.get(Uri.parse(pageUrl), headers: _headers).timeout(const Duration(seconds: 4));
          if (pageRes.statusCode != 200) continue;

          final pageDoc = html_parser.parse(pageRes.body);
          final links = pageDoc.querySelectorAll('a[href*="hubcloud"], a[href*="vcloud"], a[href*="fastdl"]');

          for (final a in links) {
            final targetUrl = a.attributes['href'];
            if (targetUrl == null || targetUrl.isEmpty) continue;

            final btnText = a.parent?.text.trim() ?? a.text.trim();
            final quality = btnText.contains('2160p') || btnText.contains('4K')
                ? '4K UHD'
                : btnText.contains('1080p')
                    ? '1080p FHD'
                    : btnText.contains('720p')
                        ? '720p HD'
                        : 'HD';

            final isHindi = btnText.toLowerCase().contains('hindi') || btnText.toLowerCase().contains('dual');

            yield StreamSource(
              name: 'MoviesDrive ($quality)',
              title: '⚡ ${isHindi ? "🇮🇳 Hindi • " : ""}$quality HubCloud / Direct Cloud Stream',
              url: targetUrl,
              addonName: 'PlayTorrioHTTP',
              providerId: providerId,
              providerName: providerName,
              behaviorHints: {
                'notWebReady': false,
              },
            );
          }
        }
        break; // If search succeeded on this base, no need to query others
      } catch (_) {}
    }
  }
}
