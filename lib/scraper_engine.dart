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
import 'opensubtitles_service.dart';

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
  final String? fileSize;
  final List<Map<String, dynamic>>? subtitles;

  ScrapedStream({
    required this.name,
    required this.title,
    required this.url,
    this.behaviorHints,
    required this.provider,
    this.quality,
    this.fileSize,
    this.subtitles,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'description': title,
        'url': url,
        if (fileSize != null && fileSize!.isNotEmpty) 'fileSize': fileSize,
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
  /// Max 100 entries LRU — evicts oldest when cap is exceeded
  final Map<String, _CachedScrape> _scrapeCache = {};
  static const int _scrapeCacheMaxSize = 100;
  final List<String> _scrapeCacheOrder = []; // LRU order tracking

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
    _scrapeCacheOrder.clear();
    _consecutiveFailures.clear();
    _trippedUntil.clear();
    _initScrapers();
  }

  /// Insert into scrape cache with LRU eviction (max _scrapeCacheMaxSize entries)
  void _putScrapeCache(String key, _CachedScrape value) {
    // Remove stale key from order list if present
    _scrapeCacheOrder.remove(key);
    _scrapeCacheOrder.add(key);
    _scrapeCache[key] = value;

    // Evict oldest entries if over cap
    while (_scrapeCacheOrder.length > _scrapeCacheMaxSize) {
      final oldest = _scrapeCacheOrder.removeAt(0);
      _scrapeCache.remove(oldest);
    }
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
              fileSize: s.fileSize,
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
        _putScrapeCache(key, _CachedScrape(streams, DateTime.now().add(const Duration(minutes: 12))));
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
    final cfg = AddonConfig.instance;
    final scrapers = allActive.where((s) {
      if (!cfg.enableTorboxCachedTorrents && s.isTorrent) {
        return false;
      }
      final tripExp = _trippedUntil[s.providerId];
      if (tripExp != null && tripExp.isAfter(now)) {
        return false;
      }
      return true;
    }).toList();

    final timeout = Duration(seconds: cfg.timeoutSeconds);

    print('[ScraperEngine] Scraping "${meta.title}" (${meta.year ?? 'N/A'}, ${meta.type}) '
        'across ${scrapers.length} active scrapers (${allActive.length - scrapers.length} tripped, timeout: ${cfg.timeoutSeconds}s)...');

    // Each scraper collects into its own list to avoid concurrent-write races.
    final futures = scrapers.map((scraper) async {
      final localResults = <StreamSource>[];
      final completer = Completer<void>();
      StreamSubscription<StreamSource>? sub;
      try {
        final stream = scraper.scrapeStream(
          type: meta.type,
          title: meta.title,
          year: meta.year,
          season: meta.season,
          episode: meta.episode,
          imdbId: meta.imdbId,
        );
        sub = stream.listen(
          (item) {
            final realScraper = resolveSourceName(scraper.providerId, scraper.providerName);
            String itemProv = item.providerName ?? '';
            if (itemProv.isEmpty ||
                itemProv.toLowerCase().contains('playtorrio') ||
                itemProv.toLowerCase().contains('megascraper') ||
                itemProv.toLowerCase().contains('unbound') ||
                itemProv.toLowerCase().contains('hosthound') ||
                itemProv.toLowerCase() == 'hostreamio') {
              final itemName = item.name ?? '';
              if (itemName.isNotEmpty &&
                  !itemName.toLowerCase().contains('playtorrio') &&
                  !itemName.toLowerCase().contains('hostreamio') &&
                  !itemName.toLowerCase().contains('megascraper')) {
                final cleanItemName = itemName.replaceAll(RegExp(r'^\[+|\]+$'), '').trim();
                itemProv = cleanItemName.isNotEmpty ? cleanItemName : realScraper;
              } else {
                itemProv = realScraper;
              }
            }

            localResults.add(item.copyWith(
              providerName: itemProv,
              providerId: scraper.providerId,
            ));
          },
          onError: (_) {},
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: false,
        );
        await completer.future.timeout(timeout);
      } catch (_) {
        await sub?.cancel();
      }
      if (localResults.isNotEmpty) {
        _consecutiveFailures[scraper.providerId] = 0;
        _trippedUntil.remove(scraper.providerId);
      } else {
        final fails = (_consecutiveFailures[scraper.providerId] ?? 0) + 1;
        _consecutiveFailures[scraper.providerId] = fails;
        if (fails >= 3) {
          _trippedUntil[scraper.providerId] = DateTime.now().add(const Duration(minutes: 10));
          print('[CircuitBreaker] Scraper ${scraper.providerId} tripped for 10m (3 consecutive failures).');
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
    final torrentHashToSources = <String, List<StreamSource>>{};

    if (torboxKey.isNotEmpty) {
      for (final src in rawResults) {
        final rawUrl = src.url ?? src.externalUrl ?? '';
        if (rawUrl.startsWith('http') && TorboxService.instance.isSupportedHoster(rawUrl)) {
          supportedHosterUrls.add(rawUrl);
        } else if (cfg.enableTorboxCachedTorrents) {
          final hash = _extractTorrentHash(rawUrl, src.infoHash);
          if (hash != null) {
            torrentHashToSources.putIfAbsent(hash, () => []).add(src);
          }
        }
      }
    }

    final torboxCacheMap = supportedHosterUrls.isNotEmpty
        ? await TorboxService.instance.checkCachedBatch(supportedHosterUrls, torboxKey)
        : <String, bool>{};

    final torrentCacheMap = (cfg.enableTorboxCachedTorrents && torboxKey.isNotEmpty && torrentHashToSources.isNotEmpty)
        ? await TorboxService.instance.checkCachedTorrentsBatch(torrentHashToSources.keys.toList(), torboxKey)
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

    // ── OpenSubtitles v3 Subtitles Fetching ──
    List<Map<String, dynamic>> openSubtitlesList = [];
    if (cfg.enableOpenSubtitles && meta.imdbId != null && meta.imdbId!.isNotEmpty) {
      final subId = (meta.season != null && meta.episode != null)
          ? '${meta.imdbId}:${meta.season}:${meta.episode}'
          : meta.imdbId!;
      try {
        openSubtitlesList = await OpenSubtitlesService.instance.getSubtitles(
          type: meta.type,
          id: subId,
        );
      } catch (_) {}
    }

    final seenUrls = <String>{};
    final streamDedupeMap = <String, ScrapedStream>{};
    final finalStreams = <ScrapedStream>[];

    for (final src in rawResults) {
      final rawUrl = src.url ?? src.externalUrl ?? '';
      final torrentHash = _extractTorrentHash(rawUrl, src.infoHash);
      final isTorrent = torrentHash != null || rawUrl.startsWith('magnet:');

      if (isTorrent) {
        // Strictly only show if TorBox cached torrents is enabled AND API key is present
        if (!cfg.enableTorboxCachedTorrents || torboxKey.isEmpty) continue;
        // Strictly only show if already 100% cached on TorBox CDN (Zero P2P, instant cloud streaming)
        final isCached = torrentHash != null && torrentCacheMap[torrentHash] == true;
        if (!isCached) continue;

        final sourceName = resolveSourceName(src.providerId ?? '', src.providerName ?? src.name);
        final q = src.quality ?? '';
        final qLabel = q.isNotEmpty ? q : 'HD';
        final badge = src.getAudioBadge(mediaTitle: meta.title) ?? '';
        final torboxPlayUrl = '$localBaseUrl/torbox/play?url=${Uri.encodeComponent(rawUrl.isNotEmpty ? rawUrl : 'magnet:?xt=urn:btih:$torrentHash')}';

        final cachedEnriched = BadgeService.enrichStream(
          rawTitle: src.title ?? src.name ?? meta.title,
          mediaTitle: meta.title,
          year: meta.year,
          season: meta.season,
          episode: meta.episode,
          quality: q,
          codec: src.codec,
          audioBadge: badge,
          fileSize: src.fileSize,
          providerName: '$sourceName (TorBox Cached)',
          sourceName: sourceName,
          hostName: '⚡ TorBox Cloud CDN ($sourceName)',
          ottPlatform: meta.ottPlatform,
          isCached: true,
          isHls: false,
          isProxied: false,
        );

        final cachedBadge = cachedEnriched['badgeHeader'] ?? qLabel;
        final cachedStream = ScrapedStream(
          name: '⚡ TorBox [Cached] • $sourceName\n$cachedBadge',
          title: '${cachedEnriched['title']}\n⚡ Instant TorBox Cloud CDN Playback (Zero P2P)',
          url: torboxPlayUrl,
          behaviorHints: const {'notWebReady': false},
          provider: '$sourceName (TorBox Cached)',
          quality: q,
          fileSize: cachedEnriched['fileSize'],
          subtitles: openSubtitlesList,
        );
        finalStreams.add(cachedStream);
        continue; // Torrent handled; never fall through to direct play
      }

      // Non-torrent: Standard Direct HTTP(S) & Hoster Link Processing
      if (rawUrl.isEmpty || !rawUrl.startsWith('http')) continue;
      if (deadUrls.contains(rawUrl)) continue; // Filtered broken link

      final isSupportedHoster = torboxKey.isNotEmpty && TorboxService.instance.isSupportedHoster(rawUrl);
      final isHosterOffline = torboxKey.isNotEmpty && TorboxService.instance.isHosterOffline(rawUrl);
      final offlineHosterName = isHosterOffline ? TorboxService.instance.getHosterName(rawUrl) : '';
      final isTorboxCached = torboxCacheMap[rawUrl] == true;

      // Clean Source & Host names
      final sourceName = resolveSourceName(src.providerId ?? '', src.providerName ?? src.name);
      final hostName = detectStreamHost(rawUrl, isCached: isTorboxCached);

      // Smart Deduplication across scrapers
      if (cfg.enableDeduplication && seenUrls.contains(rawUrl)) {
        final existing = streamDedupeMap[rawUrl];
        if (existing != null && !existing.provider.contains(sourceName)) {
          final updated = ScrapedStream(
            name: existing.name,
            title: '${existing.title}\n🔗 Also mirrored on: $sourceName',
            url: existing.url,
            behaviorHints: existing.behaviorHints,
            provider: '${existing.provider} + $sourceName',
            quality: existing.quality,
            fileSize: existing.fileSize,
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
      final Map<String, String> headers = {};
      if (src.headers != null && src.headers!.isNotEmpty) {
        headers.addAll(src.headers!);
      }
      if (src.behaviorHints != null && src.behaviorHints!['proxyHeaders'] is Map) {
        final req = src.behaviorHints!['proxyHeaders']['request'];
        if (req is Map) {
          req.forEach((k, v) {
            if (k != null && v != null) {
              headers[k.toString()] = v.toString();
            }
          });
        }
      }

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
        providerName: sourceName,
        sourceName: sourceName,
        hostName: hostName,
        ottPlatform: meta.ottPlatform,
        isCached: false,
        isHls: isHls,
        isProxied: isDirectProxied,
      );

      final qLabel = q.isNotEmpty ? q : (isHls ? 'HLS' : 'HD');
      final subList = <Map<String, dynamic>>[];
      if (src.subtitles != null) {
        subList.addAll(src.subtitles!.map((s) => {
          'id': s.language,
          'url': s.downloadUrl,
          'lang': s.language,
        }));
      }
      if (openSubtitlesList.isNotEmpty) {
        subList.addAll(openSubtitlesList);
      }

      if (isTorboxCached) {
        // ── 1. Link is ALREADY TorBox cached: show 2 links (Cached + Direct Play) ──
        final torboxPlayUrl = '$localBaseUrl/torbox/play?url=${Uri.encodeComponent(rawUrl)}';
        final cachedHost = detectStreamHost(rawUrl, isCached: false);
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
          providerName: '$sourceName (TorBox Cached)',
          sourceName: sourceName,
          hostName: '⚡ TorBox Cloud CDN ($cachedHost)',
          ottPlatform: meta.ottPlatform,
          isCached: true,
          isHls: false,
          isProxied: false,
        );

        final cachedBadge = cachedEnriched['badgeHeader'] ?? qLabel;
        final cachedStream = ScrapedStream(
          name: '⚡ TorBox [Cached] • $cachedHost\n$cachedBadge',
          title: '${cachedEnriched['title']}\n⚡ Instant TorBox Cloud CDN Playback',
          url: torboxPlayUrl,
          behaviorHints: const {'notWebReady': false},
          provider: '$sourceName ($cachedHost)',
          quality: q,
          fileSize: cachedEnriched['fileSize'],
          subtitles: subList,
        );
        finalStreams.add(cachedStream);

        final isDirectPlayable = isDirectPlayableUrl(rawUrl);
        if (isDirectPlayable) {
          final directBadge = directEnriched['badgeHeader'] ?? qLabel;
          final directStream = ScrapedStream(
            name: '🌐 Direct Play [$sourceName]\n$directBadge',
            title: '${directEnriched['title']}\n🌐 Direct Play • Original Hoster Link',
            url: directStreamUrl,
            behaviorHints: directBehaviorHints,
            provider: sourceName,
            quality: q,
            fileSize: directEnriched['fileSize'],
            subtitles: subList,
          );
          finalStreams.add(directStream);
        }
      } else if (isSupportedHoster) {
        // ── 2. Link is NOT cached but IS cachable: show TorBox Start Caching (and Direct Play only if truly playable) ──
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
          providerName: sourceName,
          sourceName: sourceName,
          hostName: hostName,
          ottPlatform: meta.ottPlatform,
          isCached: false,
          isHls: isHls,
          isProxied: false,
        );

        final cacheBadge = cacheEnriched['badgeHeader'] ?? qLabel;
        final startCachingStream = ScrapedStream(
          name: '☁️ TorBox [Start Caching] • $hostName\n$cacheBadge',
          title: '${cacheEnriched['title']}\n☁️ Click to cache on TorBox cloud & stream',
          url: cachePlayUrl,
          behaviorHints: const {'notWebReady': false},
          provider: '$sourceName ($hostName)',
          quality: q,
          fileSize: cacheEnriched['fileSize'],
          subtitles: subList,
        );
        finalStreams.add(startCachingStream);
        streamDedupeMap[rawUrl] = startCachingStream;

        // ONLY add direct stream if rawUrl is actually a playable video container/stream!
        if (isDirectPlayableUrl(rawUrl)) {
          final directBadge = directEnriched['badgeHeader'] ?? qLabel;
          final directStream = ScrapedStream(
            name: '🌐 Direct Play [$sourceName]\n$directBadge',
            title: '${directEnriched['title']}\n🌐 Direct Play • Original Hoster Link',
            url: directStreamUrl,
            behaviorHints: directBehaviorHints,
            provider: sourceName,
            quality: q,
            fileSize: directEnriched['fileSize'],
            subtitles: subList,
          );
          finalStreams.add(directStream);
        }
      } else if (isHosterOffline) {
        // ── 3. Hoster is recognized by TorBox but currently OFFLINE on TorBox ──
        // Do NOT offer "Start Caching" (it will fail). Offer direct play if playable, with offline notice!
        if (isDirectPlayableUrl(rawUrl)) {
          final directBadge = directEnriched['badgeHeader'] ?? qLabel;
          final offlineName = offlineHosterName.isNotEmpty ? offlineHosterName : hostName;
          final directStream = ScrapedStream(
            name: '🌐 Direct Play [$sourceName] • ⚠️ TorBox: $offlineName Offline\n$directBadge',
            title: '${directEnriched['title']}\n⚠️ $offlineName is currently OFFLINE on TorBox debrider • Direct playback only',
            url: directStreamUrl,
            behaviorHints: directBehaviorHints,
            provider: sourceName,
            quality: q,
            fileSize: directEnriched['fileSize'],
            subtitles: subList,
          );
          finalStreams.add(directStream);
          streamDedupeMap[rawUrl] = directStream;
        }
      } else {
        // ── 4. Standard Non-Hoster / Direct Stream (1 link) ──
        // Validate that this link is actually a playable stream rather than an unparsed website/blog URL!
        if (isDirectPlayableUrl(rawUrl)) {
          final directBadge = directEnriched['badgeHeader'] ?? qLabel;
          final directStream = ScrapedStream(
            name: '🌐 Direct Play [$sourceName]\n$directBadge',
            title: directEnriched['title']!,
            url: directStreamUrl,
            behaviorHints: directBehaviorHints,
            provider: sourceName,
            quality: q,
            fileSize: directEnriched['fileSize'],
            subtitles: subList,
          );
          finalStreams.add(directStream);
          streamDedupeMap[rawUrl] = directStream;
        }
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

  static bool isDirectPlayableUrl(String url) {
    final lower = url.toLowerCase();
    // 1. Definite media containers & manifests
    if (lower.contains('.m3u8') ||
        lower.contains('.mpd') ||
        lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.webm') ||
        lower.contains('.ts') ||
        lower.contains('.avi') ||
        lower.contains('/proxy?') ||
        lower.contains('/torbox/play')) {
      return true;
    }

    // 2. Definite non-playable hoster landing pages / link shorteners / blog posts
    if (lower.contains('hubcloud') ||
        lower.contains('hubdrive') ||
        lower.contains('driveseed') ||
        lower.contains('drivebot') ||
        lower.contains('fast-dl') ||
        lower.contains('modpro.blog') ||
        lower.contains('multimovies.casa') ||
        lower.contains('/drive/') ||
        lower.contains('/dl/') ||
        lower.contains('/archives/') ||
        lower.contains('/tvshows/') ||
        lower.contains('1fichier.com') ||
        lower.contains('rapidgator.net') ||
        lower.contains('katfile.com') ||
        lower.contains('turbobit.net') ||
        lower.contains('ddownload.com') ||
        lower.contains('nitroflare.com') ||
        lower.contains('mega.nz/file') ||
        lower.contains('mega.co.nz/file')) {
      return false;
    }

    // 3. Known direct streaming CDNs
    if (lower.contains('pontv.to') ||
        lower.contains('quietridge.top') ||
        lower.contains('stillhaven.top') ||
        lower.contains('vidzy.cc') ||
        lower.contains('workers.dev') ||
        lower.contains('streamtape.com/get_video') ||
        lower.contains('vidsrc') ||
        lower.contains('superstream') ||
        lower.contains('youtube.com') ||
        lower.contains('googlevideo.com') ||
        lower.contains('archive.org/download') ||
        lower.contains('dailymotion.com/cdn') ||
        lower.contains('dmcdn.net') ||
        lower.contains('pixeldrain.com/api/file/')) {
      return true;
    }

    return false;
  }

  /// Maps scraper IDs and names to clear website and scraper source labels
  static String resolveSourceName(String providerId, [String? providerName]) {
    final cleanId = providerId.toLowerCase().replaceAll('scraper', '').trim();
    const siteMap = {
      'fourkhdhub': '4KHDHub',
      'vegamovies': 'VegaMovies',
      'uhdmovies': 'UHDMovies',
      'bollyflix': 'BollyFlix',
      'bolly4u': 'Bolly4u',
      'hdhub4u': 'HDHub4u',
      'moviesdrive': 'MoviesDrive',
      'moviesmod': 'MoviesMod',
      'multimovies': 'MultiMovies',
      'dramacool': 'Dramacool',
      'dramaday': 'DramaDay',
      'animepahe': 'AnimePahe',
      'gogoanime': 'GogoAnime',
      'hianime': 'HiAnime',
      'kissasian': 'KissAsian',
      'kisskh': 'KissKh',
      'lookmovie': 'LookMovie',
      'vadapav': 'Vadapav',
      'yomovies': 'YoMovies',
      'cinesu': 'CineSu',
      'cinesrc': 'CineSrc',
      'cinejoy': 'CineJoy',
      'flaxmovies': 'FlaxMovies',
      'fsharetv': 'FShareTV',
      'fsonic': 'FSonic',
      'fsonline': 'FSOnline',
      'hindmoviez': 'HindMoviez',
      'playdesi': 'PlayDesi',
      'toonstream': 'ToonStream',
      'vuflix': 'Vuflix',
      'downloadeverything': 'DownloadEverything',
      'videasy': 'Videasy',
      'vidsrc': 'VidSrc',
      'vidlink': 'VidLink',
      'vidcore': 'VidCore',
      'vidfast': 'VidFast',
      'vidrock': 'VidRock',
      'vidup': 'VidUp',
      'vidvault': 'VidVault',
      'vidzee': 'VidZee',
      'vixsrc': 'VixSrc',
      'flystream': 'FlyStream',
      'rivestream': 'RiveStream',
      'movy': 'Movy',
      'dulo': 'Dulo',
      'frame': 'Frame',
      'hexa': 'Hexa',
      'lmscript': 'LMScript',
      'mapple': 'Mapple',
      'megasource': 'MegaSource',
      'meowtv': 'MeowTV',
      'movienight': 'MovieNight',
      'multiembed': 'MultiEmbed',
      'nova': 'Nova',
      'peestream': 'PeeStream',
      'purstream': 'PurStream',
      'xdownloader': 'XDownloader',
      'xpass': 'XPass',
      'bcine': 'BCine',
      'a111477': '111477',
      'vidgod': 'VidGod',
      'zxcstream': 'ZxcStream',
      'archive': 'Archive.org',
      'dailymotion': 'Dailymotion',
      'youtube': 'YouTube',
      'vimeo': 'Vimeo',
    };

    String baseName = siteMap[cleanId] ?? '';
    if (baseName.isEmpty) {
      if (providerName != null && providerName.isNotEmpty) {
        final clean = providerName
            .replaceAll(RegExp(r'PlayTorrio(HTTP)?|MegaScraper|Unbound|HostHound', caseSensitive: false), '')
            .replaceAll(RegExp(r'\b(saket|sakinator)\b', caseSensitive: false), '')
            .replaceAll(RegExp(r'^\[+|\]+$'), '')
            .trim();
        if (clean.isNotEmpty && clean.toLowerCase() != 'hostreamio') {
          baseName = clean;
        }
      }
      if (baseName.isEmpty) {
        baseName = cleanId.isNotEmpty ? cleanId : 'Hostreamio';
      }
    }

    // Preserve sub-server information if provided
    if (providerName != null && providerName.isNotEmpty) {
      var sub = providerName
          .replaceAll(RegExp(r'PlayTorrio(HTTP)?|MegaScraper|Unbound|HostHound', caseSensitive: false), '')
          .replaceAll(RegExp(r'\b(saket|sakinator)\b', caseSensitive: false), '')
          .replaceAll('[', '')
          .replaceAll(']', '')
          .trim();
      if (sub.isNotEmpty && sub.toLowerCase() != baseName.toLowerCase() && sub.toLowerCase() != 'hostreamio') {
        if (sub.toLowerCase().contains(baseName.toLowerCase()) ||
            baseName.toLowerCase().contains(sub.toLowerCase().replaceAll(RegExp(r'\s*-\s*.*'), ''))) {
          return sub;
        }
        return '$baseName ($sub)';
      }
    }

    return baseName;
  }

  /// Detects where the file or stream is hosted (filehoster, cyberlocker, or CDN host)
  static String detectStreamHost(String url, {bool isCached = false}) {
    if (isCached) {
      return 'TorBox Cloud CDN';
    }

    final lower = url.toLowerCase();

    // 1. Filehosters & Cyberlockers
    if (lower.contains('hubcloud')) return 'HubCloud';
    if (lower.contains('driveseed') || lower.contains('drivebot')) return 'DriveSeed';
    if (lower.contains('fast-dl') || lower.contains('fastdl') || lower.contains('fastcloud')) return 'Fast-DL';
    if (lower.contains('pixeldrain')) return 'PixelDrain';
    if (lower.contains('1fichier')) return '1fichier';
    if (lower.contains('rapidgator')) return 'Rapidgator';
    if (lower.contains('turbobit')) return 'Turbobit';
    if (lower.contains('nitroflare')) return 'Nitroflare';
    if (lower.contains('katfile')) return 'Katfile';
    if (lower.contains('ddownload')) return 'DDownload';
    if (lower.contains('mega.nz') || lower.contains('mega.co.nz')) return 'Mega';
    if (lower.contains('gofile')) return 'Gofile';
    if (lower.contains('mediafire')) return 'Mediafire';
    if (lower.contains('filepress')) return 'Filepress';
    if (lower.contains('gdflix')) return 'GDFlix';
    if (lower.contains('filelions')) return 'Filelions';
    if (lower.contains('streamwish')) return 'Streamwish';
    if (lower.contains('vidhide')) return 'Vidhide';
    if (lower.contains('dropload')) return 'Dropload';
    if (lower.contains('vidspeed')) return 'Vidspeed';
    if (lower.contains('krakenfiles')) return 'Krakenfiles';
    if (lower.contains('streamtape')) return 'Streamtape';
    if (lower.contains('mixdrop')) return 'Mixdrop';
    if (lower.contains('doodstream') || lower.contains('dood.')) return 'Doodstream';
    if (lower.contains('vadapav')) return 'Vadapav';
    if (lower.contains('archive.org')) return 'Archive.org';
    if (lower.contains('dailymotion')) return 'Dailymotion';
    if (lower.contains('youtube') || lower.contains('youtu.be')) return 'YouTube';
    if (lower.contains('vimeo')) return 'Vimeo';

    // 2. Direct Streaming CDNs & Edge Providers
    if (lower.contains('rabbitstream') || lower.contains('megacloud')) return 'MegaCloud CDN';
    if (lower.contains('vidcloud')) return 'VidCloud CDN';
    if (lower.contains('upcloud')) return 'UpCloud CDN';
    if (lower.contains('dokicloud')) return 'DokiCloud';
    if (lower.contains('streamlare')) return 'Streamlare';
    if (lower.contains('streamruby')) return 'StreamRuby';
    if (lower.contains('voe.sx') || lower.contains('voe-network')) return 'VOE CDN';
    if (lower.contains('vidsrc')) return 'VidSrc CDN';
    if (lower.contains('workers.dev') || lower.contains('cloudflare')) return 'Cloudflare Edge';
    if (lower.contains('b-cdn.net') || lower.contains('bunnycdn')) return 'BunnyCDN';
    if (lower.contains('akamai')) return 'Akamai CDN';
    if (lower.contains('fastly')) return 'Fastly CDN';
    if (lower.contains('googlevideo.com')) return 'Google Video CDN';

    // 3. Fallback: Disposable Stealth Edge Domain
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.isNotEmpty) {
        final clean = host
            .replaceAll(RegExp(r'^(?:www|cdn\d*|edge\d*|s\d+|stream\d*|media\d*)\.', caseSensitive: false), '')
            .trim()
            .toLowerCase();
        if (clean.isNotEmpty) {
          return 'Stealth Edge ($clean)';
        }
      }
    } catch (_) {}

    return 'Direct Streaming Edge';
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
    } else if (s.name.contains('[Start Caching]') ||
        s.name.contains('[Cachable]') ||
        s.name.contains('[Cache]')) {
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

  static String? _extractTorrentHash(String url, String? infoHash) {
    if (infoHash != null && infoHash.isNotEmpty) return infoHash.toLowerCase();
    if (url.startsWith('magnet:')) {
      final m = RegExp(r'xt=urn:btih:([a-zA-Z0-9]+)', caseSensitive: false).firstMatch(url);
      if (m != null) return m.group(1)!.toLowerCase();
    } else if (RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(url)) {
      return url.toLowerCase();
    }
    return null;
  }
}
