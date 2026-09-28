import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'mpd_converter.dart';

class _CachedSegment {
  final Uint8List data;
  final String contentType;
  final DateTime expiresAt;

  _CachedSegment({
    required this.data,
    required this.contentType,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-memory LRU Ring Buffer Segment Cache to eliminate micro-stutter on seek/rewind.
class SegmentCache {
  static final Map<String, _CachedSegment> _cache = {};
  static final List<String> _order = [];
  static int _totalBytes = 0;

  static const int maxBytes = 35 * 1024 * 1024; // 35 MB RAM limit
  static const int maxEntries = 40;

  static _CachedSegment? get(String url) {
    final entry = _cache[url];
    if (entry == null) return null;
    if (entry.isExpired) {
      remove(url);
      return null;
    }
    // Move to end (most recently used)
    _order.remove(url);
    _order.add(url);
    return entry;
  }

  static void put(String url, Uint8List data, String contentType, {bool isInit = false}) {
    if (data.length > 8 * 1024 * 1024) return; // Don't cache oversized chunks

    // Evict if exists
    remove(url);

    // Evict oldest until within limits
    while (_order.isNotEmpty && (_totalBytes + data.length > maxBytes || _cache.length >= maxEntries)) {
      remove(_order.first);
    }

    final ttl = isInit ? const Duration(minutes: 10) : const Duration(seconds: 90);
    _cache[url] = _CachedSegment(
      data: data,
      contentType: contentType,
      expiresAt: DateTime.now().add(ttl),
    );
    _order.add(url);
    _totalBytes += data.length;
  }

  static void remove(String url) {
    final old = _cache.remove(url);
    if (old != null) {
      _order.remove(url);
      _totalBytes -= old.data.length;
    }
  }

  static void clear() {
    _cache.clear();
    _order.clear();
    _totalBytes = 0;
  }
}

class StreamProxy {
  static final HttpClient _client = HttpClient()
    ..badCertificateCallback = ((X509Certificate cert, String host, int port) => true)
    ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    ..connectionTimeout = const Duration(seconds: 15);

  /// Handles incoming /proxy HTTP requests.
  static Future<void> handleRequest(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final targetUrl = query['url'];
    final repId = query['rep_id'];

    if (targetUrl == null || targetUrl.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing "url" query parameter')
        ..close();
      return;
    }

    Uri targetUri;
    try {
      targetUri = Uri.parse(targetUrl);
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid target url: $e')
        ..close();
      return;
    }

    final isHead = request.method.toUpperCase() == 'HEAD';

    // ── Check In-Memory Segment Cache (Ring Buffer) ──
    final cached = SegmentCache.get(targetUrl);
    if (cached != null) {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
      request.response.headers.set('Access-Control-Allow-Headers', '*');
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.set('X-Proxy-Cache', 'HIT');
      if (cached.contentType.isNotEmpty) {
        request.response.headers.set('Content-Type', cached.contentType);
      }
      request.response.headers.contentLength = cached.data.length;
      if (!isHead) {
        request.response.add(cached.data);
      }
      await request.response.close();
      return;
    }

    Map<String, String> customHeaders = {};
    if (query['headers'] != null && query['headers']!.isNotEmpty) {
      try {
        final decoded = jsonDecode(query['headers']!) as Map;
        customHeaders = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (_) {}
    }

    try {
      final req = isHead
          ? await _client.headUrl(targetUri)
          : await _client.getUrl(targetUri);

      // Forward request headers
      request.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower != 'host' && lower != 'connection' && lower != 'content-length') {
          for (final val in values) {
            req.headers.add(name, val);
          }
        }
      });

      // Apply custom headers (e.g. Referer, Origin, User-Agent)
      customHeaders.forEach((name, value) {
        req.headers.set(name, value);
      });

      final res = await req.close();

      request.response.statusCode = res.statusCode;

      final contentType = res.headers.contentType?.mimeType.toLowerCase() ?? '';
      final isHls = contentType.contains('mpegurl') || targetUrl.contains('.m3u8');
      final isMpd = contentType.contains('dash+xml') || targetUrl.contains('.mpd');

      // Copy response headers, excluding hop-by-hop and encoding headers for rewritten content
      res.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'connection' || lower == 'transfer-encoding') return;
        if ((isHls || isMpd) && (lower == 'content-encoding' || lower == 'content-length')) {
          // Decompressed plaintext body is rewritten; do not copy original gzip encoding/length
          return;
        }
        for (final val in values) {
          request.response.headers.add(name, val);
        }
      });

      // Ensure CORS for Nuvio web/app
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
      request.response.headers.set('Access-Control-Allow-Headers', '*');
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.set('X-Proxy-Cache', 'MISS');

      if (isHead) {
        await request.response.close();
        return;
      }

      final proxyBaseUrl = '${request.requestedUri.scheme}://${request.requestedUri.host}:${request.requestedUri.port}/proxy';

      if (isMpd && res.statusCode == HttpStatus.ok) {
        // ── MPEG-DASH to virtual HLS conversion ──
        final bytes = await res.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        final body = utf8.decode(bytes, allowMalformed: true);
        final hlsPlaylist = MpdConverter.convertMpdToHls(
          mpdXml: body,
          baseUri: targetUri,
          proxyBaseUrl: proxyBaseUrl,
          customHeadersJson: query['headers'] ?? '',
          selectedRepId: repId,
        );
        final encoded = utf8.encode(hlsPlaylist);
        request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        request.response.headers.contentLength = encoded.length;
        request.response.add(encoded);
        await request.response.close();
      } else if (isHls && res.statusCode == HttpStatus.ok) {
        // ── Rewrite HLS playlist relative URLs ──
        final bytes = await res.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        final body = utf8.decode(bytes, allowMalformed: true);
        final rewritten = _rewriteHlsPlaylist(
          body: body,
          baseUri: targetUri,
          proxyBaseUrl: proxyBaseUrl,
          customHeadersJson: query['headers'] ?? '',
        );
        final encoded = utf8.encode(rewritten);
        request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        request.response.headers.contentLength = encoded.length;
        request.response.add(encoded);
        await request.response.close();
      } else {
        // Media segment or direct file
        final isMediaSegment = targetUrl.contains('.ts') ||
            targetUrl.contains('.m4s') ||
            targetUrl.contains('.aac') ||
            targetUrl.contains('init') ||
            targetUrl.contains('map');

        final cl = res.headers.contentLength;
        final shouldCache = isMediaSegment &&
            res.statusCode == HttpStatus.ok &&
            cl > 0 &&
            cl <= 8 * 1024 * 1024;

        if (shouldCache) {
          final bytes = await res.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
          final uint8Data = Uint8List.fromList(bytes);
          final isInit = targetUrl.contains('init') || targetUrl.contains('map');
          SegmentCache.put(targetUrl, uint8Data, contentType, isInit: isInit);

          request.response.headers.contentLength = uint8Data.length;
          request.response.add(uint8Data);
          await request.response.close();
        } else {
          // Stream directly to client chunk-by-chunk without RAM buffering (prevents OOM on large MP4/MKV)
          await request.response.addStream(res);
          await request.response.close();
        }
      }
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('Proxy error: $e');
        await request.response.close();
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  static String _rewriteHlsPlaylist({
    required String body,
    required Uri baseUri,
    required String proxyBaseUrl,
    required String customHeadersJson,
  }) {
    final lines = body.split('\n');
    final out = <String>[];

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        out.add(line);
        continue;
      }

      if (trimmed.startsWith('#')) {
        // Check for URI in tags like #EXT-X-KEY:METHOD=AES-128,URI="..." or #EXT-X-MAP:URI="..."
        if (trimmed.contains('URI="')) {
          final rewrittenTag = trimmed.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (m) {
              final rawUri = m.group(1)!;
              final resolved = baseUri.resolve(rawUri).toString();
              final proxied = '$proxyBaseUrl?url=${Uri.encodeComponent(resolved)}&headers=${Uri.encodeComponent(customHeadersJson)}';
              return 'URI="$proxied"';
            },
          );
          out.add(rewrittenTag);
        } else {
          out.add(line);
        }
      } else {
        // Segment or variant URI
        final resolved = baseUri.resolve(trimmed).toString();
        final proxied = '$proxyBaseUrl?url=${Uri.encodeComponent(resolved)}&headers=${Uri.encodeComponent(customHeadersJson)}';
        out.add(proxied);
      }
    }

    return out.join('\n');
  }
}
