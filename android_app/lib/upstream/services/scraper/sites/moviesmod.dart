import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// MoviesMod Scraper for Hostreamio.
/// Massive library of Hollywood, Bollywood & Indian OTT releases (Netflix, Prime, Hotstar, SonyLIV, Zee5).
/// Extracts 4K UHD, 1080p FHD, 720p HD, and 480p SD cloud streaming links.
class MoviesModScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'moviesmod';

  @override
  String get providerName => 'MoviesMod';

  static const List<String> _baseUrls = [
    'https://moviesmod.ai.in',
    'https://moviesmod.org',
    'https://moviesmod.cc',
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
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 5));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final articles = doc.querySelectorAll('article, .latestPost, div.post-item, h2.entry-title a, a[rel="bookmark"]');

        final seenLinks = <String>{};

        for (final art in articles) {
          final a = art.localName == 'a' ? art : art.querySelector('a');
          final link = a?.attributes['href'] ?? art.attributes['href'];
          final postTitle = (a?.attributes['title'] ?? art.text).trim();
          if (link == null || link.isEmpty || !link.startsWith('http')) continue;
          if (seenLinks.contains(link)) continue;
          seenLinks.add(link);

          // Verify match
          final firstWord = cleanTitle.split(' ').first.toLowerCase();
          if (!postTitle.toLowerCase().contains(firstWord) && !link.toLowerCase().contains(firstWord)) continue;

          // Fetch detail post
          final postRes = await http.get(Uri.parse(link), headers: _headers).timeout(const Duration(seconds: 5));
          if (postRes.statusCode != 200) continue;

          final postDoc = html_parser.parse(postRes.body);
          final downloadLinks = postDoc.querySelectorAll(
            'a[href*="modpro.blog"], a[href*="gdrivepro"], a[href*="thenaukriadda"], a[href*="drive"], a[href*="fast"]',
          );

          for (final dl in downloadLinks) {
            final targetUrl = dl.attributes['href'];
            if (targetUrl == null || targetUrl.isEmpty) continue;
            if (targetUrl.contains('facebook') || targetUrl.contains('twitter') || targetUrl.contains('telegram')) {
              continue;
            }

            final parentText = dl.parent?.text.trim() ?? dl.text.trim();
            final quality = parentText.contains('2160p') || parentText.contains('4K') || parentText.contains('4k')
                ? '4K UHD'
                : parentText.contains('1080p')
                    ? '1080p FHD'
                    : parentText.contains('720p')
                        ? '720p HD'
                        : 'HD';

            final isHindi = parentText.toLowerCase().contains('hindi') ||
                parentText.toLowerCase().contains('dual') ||
                postTitle.toLowerCase().contains('hindi');

            yield StreamSource(
              name: 'MoviesMod ($quality)',
              title: '⚡ ${isHindi ? "🇮🇳 Hindi • " : ""}$quality MoviesMod Cloud Stream',
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
