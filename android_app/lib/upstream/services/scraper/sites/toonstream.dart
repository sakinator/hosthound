import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// ToonStream Scraper for Hostreamio.
/// Dedicated provider for Hindi Dubbed Anime, Cartoons, and Animated Series.
class ToonStreamScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'toonstream';

  @override
  String get providerName => 'ToonStream';

  static const List<String> _baseUrls = [
    'https://toonstream.us',
    'https://toonstream.co',
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
        final articles = doc.querySelectorAll('article a, .film-detail a, .item-thumbnail a, a[rel="bookmark"]');

        for (final art in articles) {
          final link = art.attributes['href'];
          final postTitle = art.text.trim();
          if (link == null || link.isEmpty || !link.startsWith('http')) continue;

          final firstWord = cleanTitle.split(' ').first.toLowerCase();
          if (!postTitle.toLowerCase().contains(firstWord) && !link.toLowerCase().contains(firstWord)) continue;

          yield StreamSource(
            name: 'ToonStream',
            title: '🍙 🇮🇳 Hindi Dubbed Anime / Cartoon Stream',
            url: link,
            addonName: 'PlayTorrioHTTP',
            providerId: providerId,
            providerName: providerName,
            behaviorHints: {
              'notWebReady': false,
            },
          );
        }
        break;
      } catch (_) {}
    }
  }
}
