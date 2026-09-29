import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// YTS Movies Torrent Scraper
/// Credits: YTS.mx Community API
class YtsScraper extends StreamScraper {
  @override
  String get name => 'YTS';

  @override
  String get providerId => 'yts';

  @override
  String get providerName => 'YTS';

  @override
  bool get isTorrent => true;

  static const List<String> _apiBases = [
    'https://yts.mx/api/v2',
    'https://yts.lt/api/v2',
    'https://yts.do/api/v2',
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
    if (type == 'series') return; // YTS only hosts movies

    final query = (imdbId != null && imdbId.isNotEmpty) ? imdbId : title.trim();

    for (final base in _apiBases) {
      try {
        final uri = Uri.parse('$base/list_movies.json?query_term=${Uri.encodeComponent(query)}&limit=5');
        final res = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 4));

        if (res.statusCode != 200 || res.body.isEmpty) continue;

        final data = jsonDecode(res.body);
        if (data is! Map || data['status'] != 'ok') continue;

        final movies = data['data']?['movies'];
        if (movies is! List || movies.isEmpty) continue;

        for (final m in movies) {
          final movieTitle = m['title_long'] ?? m['title'] ?? title;
          final torrents = m['torrents'];
          if (torrents is! List) continue;

          for (final t in torrents) {
            final hash = t['hash']?.toString().trim();
            if (hash == null || hash.isEmpty) continue;

            final quality = t['quality']?.toString() ?? '1080p';
            final tType = t['type']?.toString().toUpperCase() ?? 'WEB';
            final size = t['size']?.toString() ?? '';
            final seeds = t['seeds'] ?? 0;

            final magnetUrl = 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent('$movieTitle [$quality] [$tType]')}'
                '&tr=udp://open.demonii.com:1337/announce'
                '&tr=udp://tracker.openbittorrent.com:80'
                '&tr=udp://tracker.coppersurfer.tk:6969';

            yield StreamSource(
              name: 'YTS',
              addonName: 'YTS.mx Community',
              title: '$movieTitle [$quality $tType]\n$size 👥 $seeds',
              infoHash: hash,
              url: magnetUrl,
              description: size,
            );
          }
        }
        break; // Successfully fetched from mirror
      } catch (_) {}
    }
  }
}
