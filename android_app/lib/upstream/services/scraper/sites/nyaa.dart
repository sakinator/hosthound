import 'dart:async';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../../utils/torrent/parse_torrent_title.dart';

/// Nyaa.si Anime & Asian Drama Torrent Scraper
/// Credits: Nyaa.si Community / Tokyo Toshokan
class NyaaScraper extends StreamScraper {
  @override
  String get name => 'Nyaa (Anime)';

  @override
  String get providerId => 'nyaa';

  @override
  String get providerName => 'Nyaa';

  @override
  bool get isTorrent => true;

  static const List<String> _mirrors = [
    'https://nyaa.si',
    'https://nyaa.land',
  ];

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
    if (type == 'series' && episode != null) {
      final epStr = episode.toString().padLeft(2, '0');
      query += ' $epStr';
    } else if (type == 'movie' && year != null) {
      query += ' $year';
    }

    final titleParser = ParseTorrentTitle();

    for (final mirror in _mirrors) {
      try {
        // Query English-translated Anime (1_2) sorted by seeders descending
        final uri = Uri.parse('$mirror/?page=rss&q=${Uri.encodeComponent(query)}&c=1_2&s=seeders&o=desc');
        final res = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        }).timeout(const Duration(seconds: 5));

        if (res.statusCode != 200 || res.body.isEmpty) continue;

        final itemRegex = RegExp(r'<item>(.*?)</item>', dotAll: true);
        final matches = itemRegex.allMatches(res.body);

        for (final m in matches) {
          final block = m.group(1) ?? '';
          final titleMatch = RegExp(r'<title><!\[CDATA\[(.*?)\]\]></title>|<title>(.*?)</title>').firstMatch(block);
          final rawTitle = (titleMatch?.group(1) ?? titleMatch?.group(2) ?? '').trim();
          if (rawTitle.isEmpty) continue;

          final hashMatch = RegExp(r'<nyaa:infoHash>(.*?)</nyaa:infoHash>').firstMatch(block);
          final hash = hashMatch?.group(1)?.trim();
          if (hash == null || hash.isEmpty) continue;

          final sizeMatch = RegExp(r'<nyaa:size>(.*?)</nyaa:size>').firstMatch(block);
          final size = sizeMatch?.group(1)?.trim() ?? '';

          final seedersMatch = RegExp(r'<nyaa:seeders>(.*?)</nyaa:seeders>').firstMatch(block);
          final seeders = int.tryParse(seedersMatch?.group(1)?.trim() ?? '0') ?? 0;

          final parsed = titleParser.parse(rawTitle);
          final quality = parsed['resolution']?.toString();

          final magnetUrl = 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(rawTitle)}';

          yield StreamSource(
            name: 'Nyaa (Anime)',
            addonName: 'Nyaa.si Community',
            title: '$rawTitle\n$size 👥 $seeders',
            infoHash: hash,
            url: magnetUrl,
            description: size,
          );
        }
        break; // Successfully fetched from mirror
      } catch (_) {}
    }
  }
}
