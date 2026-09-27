import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// UHDMovies Scraper for Hostreamio.
/// Dedicated provider for 4K UHD, HDR, Dolby Vision, 10-Bit HEVC, and 1080p FHD cloud links.
class UHDMoviesScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'uhdmovies';

  @override
  String get providerName => 'UHDMovies';

  static const List<String> _baseUrls = [
    'https://uhdmovies.my',
    'https://uhdmovies.autos',
    'https://uhdmovies.site',
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
        final searchUrl = Uri.parse('$base/?s=${Uri.encodeComponent(query)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final articles = doc.querySelectorAll('article.post-item, div.post-item, .entry-title a, article a');

        for (final art in articles) {
          final link = art.attributes['href'] ?? art.querySelector('a')?.attributes['href'];
          final postTitle = art.text.trim();
          if (link == null || link.isEmpty || !link.startsWith('http')) continue;

          // Check if post title matches our movie
          final firstWord = cleanTitle.split(' ').first.toLowerCase();
          if (!postTitle.toLowerCase().contains(firstWord)) continue;

          // Fetch post page
          final postRes = await http.get(Uri.parse(link), headers: _headers).timeout(const Duration(seconds: 4));
          if (postRes.statusCode != 200) continue;

          final postDoc = html_parser.parse(postRes.body);
          final downloadButtons = postDoc.querySelectorAll(
            'a[href*="drive"], a[href*="seed"], a[href*="hubcloud"], a[href*="thenaukriadda"], a[href*="unblockedgames"], a[href*="driveseed"]',
          );

          for (final btn in downloadButtons) {
            final targetUrl = btn.attributes['href'];
            if (targetUrl == null || targetUrl.isEmpty) continue;
            if (targetUrl.contains('facebook') || targetUrl.contains('twitter') || targetUrl.contains('telegram')) {
              continue;
            }

            final btnText = btn.parent?.text.trim() ?? btn.text.trim();
            final quality = btnText.contains('2160p') || btnText.contains('4K') || btnText.contains('4k')
                ? '4K UHD HDR'
                : btnText.contains('1080p')
                    ? '1080p FHD'
                    : btnText.contains('720p')
                        ? '720p HD'
                        : 'HD';

            final isHindi = btnText.toLowerCase().contains('hindi') || btnText.toLowerCase().contains('dual');

            yield StreamSource(
              name: 'UHDMovies ($quality)',
              title: '💎 ${isHindi ? "🇮🇳 Hindi • " : ""}$quality UHD Cloud Stream',
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
        break;
      } catch (_) {}
    }
  }
}
