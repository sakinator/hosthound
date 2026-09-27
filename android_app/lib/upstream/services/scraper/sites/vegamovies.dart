import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

class VegamoviesScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'vegamovies';

  @override
  String get providerName => 'Vegamovies';

  static const List<String> _baseUrls = [
    'https://vegamoviess.mobi',
    'https://vegamovie.si',
    'https://vegamovies.channel',
  ];

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
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
    final seenUrls = <String>{};

    for (final base in _baseUrls) {
      try {
        final searchUrl = Uri.parse('$base/index.php?do=search');
        http.Response res;
        try {
          res = await http.post(
            searchUrl,
            headers: {
              ..._headers,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'do': 'search',
              'subaction': 'search',
              'story': query,
            },
          ).timeout(const Duration(seconds: 5));
        } catch (_) {
          // Fallback to GET search if POST fails
          res = await http.get(
            Uri.parse('$base/?s=${Uri.encodeComponent(query)}'),
            headers: _headers,
          ).timeout(const Duration(seconds: 4));
        }

        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final articles = doc.querySelectorAll('article, .post-item, h3.entry-title, h2.entry-title');
        if (articles.isEmpty) continue;

        var matchedCount = 0;
        final firstWord = cleanTitle.split(' ').first.toLowerCase();

        for (final art in articles) {
          final aTag = art.querySelector('a') ?? (art.localName == 'a' ? art : null);
          final link = aTag?.attributes['href'];
          final postTitle = art.text.trim();
          if (link == null || link.isEmpty || !link.startsWith('http')) continue;

          // Check if post title matches our search query
          final lowerPostTitle = postTitle.toLowerCase();
          if (!lowerPostTitle.contains(firstWord)) continue;
          if (year != null && lowerPostTitle.contains(RegExp(r'\b(19\d\d|20\d\d)\b')) && !lowerPostTitle.contains(year.toString())) {
            continue; // Skip if year is present and does not match
          }

          // Fetch post page
          http.Response postRes;
          try {
            postRes = await http.get(Uri.parse(link), headers: _headers).timeout(const Duration(seconds: 5));
          } catch (_) {
            continue;
          }
          if (postRes.statusCode != 200) continue;

          final postDoc = html_parser.parse(postRes.body);
          final downloadButtons = postDoc.querySelectorAll(
            'a[href*="hubcloud"], a[href*="vcloud"], a[href*="fast-dl"], a[href*="fastdl"], a[href*="vgmlinks"], a[href*="dropgalaxy"], a[href*="nexdrive"]'
          );

          for (final btn in downloadButtons) {
            final targetUrl = btn.attributes['href'];
            if (targetUrl == null || targetUrl.isEmpty) continue;

            final btnText = btn.parent?.text.trim() ?? btn.text.trim();
            final quality = btnText.contains('2160p') || btnText.contains('4K')
                ? '4K UHD'
                : btnText.contains('1080p')
                    ? '1080p FHD'
                    : btnText.contains('720p')
                        ? '720p HD'
                        : btnText.contains('480p')
                            ? '480p SD'
                            : 'HD';

            final isHindi = btnText.toLowerCase().contains('hindi') ||
                btnText.toLowerCase().contains('dual') ||
                postTitle.toLowerCase().contains('hindi');

            if (targetUrl.contains('nexdrive')) {
              try {
                final nexRes = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(const Duration(seconds: 4));
                if (nexRes.statusCode == 200) {
                  final nexDoc = html_parser.parse(nexRes.body);
                  final directLinks = nexDoc.querySelectorAll('a[href*="fast-dl"], a[href*="vgmlinks"], a[href*="hubcloud"], a[href*="vcloud"], a[href*="dropgalaxy"]');
                  for (final nexA in directLinks) {
                    final dl = nexA.attributes['href'];
                    if (dl == null || dl.isEmpty || !seenUrls.add(dl)) continue;

                    yield StreamSource(
                      name: 'Vegamovies ($quality)',
                      title: '⚡ ${isHindi ? "🇮🇳 Hindi • " : ""}$quality Direct Cloud Stream (Non-Torrent)',
                      url: dl,
                      addonName: 'PlayTorrioHTTP',
                      providerId: providerId,
                      providerName: providerName,
                      behaviorHints: {
                        'notWebReady': false,
                      },
                    );
                  }
                }
              } catch (_) {}
            } else {
              if (!seenUrls.add(targetUrl)) continue;

              yield StreamSource(
                name: 'Vegamovies ($quality)',
                title: '⚡ ${isHindi ? "🇮🇳 Hindi • " : ""}$quality Direct Cloud Stream (Non-Torrent)',
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

          matchedCount++;
          if (matchedCount >= 2) break; // Check top 2 matching posts
        }

        if (seenUrls.isNotEmpty) break; // Succeeded, no need to query further mirrors
      } catch (_) {}
    }
  }
}
