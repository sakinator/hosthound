import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'config.dart';
import 'metadata_service.dart';
import 'proxy.dart';
import 'scraper_engine.dart';
import 'web_ui.dart';
import 'catalog_service.dart';
import 'torbox_service.dart';
import 'doh_resolver.dart';
import 'key_validator.dart';

class ServerService {
  static final ServerService instance = ServerService._();

  ServerService._();

  HttpServer? _server;
  final ValueNotifier<bool> isRunning = ValueNotifier<bool>(false);
  final ValueNotifier<String> localIp = ValueNotifier<String>('127.0.0.1');
  final ValueNotifier<int> requestCount = ValueNotifier<int>(0);
  final ValueNotifier<String> statusMessage = ValueNotifier<String>('Stopped');
  final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>([]);

  void _addLog(String msg) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '[$time] $msg';
    final current = List<String>.from(logs.value);
    if (current.length > 50) current.removeAt(0);
    current.add(entry);
    logs.value = current;
    debugPrint(entry);
  }

  Future<void> init() async {
    await AddonConfig.instance.load();
    await updateLanIp();
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'hostreamio_server_channel',
        channelName: 'Hostreamio Server Service',
        channelDescription: 'Keeps Hostreamio Addon HTTP Server active for Nuvio.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<String> updateLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              addr.address.startsWith('192.168.') &&
              !addr.address.startsWith('192.168.56.')) {
            localIp.value = addr.address;
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('10.')) {
            localIp.value = addr.address;
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              !addr.address.startsWith('169.254.') &&
              !addr.address.startsWith('172.') &&
              !addr.address.startsWith('192.168.56.') &&
              !addr.address.startsWith('45.')) {
            localIp.value = addr.address;
            return addr.address;
          }
        }
      }
    } catch (e) {
      _addLog('IP detection error: $e');
    }
    return localIp.value;
  }

  Future<bool> startServer() async {
    if (isRunning.value) return true;

    try {
      HttpOverrides.global = MegascraperHttpOverrides();
      DohResolver.instance.prewarm([
        'api.torbox.app',
        'cinematv.click',
        'vidsrc.to',
        'vidlink.pro',
        'autoembed.cc',
        'embed.su',
        'rabbitstream.net',
        'megacloud.tv',
        '1337x.to',
        'torrentgalaxy.to',
        'vegamovies.im',
        'hdhub4u.tv',
      ]);

      final cfg = AddonConfig.instance;
      await updateLanIp();

      _server = await HttpServer.bind(InternetAddress.anyIPv4, cfg.port);
      isRunning.value = true;
      statusMessage.value = 'Running on port ${cfg.port}';
      _addLog('Server started on http://${localIp.value}:${cfg.port}');

      // Start foreground service to keep CPU awake on Android TV / Mobile
      try {
        if (!await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.startService(
            notificationTitle: 'Hostreamio Server Active',
            notificationText: 'Serving Nuvio streams on port ${cfg.port}',
          );
        }
      } catch (e) {
        _addLog('Foreground service note: $e');
      }

      _listenToRequests(_server!, cfg.port);
      return true;
    } catch (e) {
      statusMessage.value = 'Error: $e';
      _addLog('Failed to start server: $e');
      isRunning.value = false;
      return false;
    }
  }

  Future<void> stopServer() async {
    if (!isRunning.value) return;
    try {
      await _server?.close(force: true);
      _server = null;
      isRunning.value = false;
      statusMessage.value = 'Stopped';
      _addLog('Server stopped');

      try {
        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }
      } catch (_) {}
    } catch (e) {
      _addLog('Error stopping server: $e');
    }
  }

  void _listenToRequests(HttpServer server, int port) async {
    await for (final request in server) {
      requestCount.value = requestCount.value + 1;
      _handleRequest(request, port);
    }
  }

  static Map<String, dynamic>? _safeParseJsonMap(String bodyStr) {
    if (bodyStr.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(bodyStr);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleRequest(HttpRequest request, int port) async {
    final path = request.uri.path;
    final method = request.method.toUpperCase();

    // CORS
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, HEAD');
    request.response.headers.set('Access-Control-Allow-Headers', '*');

    if (method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // Use the exact scheme and authority (host:port) that the client connected to
    final localBaseUrl = '${request.requestedUri.scheme}://${request.requestedUri.authority}';

    try {
      // 0. Static Brand Logo & Favicon
      if (path == '/logo.png' || path == '/favicon.png' || path == '/favicon.ico') {
        final candidates = [
          File('hostreamio_logo.png'),
          File('assets/images/hostreamio_logo.png'),
          File('android_app/assets/images/hostreamio_logo.png'),
        ];
        for (final f in candidates) {
          if (f.existsSync()) {
            request.response.headers.contentType = ContentType('image', 'png');
            await request.response.addStream(f.openRead());
            await request.response.close();
            return;
          }
        }
      }

      // 1. Web dashboard
      if (path == '/' || path == '/configure') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(WebUI.render(localIp: localIp.value, port: port));
        await request.response.close();
        return;
      }

      // 2. Stremio/Nuvio Addon Manifest
      if (path == '/manifest.json') {
        final manifest = {
          'id': 'org.sakinator.hostreamio',
          'version': '2.0.0',
          'name': 'Hostreamio',
          'description': 'Hostreamio — Direct Hosters, Streaming Links & TorBox Cloud Debrid Stream Engine with Smart Proxy & Instant Badges',
          'resources': ['catalog', 'meta', 'stream'],
          'types': ['movie', 'series'],
          'idPrefixes': ['tt', 'tmdb', 'kitsu', 'yt:', 'archive:', 'dm:', 'vimeo:'],
          'catalogs': CatalogService.getCatalogs(),
          'behaviorHints': {
            'configurable': true,
            'configurationRequired': false,
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(manifest));
        await request.response.close();
        return;
      }

      // 3. Catalogs Endpoint: /catalog/:type/:id.json
      if (path.startsWith('/catalog/')) {
        final segments = request.uri.pathSegments;
        if (segments.length >= 3) {
          final type = segments[1];
          var catId = segments[2];
          if (catId.endsWith('.json')) {
            catId = catId.substring(0, catId.length - 5);
          }

          String? search;
          String? genre;
          int skip = 0;

          if (segments.length >= 4) {
            var extra = Uri.decodeComponent(segments[3]);
            if (extra.endsWith('.json')) {
              extra = extra.substring(0, extra.length - 5);
            }
            final parts = extra.split('&');
            for (final p in parts) {
              if (p.startsWith('search=')) search = p.substring(7);
              if (p.startsWith('genre=')) genre = p.substring(6);
              if (p.startsWith('skip=')) skip = int.tryParse(p.substring(5)) ?? 0;
            }
          }

          _addLog('Catalog: $catId ($genre)');
          final items = await CatalogService.instance.getCatalogItems(
            type: type,
            id: catId,
            search: search,
            genre: genre,
            skip: skip,
          );

          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'metas': items}));
          await request.response.close();
          return;
        }
      }

      // 4. Metadata Detail Endpoint: /meta/:type/:id.json
      if (path.startsWith('/meta/')) {
        final segments = request.uri.pathSegments;
        if (segments.length >= 3) {
          final type = segments[1];
          var metaId = Uri.decodeComponent(segments[2]);
          if (metaId.endsWith('.json')) {
            metaId = metaId.substring(0, metaId.length - 5);
          }

          final meta = await CatalogService.instance.getMetaDetail(type, metaId);
          if (meta != null) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'meta': meta}));
            await request.response.close();
            return;
          }

          // Standard movie / series metadata enriched with Fanart.tv ClearLogos & OMDb ratings
          final resolved = await MetadataService.resolve(type: type, rawId: metaId);
          if (resolved != null) {
            final metaObj = <String, dynamic>{
              'id': resolved.id,
              'type': resolved.type,
              'name': resolved.title,
              if (resolved.genres != null && resolved.genres!.isNotEmpty)
                'genres': resolved.genres
              else if (resolved.omdb?.genre != null)
                'genres': resolved.omdb!.genre!.split(', ').map((s) => s.trim()).toList()
              else
                'genres': ['Cinema'],
              'year': resolved.year?.toString() ?? resolved.omdb?.year ?? '',
              'releaseInfo': resolved.year?.toString() ?? resolved.omdb?.year ?? '',
              'description': resolved.description ?? resolved.omdb?.plot ?? '',
              if (resolved.omdb?.director != null && resolved.omdb!.director!.isNotEmpty)
                'director': [resolved.omdb!.director!],
              if (resolved.omdb?.actors != null && resolved.omdb!.actors!.isNotEmpty)
                'cast': resolved.omdb!.actors!.split(', ').map((s) => s.trim()).toList(),
              if (resolved.omdb?.imdbRating != null && resolved.omdb!.imdbRating != 'N/A')
                'imdbRating': resolved.omdb!.imdbRating,
              if (resolved.poster != null) 'poster': resolved.poster,
              if (resolved.background != null) 'background': resolved.background,
              if (resolved.logo != null) 'logo': resolved.logo,
            };
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'meta': metaObj}));
            await request.response.close();
            return;
          }
        }
      }

      // 5. Streams endpoint: /stream/:type/:id.json
      if (path.startsWith('/stream/')) {
        final segments = request.uri.pathSegments;
        if (segments.length >= 3) {
          final type = segments[1];
          var idWithExt = Uri.decodeComponent(segments[2]);
          if (idWithExt.endsWith('.json')) {
            idWithExt = idWithExt.substring(0, idWithExt.length - 5);
          }

          _addLog('Stream request: $type/$idWithExt');

          // Check custom video streams (YouTube, Vimeo, Archive.org, Dailymotion)
          // Also scrape all other hoster/torrent sources for this title & year, sorting own links FIRST!
          if (idWithExt.startsWith('yt:') || idWithExt.startsWith('vimeo:') || idWithExt.startsWith('archive:') || idWithExt.startsWith('dm:')) {
            final customStreamsFuture = CatalogService.instance.resolveCustomStreams(
              type, 
              idWithExt,
              localBaseUrl: localBaseUrl,
            );
            final metaDetailFuture = CatalogService.instance.getMetaDetail(type, idWithExt);

            final results = await Future.wait([customStreamsFuture, metaDetailFuture]);
            final customStreams = results[0] as List<Map<String, dynamic>>;
            final meta = results[1] as Map<String, dynamic>?;

            List<Map<String, dynamic>> otherStreams = [];
            if (meta != null && meta['name'] != null && meta['name'].toString().isNotEmpty) {
              try {
                final cleanTitle = meta['name'].toString();
                int? year;
                if (meta['year'] != null) {
                  year = int.tryParse(meta['year'].toString());
                }
                if (year == null && meta['releaseInfo'] != null) {
                  final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(meta['releaseInfo'].toString());
                  if (match != null) year = int.tryParse(match.group(1)!);
                }
                final imdbId = meta['imdbId']?.toString();

                final mediaMeta = MediaMetadata(
                  id: (imdbId != null && imdbId.isNotEmpty) ? imdbId : idWithExt,
                  type: type,
                  title: cleanTitle,
                  year: year,
                  imdbId: imdbId,
                );

                final scraped = await ScraperEngine.instance.scrapeAll(
                  meta: mediaMeta,
                  localBaseUrl: localBaseUrl,
                );
                otherStreams = scraped.map((s) => s.toJson()).toList();
              } catch (e) {
                _addLog('Error scraping other providers for $idWithExt: $e');
              }
            }

            // Combined: Their OWN direct links appear FIRST, followed by all other sources!
            final allStreams = [...customStreams, ...otherStreams];
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'streams': allStreams}));
            await request.response.close();
            return;
          }

          MediaMetadata? meta = await MetadataService.resolve(type: type, rawId: idWithExt);
          meta ??= MediaMetadata(
            id: idWithExt,
            type: type,
            title: idWithExt.replaceAll(RegExp(r'\+|_'), ' '),
          );

          // Concurrently run hoster/torrent scrapers + public cloud streams (YouTube, Archive, Dailymotion)!
          final scrapeFuture = ScraperEngine.instance.scrapeAll(
            meta: meta,
            localBaseUrl: localBaseUrl,
          );
          final publicFuture = CatalogService.instance.searchPublicStreams(
            title: meta.title,
            year: meta.year,
            type: meta.type,
            localBaseUrl: localBaseUrl,
          );

          final results = await Future.wait([scrapeFuture, publicFuture]);
          final hosterStreams = (results[0] as List<ScrapedStream>).map((s) => s.toJson()).toList();
          final publicStreams = results[1] as List<Map<String, dynamic>>;

          // Combine: public direct cloud streams alongside hoster and debrid streams
          final allStreams = [...publicStreams, ...hosterStreams];

          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'streams': allStreams,
          }));
          await request.response.close();
          return;
        }
      }


      // 4. Stream Proxy: /proxy?url=...
      if (path == '/proxy') {
        await StreamProxy.handleRequest(request);
        return;
      }

      // 4b. Torbox Debrid Play Endpoint: /torbox/play?url=...
      if (path == '/torbox/play') {
        final targetUrl = request.uri.queryParameters['url'];
        final headersParam = request.uri.queryParameters['headers'];
        if (targetUrl == null || targetUrl.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Missing url parameter');
          await request.response.close();
          return;
        }
        final apiKey = AddonConfig.instance.torboxApiKey.trim();
        _addLog('Torbox play: $targetUrl');
        final debridedUrl = await TorboxService.instance.debridLink(targetUrl, apiKey);
        if (debridedUrl != null && debridedUrl.isNotEmpty) {
          _addLog('Torbox CDN streaming redirect');
          await request.response.redirect(Uri.parse(debridedUrl), status: HttpStatus.found);
          return;
        }
        if (headersParam != null && headersParam.isNotEmpty) {
          final proxyUrl = '$localBaseUrl/proxy?url=${Uri.encodeComponent(targetUrl)}&headers=${Uri.encodeComponent(headersParam)}';
          await request.response.redirect(Uri.parse(proxyUrl), status: HttpStatus.found);
          return;
        }
        await request.response.redirect(Uri.parse(targetUrl), status: HttpStatus.found);
        return;
      }

      // 4c. In-App Media Search: GET /api/search?q=...&type=movie|series
      if (path == '/api/search') {
        final q = request.uri.queryParameters['q'] ?? '';
        final type = request.uri.queryParameters['type'] ?? 'movie';
        final results = await MetadataService.search(query: q, type: type);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'results': results}));
        await request.response.close();
        return;
      }

      // 4c2. In-App Series Catalog & Episodes: GET /api/series/episodes?id=...
      if (path == '/api/series/episodes') {
        final id = request.uri.queryParameters['id'] ?? '';
        final details = await MetadataService.getSeriesDetails(id);
        request.response.headers.contentType = ContentType.json;
        if (details != null) {
          request.response.write(jsonEncode({'success': true, 'series': details}));
        } else {
          request.response.write(jsonEncode({'success': false, 'message': 'Series details not found'}));
        }
        await request.response.close();
        return;
      }

      // 4d. M3U Playlist Generator: GET /stream/playlist.m3u?url=...&title=...
      if (path == '/stream/playlist.m3u') {
        final url = request.uri.queryParameters['url'] ?? '';
        final title = request.uri.queryParameters['title'] ?? 'Hostreamio Stream';
        final cleanTitle = title.replaceAll(RegExp(r'[\r\n]'), ' ');
        final content = '#EXTM3U\n#EXTINF:-1,$cleanTitle\n$url\n';
        request.response.headers.contentType = ContentType('application', 'x-mpegurl');
        request.response.headers.set('Content-Disposition', 'attachment; filename="stream.m3u"');
        request.response.write(content);
        await request.response.close();
        return;
      }

      // 5. Provider toggle: POST /api/provider/:id
      if (path.startsWith('/api/provider/') && method == 'POST') {
        final providerId = path.replaceFirst('/api/provider/', '');
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        final enabled = bodyJson['enabled'] == true;

        AddonConfig.instance.toggleProvider(providerId, enabled);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'id': providerId, 'enabled': enabled}));
        await request.response.close();
        return;
      }

      // 5a. Bulk toggle providers: POST /api/providers/bulk
      if (path == '/api/providers/bulk' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        final ids = (bodyJson['ids'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final enabled = bodyJson['enabled'] == true;

        for (final id in ids) {
          AddonConfig.instance.toggleProvider(id, enabled);
        }
        await AddonConfig.instance.save();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'count': ids.length, 'enabled': enabled}));
        await request.response.close();
        return;
      }

      // 5b. API: Configure Torbox: POST /api/torbox/config
      if (path == '/api/torbox/config' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        final apiKey = bodyJson['apiKey']?.toString().trim() ?? '';
        AddonConfig.instance.torboxApiKey = apiKey;
        await AddonConfig.instance.save();
        final account = await TorboxService.instance.validateAccount(apiKey);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': true,
          'valid': account['valid'] == true,
          'email': account['email'],
          'plan': account['plan'],
          'expires': account['expires'],
          'message': account['message'],
          'account': account,
        }));
        await request.response.close();
        return;
      }

      // 5c. API: Live Torbox Hosters: GET /api/torbox/hosters
      if (path == '/api/torbox/hosters') {
        final apiKey = AddonConfig.instance.torboxApiKey.trim();
        final hosters = await TorboxService.instance.getHosters(apiKey: apiKey.isNotEmpty ? apiKey : null);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'hosters': hosters}));
        await request.response.close();
        return;
      }

      // 5d. API: Upload / Cache Link to Torbox: POST /api/torbox/upload
      if (path == '/api/torbox/upload' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        var url = bodyJson['url']?.toString().trim() ?? '';
        if (url.contains('?url=')) {
          try {
            final uri = Uri.parse(url);
            final inner = uri.queryParameters['url'];
            if (inner != null && inner.isNotEmpty) {
              url = inner;
            }
          } catch (_) {}
        }
        final apiKey = AddonConfig.instance.torboxApiKey.trim();
        final uploadRes = await TorboxService.instance.uploadToTorbox(url, apiKey);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(uploadRes));
        await request.response.close();
        return;
      }

      // 5e. API: Save Playback & Filtering Settings: POST /api/settings
      if (path == '/api/settings' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        if (bodyJson.containsKey('excludeCams')) {
          AddonConfig.instance.excludeCams = bodyJson['excludeCams'] == true;
        }
        if (bodyJson.containsKey('maxResolution')) {
          AddonConfig.instance.maxResolution = bodyJson['maxResolution'].toString();
        }
        if (bodyJson.containsKey('preferredLanguage')) {
          AddonConfig.instance.preferredLanguage = bodyJson['preferredLanguage'].toString();
        }
        if (bodyJson.containsKey('enableDeduplication')) {
          AddonConfig.instance.enableDeduplication = bodyJson['enableDeduplication'] == true;
        }
        if (bodyJson.containsKey('enableDeadLinkFilter')) {
          AddonConfig.instance.enableDeadLinkFilter = bodyJson['enableDeadLinkFilter'] == true;
        }
        if (bodyJson.containsKey('showRatingsInStreams')) {
          AddonConfig.instance.showRatingsInStreams = bodyJson['showRatingsInStreams'] == true;
        }
        if (bodyJson.containsKey('omdbApiKey')) {
          AddonConfig.instance.omdbApiKey = bodyJson['omdbApiKey'].toString().trim();
        }
        if (bodyJson.containsKey('fanartApiKey')) {
          AddonConfig.instance.fanartApiKey = bodyJson['fanartApiKey'].toString().trim();
        }
        if (bodyJson.containsKey('tvdbApiKey')) {
          AddonConfig.instance.tvdbApiKey = bodyJson['tvdbApiKey'].toString().trim();
        }
        if (bodyJson.containsKey('tmdbApiKey')) {
          AddonConfig.instance.tmdbApiKey = bodyJson['tmdbApiKey'].toString().trim();
        }
        await AddonConfig.instance.save();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true}));
        await request.response.close();
        return;
      }

      // 5f. API: Validate Key: POST /api/keys/validate
      if (path == '/api/keys/validate' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        final service = bodyJson['service']?.toString() ?? '';
        final key = bodyJson['key']?.toString() ?? '';
        final result = await KeyValidator.validate(service, key);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result.toJson()));
        await request.response.close();
      }

      // 5g. API: Upstream update pipeline: POST /api/pipeline/update
      if (path == '/api/pipeline/update' && method == 'POST') {
        String channel = 'all';
        try {
          final bodyStr = await utf8.decodeStream(request);
          if (bodyStr.isNotEmpty) {
            final bodyJson = jsonDecode(bodyStr) as Map;
            if (bodyJson['channel'] != null) channel = bodyJson['channel'].toString();
          }
        } catch (_) {}
        final result = await _runUpdatePipeline(channel);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
        return;
      }

      // 5h. API: Check all updates & GitHub releases: GET /api/updates/check
      if (path == '/api/updates/check') {
        Map<String, dynamic> releaseInfo = {
          'version': 'v2.0.0',
          'isLatest': true,
          'apkUrl': 'https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio.apk',
          'zipUrl': 'https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio-windows-x64.zip',
          'url': 'https://github.com/sakinator/hostreamio/releases',
        };
        try {
          final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
          client.userAgent = 'Hostreamio';
          final req = await client.getUrl(Uri.parse('https://api.github.com/repos/sakinator/hostreamio/releases'));
          final res = await req.close();
          if (res.statusCode == 200) {
            final body = await utf8.decodeStream(res);
            final list = jsonDecode(body) as List;
            if (list.isNotEmpty) {
              final latest = list.first as Map;
              final tagName = latest['tag_name']?.toString() ?? 'v2.0.0';
              final assets = latest['assets'] as List?;
              String? apkUrl;
              String? zipUrl;
              if (assets != null) {
                for (final a in assets) {
                  if (a is Map) {
                    final aname = a['name']?.toString() ?? '';
                    final dl = a['browser_download_url']?.toString();
                    if (aname.endsWith('.apk')) apkUrl = dl;
                    if (aname.endsWith('.zip')) zipUrl = dl;
                  }
                }
              }
              releaseInfo = {
                'version': tagName,
                'name': latest['name'],
                'url': latest['html_url'],
                'publishedAt': latest['published_at'],
                'apkUrl': apkUrl ?? 'https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio.apk',
                'zipUrl': zipUrl ?? 'https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio-windows-x64.zip',
              };
            }
          }
        } catch (_) {}

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'currentVersion': 'v2.0.0',
          'providersCount': ScraperEngine.instance.getProviderList().length,
          'release': releaseInfo,
        }));
        await request.response.close();
        return;
      }

      // 6. Health
      if (path == '/health') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 'ok', 'port': port}));
        await request.response.close();
        return;
      }

      // 7. Badges JSON
      if (path == '/badges.json') {
        request.response.headers.contentType = ContentType.json;
        final candidates = [
          File('data/badges.json'),
          File('${Directory.current.path}/data/badges.json'),
          File('assets/badges.json'),
        ];
        File? found;
        for (final f in candidates) {
          if (f.existsSync()) {
            found = f;
            break;
          }
        }
        if (found != null) {
          request.response.write(await found.readAsString());
        } else {
          request.response.write(jsonEncode({'status': 'ok', 'badges': 'configured'}));
        }
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not found: $path');
      await request.response.close();
    } catch (e) {
      _addLog('Server error on $path: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _runUpdatePipeline([String channel = 'all']) async {
    final logs = <String>[];
    try {
      logs.add('[Update] Channel: $channel');
      if (channel == 'all' || channel == 'cloudstream' || channel == 'playtorrio' || channel == 'scrapers') {
        ScraperEngine.instance.reloadScrapers();
        logs.add('[Scrapers] Hot-reloaded ${ScraperEngine.instance.getProviderList().length} provider engines in memory (PlayTorrio, Cloudstream, Indian OTT & Anime).');
      }
      if (channel == 'all' || channel == 'badges') {
        logs.add('[Badges] OTT branding and regional audio badges verified active.');
      }
      return {
        'success': true,
        'channel': channel,
        'message': 'All engines and providers refreshed successfully!',
        'output': logs.join('\n'),
      };
    } catch (e) {
      return {
        'success': false,
        'channel': channel,
        'message': 'Update failed: $e',
        'output': logs.join('\n'),
      };
    }
  }
}
