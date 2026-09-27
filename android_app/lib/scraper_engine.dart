import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'scraper_registry.dart';
import 'config.dart';
import 'metadata_service.dart';
import 'upstream/models/stream/stream_model.dart';
import 'upstream/services/scraper/stream_scraper.dart';
import 'badge_service.dart';
import 'torbox_service.dart';

class _CachedScrape {
  final List<ScrapedStream> streams;
  final DateTime expiresAt;
  _CachedScrape(this.streams, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class ScrapedStream {
  final String name;
  final String title;
  final String url;
  final Map<String, dynamic>? behaviorHints;
  final String provider;
  final String? quality;
  final List<Map<String, dynamic>>? subtitles;

  ScrapedStream({
    required this.name,
    required this.title,
    required this.url,
    this.behaviorHints,
    required this.provider,
    this.quality,
    this.subtitles,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'description': title,
        'url': url,
        if (behaviorHints != null) 'behaviorHints': behaviorHints,
        if (subtitles != null && subtitles!.isNotEmpty) 'subtitles': subtitles,
      };
}

class ScraperEngine {
  static final ScraperEngine instance = ScraperEngine._();
  List<StreamScraper> _allScrapers = [];

  /// In-flight deduplication cache: if two Nuvio clients request the same
  /// content simultaneously we reuse the same scrape Future instead of
  /// launching 46×2 parallel requests.
  final Map<String, Future<List<ScrapedStream>>> _inFlight = {};

  /// Short-term Scrape Cache (12m TTL) for instant replay and seamless browsing
  final Map<String, _CachedScrape> _scrapeCache = {};

  /// Circuit Breaker: maps providerId to consecutive failure count
  final Map<String, int> _consecutiveFailures = {};
  /// Circuit Breaker: maps providerId to expiration of tripped state
  final Map<String, DateTime> _trippedUntil = {};

  static final HttpClient _probeClient = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 1200)
    ..badCertificateCallback = ((_, __, ___) => true);

  ScraperEngine._() {
    _initScrapers();
  }

  void _initScrapers() {
    _allScrapers = ScraperRegistry.getAllScrapers();
    print('[ScraperEngine] Registered ${_allScrapers.length} PlayTorrio HTTP scrapers.');
  }

  void reloadScrapers() {
    _inFlight.clear(); // Invalidate any in-flight results after a reload
    _scrapeCache.clear();
    _consecutiveFailures.clear();
    _trippedUntil.clear();
    _initScrapers();
  }

  List<StreamScraper> get activeScrapers {
    final cfg = AddonConfig.instance;
    return _allScrapers.where((s) => cfg.isProviderEnabled(s.providerId)).toList();
  }

  List<Map<String, dynamic>> getProviderList() {
    final cfg = AddonConfig.instance;
    return _allScrapers.map((s) {
      return {
        'id': s.providerId,
        'name': s.providerName,
        'enabled': cfg.isProviderEnabled(s.providerId),
      };
    }).toList();
  }

  Future<List<ScrapedStream>> scrapeAll({
    required MediaMetadata meta,
    required String localBaseUrl,
  }) {
    // 1. Check Short-Term Scrape Cache (instant 0ms response)
    final key = '${meta.type}|${meta.id}';
    final cached = _scrapeCache[key];
    if (cached != null && !cached.isExpired) {
      print('[ScraperEngine] Returning cached scrape for "$key" (${cached.streams.length} stream(s)).');
      // Adapt local endpoints (/torbox/play, /proxy) to requesting client's localBaseUrl (e.g. LAN TV vs PC localhost)
      final adapted = cached.streams.map((s) {
        if (s.url.contains('/torbox/play') || s.url.contains('/proxy')) {
          final uri = Uri.tryParse(s.url);
          if (uri != null && (uri.path.startsWith('/torbox/play') || uri.path.startsWith('/proxy'))) {
            final newUrl = '$localBaseUrl${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
            return ScrapedStream(
              name: s.name,
              title: s.title,
              url: newUrl,
              behaviorHints: s.behaviorHints,
              provider: s.provider,
              quality: s.quality,
              subtitles: s.subtitles,
            );
          }
        }
        return s;
      }).toList();
      return Future.value(adapted);
    }

    // 2. Deduplicate concurrent in-flight requests for the same content
    if (_inFlight.containsKey(key)) {
      print('[ScraperEngine] Deduplicating concurrent request for "$key".');
      return _inFlight[key]!;
    }

    final future = _doScrapeAll(meta: meta, localBaseUrl: localBaseUrl);
    _inFlight[key] = future;
    future.then((streams) {
      if (streams.isNotEmpty) {
        _scrapeCache[key] = _CachedScrape(streams, DateTime.now().add(const Duration(minutes: 12)));
      }
    }).whenComplete(() => _inFlight.remove(key));
    return future;
  }

  Future<List<ScrapedStream>> _doScrapeAll({
    required MediaMetadata meta,
    required String localBaseUrl,
  }) async {
    final allActive = activeScrapers;
    final now = DateTime.now();
    final scrapers = allActive.where((s) {
      final tripExp = _trippedUntil[s.providerId];
      if (tripExp != null && tripExp.isAfter(now)) {
        return false;
      }
      return true;
    }).toList();

    final cfg = AddonConfig.instance;
    final timeout = Duration(seconds: cfg.timeoutSeconds);

    print('[ScraperEngine] Scraping "${meta.title}" (${meta.year ?? 'N/A'}, ${meta.type}) '
        'across ${scrapers.length} active scrapers (${allActive.length - scrapers.length} tripped, timeout: ${cfg.timeoutSeconds}s)...');

    // Each scraper collects into its own list to avoid concurrent-write races.
    final futures = scrapers.map((scraper) async {
      final localResults = <StreamSource>[];
      try {
        final stream = scraper.scrapeStream(
          type: meta.type,
          title: meta.title,
          year: meta.year,
          season: meta.season,
          episode: meta.episode,
          imdbId: meta.imdbId,
        );
        await for (final item in stream.timeout(timeout)) {
          localResults.add(item);
        }
        _consecutiveFailures[scraper.providerId] = 0;
        _trippedUntil.remove(scraper.providerId);
      } catch (_) {
        if (localResults.isEmpty) {
          final fails = (_consecutiveFailures[scraper.providerId] ?? 0) + 1;
          _consecutiveFailures[scraper.providerId] = fails;
          if (fails >= 3) {
            _trippedUntil[scraper.providerId] = DateTime.now().add(const Duration(minutes: 10));
            print('[CircuitBreaker] Scraper ${scraper.providerId} tripped for 10m (3 consecutive failures).');
          }
        } else {
          _consecutiveFailures[scraper.providerId] = 0;
          _trippedUntil.remove(scraper.providerId);
        }
      }
      return localResults;
    });

    final perScraperResults = await Future.wait(futures);
    // Merge sequentially – no concurrent list mutation.
    final rawResults = <StreamSource>[
      for (final list in perScraperResults) ...list,
    ];

    // ── Batch TorBox Cache Check (Instant single query for all hoster URLs) ──
    final torboxKey = cfg.torboxApiKey.trim();
    final supportedHosterUrls = <String>[];
    if (torboxKey.isNotEmpty) {
      for (final src in rawResults) {
        final rawUrl = src.url ?? src.externalUrl;
        if (rawUrl != null && rawUrl.startsWith('http') && TorboxService.instance.isSupportedHoster(rawUrl)) {
          supportedHosterUrls.add(rawUrl);
        }
      }
    }
    final torboxCacheMap = supportedHosterUrls.isNotEmpty
        ? await TorboxService.instance.checkCachedBatch(supportedHosterUrls, torboxKey)
        : <String, bool>{};

    // ── Dead-Link Filter: Quick concurrent HEAD probe on direct stream URLs ──
    final deadUrls = <String>{};
    if (cfg.enableDeadLinkFilter) {
      final probeCandidates = <String>[];
      for (final src in rawResults) {
        final rawUrl = src.url ?? src.externalUrl;
        if (rawUrl != null &&
            rawUrl.startsWith('http') &&
            !rawUrl.contains('.m3u8') &&
            !rawUrl.contains('.mpd') &&
            torboxCacheMap[rawUrl] != true) {
          probeCandidates.add(rawUrl);
        }
      }
      if (probeCandidates.isNotEmpty) {
        final probeFutures = probeCandidates.take(25).map((url) async {
          final isAlive = await _probeDirectLink(url);
          if (!isAlive) deadUrls.add(url);
        });
        await Future.wait(probeFutures);
      }
    }

    final seenUrls = <String>{};
    final streamDedupeMap = <String, ScrapedStream>{};
    final finalStreams = <ScrapedStream>[];

    for (final src in rawResults) {
      final rawUrl = src.url ?? src.externalUrl;
      if (rawUrl == null || rawUrl.isEmpty || !rawUrl.startsWith('http')) continue;
      if (deadUrls.contains(rawUrl)) continue; // Filtered broken link

      String providerName = src.providerName ?? src.name ?? 'Hostreamio';
      if (providerName.toLowerCase().contains('playtorrio') || providerName.toLowerCase().contains('megascraper') || providerName.toLowerCase().contains('unbound') || providerName.toLowerCase().contains('hosthound')) {
        providerName = providerName.replaceAll(RegExp(r'PlayTorrio(HTTP)?|MegaScraper|Unbound|HostHound', caseSensitive: false), 'Hostreamio').trim();
        if (providerName.isEmpty) providerName = 'Hostreamio';
      }

      final detectedHoster = _detectHoster(rawUrl);
      if (detectedHoster != null && !providerName.toLowerCase().contains(detectedHoster.toLowerCase())) {
        providerName = '$providerName ($detectedHoster)';
      }

      // Smart Deduplication across scrapers
      if (cfg.enableDeduplication && seenUrls.contains(rawUrl)) {
        final existing = streamDedupeMap[rawUrl];
        if (existing != null && !existing.provider.contains(providerName)) {
          final updated = ScrapedStream(
            name: existing.name,
            title: '${existing.title} • Merged with $providerName',
            url: existing.url,
            behaviorHints: existing.behaviorHints,
            provider: '${existing.provider} + $providerName',
            quality: existing.quality,
            subtitles: existing.subtitles,
          );
          final idx = finalStreams.indexOf(existing);
          if (idx != -1) finalStreams[idx] = updated;
          streamDedupeMap[rawUrl] = updated;
        }
        continue;
      }
      seenUrls.add(rawUrl);

      final q = src.quality ?? '';
      final isHls = rawUrl.contains('.m3u8');
      final badge = src.getAudioBadge(mediaTitle: meta.title) ?? '';
      final headers = src.headers ?? {};

      final isSupportedHoster = torboxKey.isNotEmpty && TorboxService.instance.isSupportedHoster(rawUrl);
      final isTorboxCached = torboxCacheMap[rawUrl] == true;

      // ── Direct (Uncached) Stream Configuration ────────────────────────
      String directStreamUrl = rawUrl;
      bool isDirectProxied = false;
      if (cfg.enableProxyForHeaders && headers.isNotEmpty) {
        final headersJson = jsonEncode(headers);
        directStreamUrl = '$localBaseUrl/proxy?url=${Uri.encodeComponent(rawUrl)}'
            '&headers=${Uri.encodeComponent(headersJson)}';
        isDirectProxied = true;
      }

      final directBehaviorHints = <String, dynamic>{
        'notWebReady': !isDirectProxied && headers.isNotEmpty,
      };
      if (headers.isNotEmpty && !isDirectProxied) {
        directBehaviorHints['proxyHeaders'] = {'request': headers};
      }

      String rawTitle = src.title ?? src.name ?? meta.title;
      rawTitle = rawTitle
          .replaceAll(RegExp(r'PlayTorrio(HTTP)?|MegaScraper|Unbound|HostHound', caseSensitive: false), 'Hostreamio')
          .replaceAll(RegExp(r'\b(saket|sakinator)\b', caseSensitive: false), '')
          .trim();

      final directEnriched = BadgeService.enrichStream(
        rawTitle: rawTitle,
        mediaTitle: meta.title,
        year: meta.year,
        season: meta.season,
        episode: meta.episode,
        quality: q,
        codec: src.codec,
        audioBadge: badge,
        fileSize: src.fileSize,
        providerName: isSupportedHoster ? '$providerName [Direct]' : providerName,
        ottPlatform: meta.ottPlatform,
        isCached: false,
        isHls: isHls,
        isProxied: isDirectProxied,
      );

      final qLabel = q.isNotEmpty ? q : (isHls ? 'HLS' : 'HD');
      final subList = src.subtitles?.map((s) => {
        'id': s.language,
        'url': s.downloadUrl,
        'lang': s.language,
      }).toList();

      if (isTorboxCached) {
        // ── 1. Link is ALREADY TorBox cached: show 2 links (Cached + Direct Play) ──
        final torboxPlayUrl = '$localBaseUrl/torbox/play?url=${Uri.encodeComponent(rawUrl)}';
        final cachedEnriched = BadgeService.enrichStream(
          rawTitle: rawTitle,
          mediaTitle: meta.title,
          year: meta.year,
          season: meta.season,
          episode: meta.episode,
          quality: q,
          codec: src.codec,
          audioBadge: badge,
          fileSize: src.fileSize,
          providerName: '$providerName [TorBox Cached]',
          ottPlatform: meta.ottPlatform,
          isCached: true,
          isHls: false,
          isProxied: false,
        );

        final cachedBadge = cachedEnriched['badgeHeader'] ?? qLabel;
        final cachedStream = ScrapedStream(
          name: '⚡ TorBox [Cached]\n$cachedBadge',
          title: '${cachedEnriched['title']}\n⚡ Cached on TorBox CDN • Instant High-Speed Playback',
          url: torboxPlayUrl,
          behaviorHints: const {'notWebReady': false},
          provider: '$providerName (TorBox Cached)',
          quality: q,
          subtitles: subList,
        );
        finalStreams.add(cachedStream);
        streamDedupeMap[rawUrl] = cachedStream;

        final directBadge = directEnriched['badgeHeader'] ?? qLabel;
        final directStream = ScrapedStream(
          name: '🌐 Direct Play [$providerName]\n$directBadge',
          title: '${directEnriched['title']}\n🌐 Direct Play • Original Hoster Link',
          url: directStreamUrl,
          behaviorHints: directBehaviorHints,
          provider: providerName,
          quality: q,
          subtitles: subList,
        );
        finalStreams.add(directStream);
      } else if (isSupportedHoster) {
        // ── 2. Link is NOT cached but IS cachable: show 2 links (TorBox Start Caching + Direct Play) ──
        final headersParam = headers.isNotEmpty ? '&headers=${Uri.encodeComponent(jsonEncode(headers))}' : '';
        final cachePlayUrl = '$localBaseUrl/torbox/play?url=${Uri.encodeComponent(rawUrl)}$headersParam';

        final cacheEnriched = BadgeService.enrichStream(
          rawTitle: rawTitle,
          mediaTitle: meta.title,
          year: meta.year,
          season: meta.season,
          episode: meta.episode,
          quality: q,
          codec: src.codec,
          audioBadge: badge,
          fileSize: src.fileSize,
          providerName: '$providerName [TorBox Cachable]',
          ottPlatform: meta.ottPlatform,
          isCached: false,
          isHls: isHls,
          isProxied: false,
        );

        final cacheBadge = cacheEnriched['badgeHeader'] ?? qLabel;
        final startCachingStream = ScrapedStream(
          name: '🌐 TorBox [Start Caching]\n$cacheBadge',
          title: '${cacheEnriched['title']}\n🌐 TorBox Cachable • Click to start caching on TorBox cloud & stream',
          url: cachePlayUrl,
          behaviorHints: const {'notWebReady': false},
          provider: '$providerName (TorBox Cachable)',
          quality: q,
          subtitles: subList,
        );
        finalStreams.add(startCachingStream);

        final directBadge = directEnriched['badgeHeader'] ?? qLabel;
        final directStream = ScrapedStream(
          name: '🌐 Direct Play [$providerName]\n$directBadge',
          title: '${directEnriched['title']}\n🌐 Direct Play • Original Hoster Link',
          url: directStreamUrl,
          behaviorHints: directBehaviorHints,
          provider: providerName,
          quality: q,
          subtitles: subList,
        );
        finalStreams.add(directStream);
        streamDedupeMap[rawUrl] = directStream;
      } else {
        // ── 3. Standard Non-Hoster / Direct Stream (1 link) ──
        final directBadge = directEnriched['badgeHeader'] ?? qLabel;
        final directStream = ScrapedStream(
          name: '🌐 Direct Play [$providerName]\n$directBadge',
          title: directEnriched['title']!,
          url: directStreamUrl,
          behaviorHints: directBehaviorHints,
          provider: providerName,
          quality: q,
          subtitles: subList,
        );
        finalStreams.add(directStream);
        streamDedupeMap[rawUrl] = directStream;
      }
    }

    // ── Stream Filtering Profile: Exclude CAMs when HD content exists ──
    if (cfg.excludeCams) {
      final hasHighQuality = finalStreams.any((s) {
        final q = s.quality?.toUpperCase() ?? '';
        final n = s.name.toUpperCase();
        return q.contains('1080') || q.contains('720') || q.contains('4K') || n.contains('WEB-DL') || n.contains('BLURAY') || n.contains('REMUX');
      });
      if (hasHighQuality) {
        finalStreams.removeWhere((s) {
          final text = '${s.name} ${s.title} ${s.quality}'.toUpperCase();
          return text.contains('[CAM]') ||
              text.contains('[TELESYNC]') ||
              text.contains('[TELECINE]') ||
              text.contains('[PREDVD]') ||
              text.contains('HDCAM');
        });
      }
    }

    // ── Stream Filtering Profile: Max Resolution Cap ──
    if (cfg.maxResolution == '1080p') {
      finalStreams.removeWhere((s) {
        final q = s.quality?.toUpperCase() ?? '';
        final n = s.name.toUpperCase();
        return q.contains('4K') || q.contains('2160') || n.contains('[4K]');
      });
    } else if (cfg.maxResolution == '720p') {
      finalStreams.removeWhere((s) {
        final q = s.quality?.toUpperCase() ?? '';
        final n = s.name.toUpperCase();
        return q.contains('4K') || q.contains('2160') || q.contains('1080') || n.contains('[4K]') || n.contains('[FHD]') || n.contains('[1080P]');
      });
    }

    // ── Stream Sorting: Preferred Audio Language & Resolution ──
    final prefLang = cfg.preferredLanguage.toLowerCase().trim();
    finalStreams.sort((a, b) => _streamRank(b, prefLang).compareTo(_streamRank(a, prefLang)));

    print('[ScraperEngine] Found ${finalStreams.length} stream(s) for "${meta.title}".');
    return finalStreams;
  }

  static String? _detectHoster(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('hubcloud')) return 'HubCloud';
    if (lower.contains('driveseed') || lower.contains('drivebot')) return 'DriveSeed';
    if (lower.contains('pixeldrain')) return 'Pixeldrain';
    if (lower.contains('mega.nz') || lower.contains('mega.co.nz')) return 'Mega';
    if (lower.contains('1fichier')) return '1fichier';
    if (lower.contains('rapidgator')) return 'Rapidgator';
    if (lower.contains('turbobit')) return 'Turbobit';
    if (lower.contains('nitroflare')) return 'Nitroflare';
    if (lower.contains('katfile')) return 'Katfile';
    if (lower.contains('ddownload')) return 'DDownload';
    if (lower.contains('fastcloud') || lower.contains('fastdl')) return 'FastCloud';
    if (lower.contains('gdflix')) return 'GDFlix';
    if (lower.contains('filepress')) return 'Filepress';
    if (lower.contains('streamtape')) return 'Streamtape';
    if (lower.contains('mixdrop')) return 'Mixdrop';
    if (lower.contains('doodstream') || lower.contains('dood.')) return 'Doodstream';
    if (lower.contains('vidcloud') || lower.contains('rabbitstream') || lower.contains('megacloud')) return 'MegaCloud';
    if (lower.contains('streamwish')) return 'Streamwish';
    if (lower.contains('filelions')) return 'Filelions';
    if (lower.contains('vidhide')) return 'Vidhide';
    if (lower.contains('dropload')) return 'Dropload';
    if (lower.contains('vidspeed')) return 'Vidspeed';
    if (lower.contains('krakenfiles')) return 'Krakenfiles';
    if (lower.contains('gofile')) return 'Gofile';
    if (lower.contains('mediafire')) return 'Mediafire';
    if (lower.contains('vadapav')) return 'Vadapav';
    return null;
  }

  static Future<bool> _probeDirectLink(String url) async {
    try {
      final uri = Uri.parse(url);
      final req = await _probeClient.headUrl(uri).timeout(const Duration(milliseconds: 1200));
      final res = await req.close().timeout(const Duration(milliseconds: 1200));
      await res.drain<void>();
      if (res.statusCode == 404 || res.statusCode == 410) {
        return false;
      }
      return true;
    } catch (_) {
      // If HEAD is blocked or timed out, assume alive rather than false-positive dropping
      return true;
    }
  }

  static int _streamRank(ScrapedStream s, String prefLang) {
    int rank = _qualityRank(s.quality) * 10;

    // Preferred Language boost (+100 points)
    if (prefLang.isNotEmpty && prefLang != 'any') {
      final text = '${s.name} ${s.title}'.toLowerCase();
      if (prefLang == 'dual' || prefLang == 'multi') {
        if (text.contains('dual audio') || text.contains('multi audio')) {
          rank += 100;
        }
      } else if (text.contains(prefLang)) {
        rank += 100;
      }
    }

    // Quality rip bonus
    final ripUpper = '${s.name} ${s.title}'.toUpperCase();
    if (ripUpper.contains('[REMUX]')) {
      rank += 8;
    } else if (ripUpper.contains('[BLURAY]')) {
      rank += 6;
    } else if (ripUpper.contains('[WEB-DL]')) {
      rank += 4;
    }

    // Cache source bonus
    if (s.name.contains('[Cached]')) {
      rank += 30;
    } else if (s.name.contains('[Cachable]') || s.name.contains('[Cache]')) {
      rank += 15;
    } else {
      rank += 5;
    }
    return rank;
  }

  static int _qualityRank(String? q) {
    switch (q?.toUpperCase()) {
      case '4K':
      case '2160P':
        return 4;
      case '1080P':
        return 3;
      case '720P':
        return 2;
      case '480P':
        return 1;
      default:
        return 0;
    }
  }
}
