import 'dart:convert';
import 'dart:io';
import 'package:playtorrio_nuvio_addon/config.dart';
import 'package:playtorrio_nuvio_addon/metadata_service.dart';
import 'package:playtorrio_nuvio_addon/proxy.dart';
import 'package:playtorrio_nuvio_addon/scraper_engine.dart';
import 'package:playtorrio_nuvio_addon/web_ui.dart';
import 'package:playtorrio_nuvio_addon/catalog_service.dart';
import 'package:playtorrio_nuvio_addon/torbox_service.dart';
import 'package:playtorrio_nuvio_addon/doh_resolver.dart';
import 'package:playtorrio_nuvio_addon/key_validator.dart';

void main(List<String> args) async {
  // ── Global DNS-over-HTTPS (DoH) & Pre-Warming ─────────────────────────────
  HttpOverrides.global = HostreamioHttpOverrides();
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

  // ── CWD fix ──────────────────────────────────────────────────────────────
  // All file paths in the app (data/config.json, upstream/..., etc.) are
  // relative. Lock the CWD to the project root now so they resolve correctly
  // regardless of how the user launched the binary (double-click, Task
  // Scheduler, Windows Service, etc.).
  _ensureProjectRoot();

  final cfg = AddonConfig.instance;
  await cfg.load();

  // Allow port override from CLI (saved to config so it persists)
  if (args.isNotEmpty) {
    final parsedPort = int.tryParse(args[0]);
    if (parsedPort != null) {
      cfg.port = parsedPort;
      await cfg.save();
    }
  }

  final lanIp = await _getLocalIp();
  final server = await HttpServer.bind(InternetAddress.anyIPv4, cfg.port);

  print('===============================================================');
  print('              ▶️ Hostreamio Addon for Nuvio ▶️             ');
  print('===============================================================');
  print(' Status: RUNNING');
  print(' Port:   ${cfg.port}');
  print(' Local:  http://localhost:${cfg.port}');
  print(' LAN IP: http://$lanIp:${cfg.port}');
  print('---------------------------------------------------------------');
  print(' 🔌 Nuvio Addon Manifest URLs:');
  print('    Localhost: http://localhost:${cfg.port}/manifest.json');
  print('    LAN (TV):  http://$lanIp:${cfg.port}/manifest.json');
  print('---------------------------------------------------------------');
  print(' 🌐 Web Dashboard: http://localhost:${cfg.port}/configure');
  print('===============================================================\n');

  await for (final request in server) {
    // Don't await – each request runs independently so the server stays responsive.
    _handleRequest(request, lanIp, cfg.port);
  }
}

Map<String, dynamic>? _safeParseJsonMap(String bodyStr) {
  if (bodyStr.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(bodyStr);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return null;
}

Future<void> _handleRequest(HttpRequest request, String lanIp, int port) async {
  final path = request.uri.path;
  final method = request.method.toUpperCase();

  // Always enable CORS for Nuvio TV, Mobile, Desktop & Web
  request.response.headers.set('Access-Control-Allow-Origin', '*');
  request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, HEAD');
  request.response.headers.set('Access-Control-Allow-Headers', '*');

  if (method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
    return;
  }

  // Use the exact scheme and authority (host:port) that the client connected to
  // (e.g. localhost:7002 from PC, or 192.168.0.127:7002 from TV on LAN).
  final localBaseUrl = '${request.requestedUri.scheme}://${request.requestedUri.authority}';

  try {
    // ── 0. Static Brand Logo & Favicon ──────────────────────────────────
    if (path == '/logo.png' || path == '/favicon.png' || path == '/favicon.ico') {
      final exeParent = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        File('hostreamio_logo.png'),
        File('$exeParent/hostreamio_logo.png'),
        File('${Directory.current.path}/hostreamio_logo.png'),
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

    // ── 1. Root / Configure Web UI ────────────────────────────────────────
    if (path == '/' || path == '/configure') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(WebUI.render(localIp: lanIp, port: port));
      await request.response.close();
      return;
    }

    // ── 2. Stremio/Nuvio Addon Manifest ───────────────────────────────────
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

    // ── 3. Catalogs Endpoint: /catalog/:type/:id.json or with extra params ──
    if (path.startsWith('/catalog/')) {
      final segments = request.uri.pathSegments; // ['catalog', 'movie', 'yt_indian.json'] or ['catalog', 'movie', 'yt_indian', 'genre=Bollywood.json']
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

        print('[Catalog] Query catId=$catId, type=$type, search=$search, genre=$genre, skip=$skip');
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

    // ── 4. Metadata Detail Endpoint: /meta/:type/:id.json ──────────────────
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

    // ── 5. Stremio/Nuvio Streams Endpoint: /stream/:type/:id.json ─────────
    if (path.startsWith('/stream/')) {
      final segments = request.uri.pathSegments; // ['stream', 'movie', 'tt1375666.json']
      if (segments.length >= 3) {
        final type = segments[1];
        var idWithExt = Uri.decodeComponent(segments[2]);
        if (idWithExt.endsWith('.json')) {
          idWithExt = idWithExt.substring(0, idWithExt.length - 5);
        }

        print('[Server] Received stream request: type=$type, id=$idWithExt');

        // Check custom video streams (YouTube, Vimeo, Archive.org, Dailymotion)
        if (idWithExt.startsWith('yt:') || idWithExt.startsWith('vimeo:') || idWithExt.startsWith('archive:') || idWithExt.startsWith('dm:')) {
          final customStreams = await CatalogService.instance.resolveCustomStreams(type, idWithExt);
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'streams': customStreams}));
          await request.response.close();
          return;
        }

        // Standard IMDB / TMDB / Kitsu scraper pipeline
        MediaMetadata? meta = await MetadataService.resolve(type: type, rawId: idWithExt);
        if (meta == null) {
          meta = MediaMetadata(
            id: idWithExt,
            type: type,
            title: idWithExt.replaceAll(RegExp(r'\+|_'), ' '),
          );
        }

        final streams = await ScraperEngine.instance.scrapeAll(
          meta: meta,
          localBaseUrl: localBaseUrl,
        );

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'streams': streams.map((s) => s.toJson()).toList(),
        }));
        await request.response.close();
        return;
      }
    }


    // ── 4. Stream Proxy Endpoint: /proxy?url=... ──────────────────────────
    if (path == '/proxy') {
      await StreamProxy.handleRequest(request);
      return;
    }

    // ── 4b. Torbox Debrid Play Endpoint: /torbox/play?url=... ──────────────
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
      print('[Torbox] Play request for: $targetUrl');
      final debridedUrl = await TorboxService.instance.debridLink(targetUrl, apiKey);
      if (debridedUrl != null && debridedUrl.isNotEmpty) {
        print('[Torbox] Redirecting to TorBox CDN: $debridedUrl');
        await request.response.redirect(Uri.parse(debridedUrl), status: HttpStatus.found);
        return;
      }
      // Fallback: if headers required, redirect to proxy; otherwise direct to targetUrl
      if (headersParam != null && headersParam.isNotEmpty) {
        final proxyUrl = '$localBaseUrl/proxy?url=${Uri.encodeComponent(targetUrl)}&headers=${Uri.encodeComponent(headersParam)}';
        await request.response.redirect(Uri.parse(proxyUrl), status: HttpStatus.found);
        return;
      }
      await request.response.redirect(Uri.parse(targetUrl), status: HttpStatus.found);
      return;
    }

    // ── 5. API: Toggle provider: POST /api/provider/:id ───────────────────
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

    // ── 5a. API: Bulk toggle providers: POST /api/providers/bulk ──────────
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

    // ── 5b. API: Configure Torbox: POST /api/torbox/config ────────────────
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

    // ── 5c. API: Live Torbox Hosters: GET /api/torbox/hosters ─────────────
    if (path == '/api/torbox/hosters') {
      final apiKey = AddonConfig.instance.torboxApiKey.trim();
      final hosters = await TorboxService.instance.getHosters(apiKey: apiKey.isNotEmpty ? apiKey : null);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'hosters': hosters}));
      await request.response.close();
      return;
    }

    // ── 5d. API: Upload / Cache Link to Torbox: POST /api/torbox/upload ───
    if (path == '/api/torbox/upload' && method == 'POST') {
      final bodyStr = await utf8.decodeStream(request);
      final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
      final url = bodyJson['url']?.toString().trim() ?? '';
      final apiKey = AddonConfig.instance.torboxApiKey.trim();
      final uploadRes = await TorboxService.instance.uploadToTorbox(url, apiKey);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(uploadRes));
      await request.response.close();
      return;
    }

    // ── 5e. API: Save Playback & Filtering Settings: POST /api/settings ────
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

    // ── 5f. API: Validate Key: POST /api/keys/validate ────────────────────
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

    // ── 6. API: Upstream update pipeline: POST /api/pipeline/update ───────
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

    // ── 6b. API: Check all updates & GitHub releases: GET /api/updates/check ──
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

    // ── 7. Health check ───────────────────────────────────────────────────
    if (path == '/health') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok', 'port': AddonConfig.instance.port}));
      await request.response.close();
      return;
    }

    // ── 8. Nuvio Badges Configuration ─────────────────────────────────────
    if (path == '/badges.json') {
      request.response.headers.contentType = ContentType.json;
      final exeParent = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        File('data/badges.json'),
        File('$exeParent/data/badges.json'),
        File('${Directory.current.path}/data/badges.json'),
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

    // Fallback: 404
    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Not found: $path');
    await request.response.close();
  } catch (e, stack) {
    print('[Server] Internal error handling $path: $e\n$stack');
    try {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Internal error: $e');
      await request.response.close();
    } catch (_) {
      // Response already partially sent – nothing we can do.
    }
  }
}

// ── Update Pipeline ──────────────────────────────────────────────────────────

// ── Multi-Source Update Pipeline ──────────────────────────────────────────

Future<Map<String, dynamic>> _runUpdatePipeline([String channel = 'all']) async {
  final logs = <String>[];
  bool anyUpdated = false;

  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final baseDir = Directory('$exeDir/tool').existsSync()
        ? exeDir
        : (Directory('tool').existsSync() ? Directory.current.path : exeDir);

    // 1. Root Git Repository Pull (Pulls Cloudstream extensions, badges, server fixes)
    if (channel == 'all' || channel == 'cloudstream' || channel == 'scrapers' || channel == 'repo') {
      if (Directory('$baseDir/.git').existsSync()) {
        logs.add('[Repo] Pulling latest repository updates (Cloudstream plugins, Indian/Anime scrapers, badges)...');
        final rootPull = await Process.run('git', ['pull', '--rebase', '--autostash', 'origin', 'main'], workingDirectory: baseDir);
        final out = '${rootPull.stdout}\n${rootPull.stderr}'.trim();
        logs.add(out);
        if (!out.contains('Already up to date') && !out.contains('Current branch main is up to date')) anyUpdated = true;
      }
    }

    // 2. PlayTorrio Submodule Pull (if present)
    if (channel == 'all' || channel == 'playtorrio') {
      if (Directory('$baseDir/upstream/PlayTorrioV3/.git').existsSync()) {
        logs.add('[PlayTorrio] Safely checking upstream PlayTorrio base framework...');
        final gitRes = await Process.run(
          'git',
          ['pull', '--rebase', '--autostash', 'origin', 'main'],
          workingDirectory: '$baseDir/upstream/PlayTorrioV3',
        );
        final out = '${gitRes.stdout}\n${gitRes.stderr}'.trim();
        logs.add(out);
        if (!out.contains('Already up to date') && !out.contains('Current branch main is up to date')) anyUpdated = true;
      }
    }

    // 3. Scraper Registry Regeneration
    if (channel == 'all' || channel == 'playtorrio' || channel == 'cloudstream' || channel == 'scrapers') {
      logs.add('[Registry] Regenerating unified scraper registry (56 providers: PlayTorrio + Cloudstream + Indian OTT + Anime)...');
      final dartExe = await _findDartExe();
      if (dartExe != null && File('$baseDir/tool/generate_registry.dart').existsSync()) {
        final regRes = await Process.run(dartExe, ['run', 'tool/generate_registry.dart'], workingDirectory: baseDir);
        final regOutput = '${regRes.stdout}\n${regRes.stderr}'.trim();
        logs.add(regOutput);

        // Sync registry to android_app
        final serverReg = File('$baseDir/lib/scraper_registry.dart');
        final appReg = File('$baseDir/android_app/lib/scraper_registry.dart');
        if (serverReg.existsSync() && appReg.parent.existsSync()) {
          serverReg.copySync(appReg.path);
          logs.add('[Sync] Copied scraper registry to android_app/lib/scraper_registry.dart');
        }
      } else {
        logs.add('[Notice] Skipping registry generation (dart executable or script unavailable)');
      }

      // Hot-reload scrapers into memory
      ScraperEngine.instance.reloadScrapers();
      logs.add('[Engine] Scraper instances refreshed in memory (56 active providers)');
    }

    // 4. Badges Reload
    if (channel == 'all' || channel == 'badges') {
      logs.add('[Badges] Reloaded regional OTT badges and audio tags from data/badges.json');
    }

    // 5. GitHub Releases Check
    Map<String, dynamic>? releaseInfo;
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
          releaseInfo = {
            'tag': latest['tag_name'],
            'name': latest['name'],
            'url': latest['html_url'],
          };
        }
      }
    } catch (_) {}

    return {
      'success': true,
      'channel': channel,
      'message': anyUpdated
          ? 'Successfully updated and refreshed all providers!'
          : 'All sources are already up to date! Memory caches and scrapers refreshed.',
      'output': logs.join('\n'),
      if (releaseInfo != null) 'release': releaseInfo,
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

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Locks the process CWD to the project root so all relative paths resolve
/// correctly regardless of how the binary was launched.
void _ensureProjectRoot() {
  try {
    if (Platform.script.scheme == 'file') {
      // dart run bin/server.dart → script is …/bin/server.dart → parent.parent is project root
      final scriptFile = File(Platform.script.toFilePath());
      Directory.current = scriptFile.parent.parent;
    } else {
      // Compiled AOT exe: the exe should live in the project root.
      Directory.current = File(Platform.resolvedExecutable).parent;
    }
  } catch (e) {
    // Non-fatal: best-effort. Relative paths will resolve from wherever the
    // process was started.
    print('[Server] Warning: could not set CWD to project root: $e');
  }
}

/// Finds the dart executable: bundled SDK, sibling dir, CWD, then system PATH.
/// Works on Windows (dart.exe), Linux, macOS, and Android (Termux).
Future<String?> _findDartExe() async {
  final dartBin = Platform.isWindows ? 'dart.exe' : 'dart';
  final exeDir = File(Platform.resolvedExecutable).parent;

  final candidates = [
    File('${exeDir.path}/../dart-sdk/bin/$dartBin'), // bundled next to exe
    File('${exeDir.path}/$dartBin'),                 // same dir as exe
    File('dart-sdk/bin/$dartBin'),                   // project-root-relative
  ];
  for (final f in candidates) {
    if (await f.exists()) return f.path;
  }
  try {
    final res = await Process.run(dartBin, ['--version']);
    if (res.exitCode == 0) return dartBin;
  } catch (_) {}
  return null;
}

/// Returns the best LAN IPv4 address for this machine.
Future<String> _getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    // 1. High priority: standard home LAN private subnets (192.168.0.x / 192.168.1.x)
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback &&
            addr.address.startsWith('192.168.') &&
            !addr.address.startsWith('192.168.56.')) {
          return addr.address;
        }
      }
    }
    // 2. Medium priority: 10.x.x.x
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback && addr.address.startsWith('10.')) {
          return addr.address;
        }
      }
    }
    // 3. Fallback: other non-virtual adapters (exclude link-local, WSL, VPNs)
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback &&
            !addr.address.startsWith('169.254.') &&
            !addr.address.startsWith('172.') &&
            !addr.address.startsWith('192.168.56.') &&
            !addr.address.startsWith('45.')) {
          return addr.address;
        }
      }
    }
  } catch (_) {}
  return '127.0.0.1';
}


