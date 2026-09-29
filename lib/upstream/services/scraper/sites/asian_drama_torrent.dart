import 'dart:async';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../../utils/torrent/parse_torrent_title.dart';

/// Asian Drama Torrent Scraper (K-Drama, J-Drama, C-Drama)
/// Queries Nyaa Live-Action category (c=6_1) & Asian drama trackers
/// Credits: AsianDrama / Nyaa Live-Action Community
class AsianDramaTorrentScraper extends StreamScraper {
  @override
  String get name => 'AsianDrama (Torrents)';

  @override
  String get providerId => 'asiandramatorrent';

  @override
  String get providerName => 'AsianDrama';

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
      query += ' E$epStr';
    } else if (type == 'movie' && year != null) {
      query += ' $year';
    }

    final titleParser = ParseTorrentTitle();

    for (final mirror in _mirrors) {
      try {
        // c=6_1 is Live Action - English-translated (K-Drama, J-Drama, C-Drama)
        final uri = Uri.parse('$mirror/?page=rss&q=${Uri.encodeComponent(query)}&c=6_1&s=seeders&o=desc');
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
            name: 'AsianDrama (Torrents)',
            addonName: 'AsianDrama Community',
            title: '$rawTitle\n$size 👥 $seeders',
            infoHash: hash,
            url: magnetUrl,
            description: size,
          );
        }
        break; // Successfully fetched
      } catch (_) {}
    }
  }
}
