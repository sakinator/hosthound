import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';
import '../../../utils/torrent/parse_torrent_title.dart';

/// EZTV TV Shows Torrent Scraper
/// Credits: EZTV Community API
class EztvScraper extends StreamScraper {
  @override
  String get name => 'EZTV';

  @override
  String get providerId => 'eztv';

  @override
  String get providerName => 'EZTV';

  @override
  bool get isTorrent => true;

  static const List<String> _apiBases = [
    'https://eztvx.to/api',
    'https://eztv.re/api',
    'https://eztv.wf/api',
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
    if (type == 'movie') return; // EZTV is dedicated to TV series

    final cleanImdb = (imdbId != null && imdbId.isNotEmpty)
        ? imdbId.replaceAll(RegExp(r'[^0-9]'), '')
        : '';

    final titleParser = ParseTorrentTitle();

    for (final base in _apiBases) {
      try {
        final queryParam = cleanImdb.isNotEmpty
            ? 'imdb_id=$cleanImdb'
            : 'query=${Uri.encodeComponent(title)}';

        final uri = Uri.parse('$base/get-torrents?$queryParam&limit=50');
        final res = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 5));

        if (res.statusCode != 200 || res.body.isEmpty) continue;

        final data = jsonDecode(res.body);
        if (data is! Map || data['torrents'] is! List) continue;

        final torrents = data['torrents'] as List;
        for (final t in torrents) {
          final tSeason = int.tryParse(t['season']?.toString() ?? '');
          final tEpisode = int.tryParse(t['episode']?.toString() ?? '');

          if (season != null && tSeason != null && tSeason != season) continue;
          if (episode != null && tEpisode != null && tEpisode != episode) continue;

          final rawTitle = t['title']?.toString() ?? t['filename']?.toString() ?? '';
          final hash = t['hash']?.toString().trim();
          final magnetUrl = t['magnet_url']?.toString() ?? '';

          final effectiveHash = (hash != null && hash.isNotEmpty)
              ? hash
              : RegExp(r'urn:btih:([a-fA-F0-9]{40})', caseSensitive: false).firstMatch(magnetUrl)?.group(1);

          if (effectiveHash == null) continue;

          final seeds = t['seeds'] ?? 0;
          final sizeBytes = int.tryParse(t['size_bytes']?.toString() ?? '0') ?? 0;
          final sizeMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
          final sizeStr = sizeBytes > 1024 * 1024 * 1024
              ? '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
              : '$sizeMb MB';

          final parsed = titleParser.parse(rawTitle);
          final quality = parsed['resolution']?.toString();

          yield StreamSource(
            name: 'EZTV',
            addonName: 'EZTV Community',
            title: '$rawTitle\n$sizeStr 👥 $seeds',
            infoHash: effectiveHash,
            url: magnetUrl.isNotEmpty ? magnetUrl : 'magnet:?xt=urn:btih:$effectiveHash',
            description: sizeStr,
          );
        }
        break; // Successfully fetched from mirror
      } catch (_) {}
    }
  }
}
