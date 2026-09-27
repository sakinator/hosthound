import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// DramaDay Asian Drama / K-Drama Stream Scraper for PlayTorrio / Hostreamio.
/// Resolves K-Dramas, C-Dramas, J-Dramas directly from dramaday.me.
class DramaDayScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'dramaday';

  @override
  String get providerName => 'DramaDay';

  static const List<String> _baseUrls = [
    'https://dramaday.me',
    'https://dramaday.net',
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
    final epNum = episode ?? 1;
    final epStr = epNum.toString().padLeft(2, '0');
    final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final firstWord = cleanTitle.split(' ').first.toLowerCase();
    if (firstWord.isEmpty) return;

    final seenUrls = <String>{};

    for (final base in _baseUrls) {
      try {
        final searchUrl = Uri.parse('$base/?s=${Uri.encodeComponent(cleanTitle)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 5));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final postLinks = doc.querySelectorAll('h2 a, h3 a, article a');
        if (postLinks.isEmpty) continue;

        String? dramaPageUrl;
        String? dramaPageTitle;

        for (final a in postLinks) {
          final postTitle = a.text.trim();
          final href = a.attributes['href'];
          if (href == null || href.isEmpty || !href.startsWith('http')) continue;

          final lower = postTitle.toLowerCase();
          // Skip soundtrack / OST posts
          if (lower.contains('ost') || lower.contains('soundtrack')) continue;

          if (lower.contains(firstWord)) {
            dramaPageUrl = href;
            dramaPageTitle = postTitle;
            break;
          }
        }

        if (dramaPageUrl == null) continue;

        // Fetch detail page
        final pageRes = await http.get(Uri.parse(dramaPageUrl), headers: _headers).timeout(const Duration(seconds: 6));
        if (pageRes.statusCode != 200) continue;

        final pageDoc = html_parser.parse(pageRes.body);

        if (type == 'series' || episode != null) {
          // Look for episode-specific container
          final containers = pageDoc.querySelectorAll('p, tr, div');
          for (final c in containers) {
            final t = c.text.trim();
            final matchesEp = t.startsWith('$epStr ') ||
                t.startsWith('Episode $epNum') ||
                t.startsWith('EP $epNum') ||
                t.startsWith('Ep $epNum') ||
                t.startsWith('$epNum ');

            if (!matchesEp) continue;

            final quality = t.contains('1080p')
                ? '1080p FHD'
                : t.contains('720p')
                    ? '720p HD'
                    : t.contains('540p') || t.contains('480p')
                        ? '540p SD'
                        : 'HD';

            final links = c.querySelectorAll('a[href]');
            for (final l in links) {
              final href = l.attributes['href'] ?? '';
              if (href.isEmpty || !href.startsWith('http')) continue;
              if (!seenUrls.add(href)) continue;

              final hosterName = l.text.trim().isNotEmpty ? l.text.trim() : 'Cloud Stream';

              yield StreamSource(
                name: 'DramaDay ($quality)',
                title: '⚡ 🇰🇷 $cleanTitle Ep $epNum • $quality [$hosterName] (Non-Torrent)',
                url: href,
                addonName: 'PlayTorrioHTTP',
                providerId: providerId,
                providerName: providerName,
                behaviorHints: {
                  'notWebReady': false,
                },
              );
            }
            break; // Found episode
          }
        } else {
          // Movie mode
          final links = pageDoc.querySelectorAll('a[href*="dddrive"], a[href*="pixeldrain"], a[href*="mega.nz"], a[href*="1fichier"]');
          for (final l in links) {
            final href = l.attributes['href'] ?? '';
            if (href.isEmpty || !href.startsWith('http')) continue;
            if (!seenUrls.add(href)) continue;

            final hosterName = l.text.trim().isNotEmpty ? l.text.trim() : 'Direct';
            yield StreamSource(
              name: 'DramaDay (HD)',
              title: '⚡ 🇰🇷 $cleanTitle • HD [$hosterName] (Non-Torrent)',
              url: href,
              addonName: 'PlayTorrioHTTP',
              providerId: providerId,
              providerName: providerName,
              behaviorHints: {
                'notWebReady': false,
              },
            );
          }
        }

        if (seenUrls.isNotEmpty) break;
      } catch (_) {}
    }
  }
}
