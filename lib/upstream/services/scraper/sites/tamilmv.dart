import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../../utils/torrent/parse_torrent_title.dart';

/// 1TamilMV & Indian Regional Torrents Scraper (Hindi, Tamil, Telugu, Malayalam, Kannada)
/// Credits: 1TamilMV / TamilBlasters Desi Community
class TamilmvScraper extends StreamScraper {
  @override
  String get name => '1TamilMV (Desi)';

  @override
  String get providerId => 'tamilmv';

  @override
  String get providerName => '1TamilMV';

  @override
  bool get isTorrent => true;

  static const List<String> _domains = [
    'https://www.1tamilmv.yt',
    'https://www.1tamilmv.vet',
    'https://www.1tamilmv.cz',
    'https://www.1tamilmv.mx',
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
    String query = title.trim();
    if (type == 'series' && season != null) {
      final s = season.toString().padLeft(2, '0');
      query += ' S$s';
    } else if (type == 'movie' && year != null) {
      query += ' $year';
    }

    final titleParser = ParseTorrentTitle();
    final cleanSearchTitle = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    for (final domain in _domains) {
      try {
        final searchUrl = Uri.parse('$domain/index.php?/search/&q=${Uri.encodeComponent(query)}&type=forums_topic');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 5));

        if (res.statusCode != 200 || res.body.isEmpty) continue;

        final doc = parser.parse(res.body);
        final topicLinks = doc.querySelectorAll('.ipsStreamItem_title a[href*="/topic/"]');
        if (topicLinks.isEmpty) continue;

        // Inspect top 3 relevant topics to extract magnet links
        int topicCount = 0;
        for (final linkEl in topicLinks) {
          if (topicCount >= 3) break;
          final topicUrl = linkEl.attributes['href'];
          final topicText = linkEl.text.trim();
          if (topicUrl == null || topicUrl.isEmpty) continue;

          // Quick relevance check
          final lowerTopic = topicText.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (!lowerTopic.contains(cleanSearchTitle)) continue;

          topicCount++;

          try {
            final topicRes = await http.get(Uri.parse(topicUrl), headers: _headers).timeout(const Duration(seconds: 4));
            if (topicRes.statusCode != 200) continue;

            final topicDoc = parser.parse(topicRes.body);
            final magnets = topicDoc.querySelectorAll('a[href^="magnet:"]');

            for (final mEl in magnets) {
              final magnet = mEl.attributes['href'];
              if (magnet == null || magnet.isEmpty) continue;

              final hashMatch = RegExp(r'urn:btih:([a-fA-F0-9]{40}|[a-zA-Z0-9]{32})', caseSensitive: false).firstMatch(magnet);
              final infoHash = hashMatch?.group(1);
              if (infoHash == null) continue;

              final dnMatch = RegExp(r'dn=([^&]+)').firstMatch(magnet);
              final rawTitle = dnMatch != null
                  ? Uri.decodeComponent(dnMatch.group(1)!)
                  : topicText;

              final parsed = titleParser.parse(rawTitle);
              final quality = parsed['resolution']?.toString();

              yield StreamSource(
                name: '1TamilMV (Desi)',
                addonName: '1TamilMV Desi Community',
                title: '$rawTitle\n⚡ 1TamilMV Indian Regional Release',
                infoHash: infoHash,
                url: magnet,
              );
            }
          } catch (_) {}
        }

        if (topicCount > 0) break; // Found matches on this domain
      } catch (_) {}
    }
  }
}
