import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'assets/caching_video.dart';

/// TorboxService: Integrates TorBox API (v1) for cloud caching,
/// live hosters list, cache checks, and debriding web/hoster links.
class TorboxService {
  static final TorboxService instance = TorboxService._();

  TorboxService._();

  static const String _apiBase = 'https://api.torbox.app/v1/api';

  // In-memory cache for hosters list & checkcached results
  static List<Map<String, dynamic>>? _cachedHosters;
  static DateTime? _hostersExpiry;
  static final Map<String, ({bool isCached, DateTime expiry})> _cacheLookup = {};

  static const _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  Map<String, String> _headers(String? apiKey, {bool isJson = false}) {
    final h = <String, String>{
      'User-Agent': _defaultUserAgent,
    };
    if (apiKey != null && apiKey.isNotEmpty) {
      h['Authorization'] = 'Bearer $apiKey';
    }
    if (isJson) {
      h['Content-Type'] = 'application/json';
    }
    return h;
  }

  /// Checks if an API key is valid and returns user plan information
  Future<Map<String, dynamic>> validateAccount(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return {'valid': false, 'message': 'API key is empty'};
    }
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/user/me'),
        headers: _headers(key),
      ).timeout(const Duration(seconds: 7));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map && (data['success'] == true || data['data'] != null)) {
        final userData = data['data'] is Map ? data['data'] as Map : {};
        var rawPlan = userData['plan'];
        String planStr = 'Standard';
        if (rawPlan is int) {
          switch (rawPlan) {
            case 0:
              planStr = 'Free';
              break;
            case 1:
              planStr = 'Essential';
              break;
            case 2:
              planStr = 'Pro';
              break;
            case 3:
              planStr = 'Standard';
              break;
            default:
              planStr = 'Tier $rawPlan';
          }
        } else if (rawPlan != null && rawPlan.toString().isNotEmpty) {
          planStr = rawPlan.toString();
        }
        final email = userData['email']?.toString() ?? 'Active User';
        final expires = userData['expires_at']?.toString();
        return {
          'valid': true,
          'email': email,
          'plan': planStr,
          'expires': expires,
          'message': 'Connected to Torbox ($planStr plan)',
        };
      }
      final errorMsg = data is Map ? (data['detail'] ?? data['error'] ?? 'HTTP ${res.statusCode}') : 'HTTP ${res.statusCode}';
      return {'valid': false, 'message': 'Invalid API Key ($errorMsg)'};
    } catch (e) {
      return {'valid': false, 'message': 'Connection error: $e'};
    }
  }

  /// Fetches live list of supported hosters from TorBox
  Future<List<Map<String, dynamic>>> getHosters({String? apiKey}) async {
    final now = DateTime.now();
    if (_cachedHosters != null && _hostersExpiry != null && now.isBefore(_hostersExpiry!)) {
      return _cachedHosters!;
    }

    try {
      final res = await http.get(
        Uri.parse('$_apiBase/webdl/hosters'),
        headers: _headers(apiKey),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data is Map && data['data'] is List)
            ? data['data'] as List
            : (data is List)
                ? data
                : [];

        _cachedHosters = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _hostersExpiry = now.add(const Duration(hours: 1));
        return _cachedHosters!;
      }
    } catch (_) {}

    return _cachedHosters ?? [];
  }

  /// Checks if a single direct link or web hoster link is cached on Torbox servers
  Future<bool> checkCached(String url, String apiKey) async {
    final batch = await checkCachedBatch([url], apiKey);
    return batch[url.trim()] ?? false;
  }

  /// Batch checks direct links/web hoster links on TorBox servers in 1 fast API request
  Future<Map<String, bool>> checkCachedBatch(List<String> urls, String apiKey) async {
    if (apiKey.isEmpty || urls.isEmpty) return {};

    final results = <String, bool>{};
    final uncached = <String, String>{}; // md5 -> url

    final now = DateTime.now();
    for (final url in urls) {
      final clean = url.trim();
      if (clean.isEmpty) continue;
      final hash = md5.convert(utf8.encode(clean)).toString();
      final entry = _cacheLookup[hash];
      if (entry != null && now.isBefore(entry.expiry)) {
        results[clean] = entry.isCached;
      } else {
        uncached[hash] = clean;
      }
    }

    if (uncached.isNotEmpty) {
      final hashList = uncached.keys.toList();
      for (var i = 0; i < hashList.length; i += 80) {
        final chunk = hashList.skip(i).take(80).toList();
        final hashParam = chunk.join(',');
        try {
          final uri = Uri.parse('$_apiBase/webdl/checkcached?hash=$hashParam&format=object');
          final res = await http.get(
            uri,
            headers: _headers(apiKey),
          ).timeout(const Duration(seconds: 4));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data is Map && data['data'] is Map) {
              final dataMap = data['data'] as Map;
              for (final h in chunk) {
                final val = dataMap[h];
                final isCached = val != null && (val is Map || val == true);
                _cacheLookup[h] = (
                  isCached: isCached,
                  expiry: now.add(Duration(minutes: isCached ? 15 : 2)),
                );
                final orig = uncached[h];
                if (orig != null) results[orig] = isCached;
              }
            }
          }
        } catch (_) {}
      }
    }

    for (final url in urls) {
      results.putIfAbsent(url.trim(), () => false);
    }
    return results;
  }

  /// Checks whether a list of torrent info hashes are cached on TorBox cloud CDN
  Future<Map<String, bool>> checkCachedTorrentsBatch(List<String> infoHashes, String apiKey) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty || infoHashes.isEmpty) return {};

    final results = <String, bool>{};
    final now = DateTime.now();
    final uncached = <String>[];

    for (final h in infoHashes) {
      final cleanH = h.trim().toLowerCase();
      if (cleanH.isEmpty) continue;
      final cachedEntry = _cacheLookup['t_$cleanH'];
      if (cachedEntry != null && now.isBefore(cachedEntry.expiry)) {
        results[cleanH] = cachedEntry.isCached;
      } else {
        uncached.add(cleanH);
      }
    }

    if (uncached.isNotEmpty) {
      const chunkSize = 50;
      for (var i = 0; i < uncached.length; i += chunkSize) {
        final chunk = uncached.skip(i).take(chunkSize).toList();
        final hashParam = chunk.join(',');
        try {
          final uri = Uri.parse('$_apiBase/torrents/checkcached?hash=$hashParam&format=object');
          final res = await http.get(
            uri,
            headers: _headers(cleanKey),
          ).timeout(const Duration(seconds: 4));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data is Map && data['data'] is Map) {
              final dataMap = data['data'] as Map;
              for (final h in chunk) {
                final val = dataMap[h];
                final isCached = val != null && (val is Map || val == true);
                _cacheLookup['t_$h'] = (
                  isCached: isCached,
                  expiry: now.add(Duration(minutes: isCached ? 15 : 2)),
                );
                results[h] = isCached;
              }
            }
          }
        } catch (_) {}
      }
    }

    for (final h in infoHashes) {
      results.putIfAbsent(h.trim().toLowerCase(), () => false);
    }
    return results;
  }

  /// Debrids or streams a cached torrent from TorBox cloud CDN
  Future<String?> debridTorrent(String magnetOrHash, String apiKey) async {
    lastDebridError = null;
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      lastDebridError = 'TorBox API key is not configured in settings.';
      return null;
    }
    try {
      final magnet = magnetOrHash.startsWith('magnet:')
          ? magnetOrHash
          : 'magnet:?xt=urn:btih:$magnetOrHash';

      final createUrl = Uri.parse('$_apiBase/torrents/createtorrent');
      final res = await http.post(
        createUrl,
        headers: {
          'User-Agent': _defaultUserAgent,
          'Authorization': 'Bearer $cleanKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'magnet': magnet,
        },
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map && data['success'] == true) {
        final torrentId = data['data']?['torrent_id'] ?? data['data']?['id'];
        if (torrentId != null) {
          final reqUri = Uri.parse('$_apiBase/torrents/requestdl').replace(queryParameters: {
            'token': cleanKey,
            'torrent_id': torrentId.toString(),
          });
          final dlRes = await http.get(
            reqUri,
            headers: _headers(cleanKey),
          ).timeout(const Duration(seconds: 5));

          if (dlRes.statusCode == 200) {
            final dlData = jsonDecode(dlRes.body);
            if (dlData is Map && dlData['data'] is String) {
              return dlData['data'] as String;
            }
          }
        }
      }
    } catch (e) {
      lastDebridError = 'TorBox torrent debrid error: $e';
    }
    return null;
  }

  /// Uploads / sends a web download link to Torbox to cache/download it
  Future<Map<String, dynamic>> uploadToTorbox(String url, String apiKey) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return {'success': false, 'message': 'Torbox API key not configured'};
    }
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      return {'success': false, 'message': 'Empty link provided'};
    }
    try {
      final createUrl = Uri.parse('$_apiBase/webdl/createwebdownload');
      final res = await http.post(
        createUrl,
        headers: {
          'User-Agent': _defaultUserAgent,
          'Authorization': 'Bearer $cleanKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'link': cleanUrl,
        },
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map && data['success'] == true) {
        return {
          'success': true,
          'message': data['detail']?.toString() ?? 'Successfully queued to Torbox!',
          'data': data['data'],
        };
      } else {
        String errorMsg = 'Upload failed';
        if (data is Map) {
          errorMsg = data['detail']?.toString() ?? data['error']?.toString() ?? 'HTTP ${res.statusCode}';
        }
        return {
          'success': false,
          'message': errorMsg,
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Error sending to Torbox: $e'};
    }
  }

  String? lastDebridError;

  /// Initiates or retrieves a debrided Torbox web download stream URL.
  /// If file is already cached, returns instant CDN URL (<1s).
  /// If not cached, initiates Torbox cloud caching and returns null.
  Future<String?> debridLink(String url, String apiKey) async {
    lastDebridError = null;
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      lastDebridError = 'TorBox API key is not configured in settings.';
      return null;
    }
    if (url.startsWith('magnet:') || RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(url)) {
      return debridTorrent(url, cleanKey);
    }
    try {
      final res = await uploadToTorbox(url, cleanKey);
      if (res['success'] == true) {
        final webId = res['data']?['webdownload_id'] ?? res['data']?['id'];
        if (webId != null) {
          // Request direct streaming link with URL query encoding
          final reqUri = Uri.parse('$_apiBase/webdl/requestdl').replace(queryParameters: {
            'token': cleanKey,
            'web_id': webId.toString(),
          });
          final dlRes = await http.get(
            reqUri,
            headers: _headers(cleanKey),
          ).timeout(const Duration(seconds: 5));

          if (dlRes.statusCode == 200) {
            final dlData = jsonDecode(dlRes.body);
            if (dlData is Map && dlData['data'] is String) {
              return dlData['data'] as String;
            }
            if (dlData is Map && dlData['detail'] != null) {
              lastDebridError = dlData['detail'].toString();
            } else if (dlData is Map && dlData['error'] != null) {
              lastDebridError = dlData['error'].toString();
            }
          } else {
            try {
              final errJson = jsonDecode(dlRes.body);
              lastDebridError = errJson['detail']?.toString() ?? errJson['error']?.toString() ?? 'TorBox returned HTTP ${dlRes.statusCode}';
            } catch (_) {
              lastDebridError = 'TorBox returned HTTP ${dlRes.statusCode}';
            }
          }
        } else {
          lastDebridError = 'TorBox accepted link but did not return a download ID.';
        }
      } else {
        lastDebridError = res['message']?.toString() ?? 'TorBox could not unrestrict this link.';
      }
    } catch (e) {
      lastDebridError = 'TorBox connection error: $e';
    }
    return null;
  }

  // Local map of active caching jobs initiated from Hostreamio
  final Map<String, Map<String, dynamic>> _locallyInitiatedJobs = {};

  /// Tracks a caching job initiated in Hostreamio
  void trackCachingJob({
    required String url,
    String? name,
    String? type,
    dynamic id,
    String? status,
  }) {
    final key = (id != null) ? id.toString() : url;
    _locallyInitiatedJobs[key] = {
      'id': id ?? key.hashCode.abs().toString(),
      'name': name ?? _extractFileNameFromUrl(url),
      'type': type ?? (url.startsWith('magnet:') ? 'torrent' : 'webdl'),
      'status': status ?? 'caching',
      'progress': 0.05,
      'progressPercent': 5,
      'speed': 'Connecting...',
      'eta': 'Calculating...',
      'size': 'Calculating...',
      'rawUrl': url,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Returns the embedded/cached in-progress video notification MP4 bytes
  Uint8List getCachingVideoBytes() {
    return CachingVideoAsset.bytes;
  }

  static String _extractFileNameFromUrl(String url) {
    if (url.startsWith('magnet:')) {
      final dn = RegExp(r'dn=([^&]+)').firstMatch(url);
      if (dn != null) return Uri.decodeComponent(dn.group(1)!);
      return 'Torrent Download';
    }
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) return Uri.decodeComponent(segs.last);
    } catch (_) {}
    return url.length > 45 ? url.substring(0, 45) + '...' : url;
  }

  static String _formatBytes(dynamic bytes) {
    if (bytes == null) return '0 B';
    final num b = (bytes is num) ? bytes : (num.tryParse(bytes.toString()) ?? 0);
    if (b <= 0) return '0 B';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatSpeed(dynamic bytesPerSec) {
    if (bytesPerSec == null) return '0 KB/s';
    final num b = (bytesPerSec is num) ? bytesPerSec : (num.tryParse(bytesPerSec.toString()) ?? 0);
    if (b <= 0) return '0 KB/s';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB/s';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  static String _formatEta(dynamic etaSeconds) {
    if (etaSeconds == null) return '--';
    final num s = (etaSeconds is num) ? etaSeconds : (num.tryParse(etaSeconds.toString()) ?? 0);
    if (s <= 0) return 'Ready';
    if (s < 60) return '${s.round()}s';
    if (s < 3600) return '${(s / 60).floor()}m ${(s % 60).round()}s';
    return '${(s / 3600).floor()}h ${((s % 3600) / 60).floor()}m';
  }

  /// Retrieves the unified live TorBox caching queue (WebDL + Torrents)
  Future<List<Map<String, dynamic>>> getLiveCacheQueue(String apiKey) async {
    final cleanKey = apiKey.trim();
    final items = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    if (cleanKey.isNotEmpty) {
      // 1. Fetch Web Downloads
      try {
        final webdlUri = Uri.parse('$_apiBase/webdl/mylist?bypass_cache=true');
        final res = await http.get(webdlUri, headers: _headers(cleanKey)).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map && data['data'] is List) {
            for (final d in data['data']) {
              if (d is! Map) continue;
              final id = d['id']?.toString() ?? '';
              if (id.isEmpty) continue;
              seenIds.add(id);

              final rawState = (d['download_state'] ?? d['download_status'] ?? '').toString().toLowerCase();
              final isFinished = d['download_finished'] == true || rawState == 'completed' || rawState == 'cached';
              final isFailed = rawState.contains('fail') || rawState.contains('error');

              String status = isFinished ? 'completed' : (isFailed ? 'failed' : 'caching');
              double rawProgress = 0.0;
              if (d['progress'] is num) {
                final num p = d['progress'];
                rawProgress = p > 1.0 ? p / 100.0 : p.toDouble();
              }
              if (isFinished) rawProgress = 1.0;

              final name = d['name']?.toString() ?? d['url']?.toString() ?? 'Web Download';
              final rawUrl = d['url']?.toString() ?? '';

              items.add({
                'id': id,
                'name': name,
                'type': 'webdl',
                'status': status,
                'progress': rawProgress.clamp(0.0, 1.0),
                'progressPercent': (rawProgress * 100).round().clamp(0, 100),
                'speed': _formatSpeed(d['download_speed']),
                'eta': isFinished ? 'Ready' : _formatEta(d['eta']),
                'size': _formatBytes(d['size']),
                'rawUrl': rawUrl,
                'createdAt': d['created_at']?.toString() ?? '',
                'updatedAt': d['updated_at']?.toString() ?? '',
              });
            }
          }
        }
      } catch (_) {}

      // 2. Fetch Torrents if any exist on the user's account
      try {
        final torrentUri = Uri.parse('$_apiBase/torrents/mylist?bypass_cache=true');
        final res = await http.get(torrentUri, headers: _headers(cleanKey)).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map && data['data'] is List) {
            for (final d in data['data']) {
              if (d is! Map) continue;
              final id = d['id']?.toString() ?? '';
              if (id.isEmpty) continue;
              seenIds.add(id);

              final rawState = (d['download_state'] ?? '').toString().toLowerCase();
              final isFinished = d['download_finished'] == true || rawState == 'completed' || rawState == 'cached';
              final isFailed = rawState.contains('fail') || rawState.contains('error');

              String status = isFinished ? 'completed' : (isFailed ? 'failed' : 'caching');
              double rawProgress = 0.0;
              if (d['progress'] is num) {
                final num p = d['progress'];
                rawProgress = p > 1.0 ? p / 100.0 : p.toDouble();
              }
              if (isFinished) rawProgress = 1.0;

              final name = d['name']?.toString() ?? 'Torrent Release';
              final hash = d['hash']?.toString() ?? '';

              items.add({
                'id': id,
                'name': name,
                'type': 'torrent',
                'status': status,
                'progress': rawProgress.clamp(0.0, 1.0),
                'progressPercent': (rawProgress * 100).round().clamp(0, 100),
                'speed': _formatSpeed(d['download_speed']),
                'eta': isFinished ? 'Ready' : _formatEta(d['eta']),
                'size': _formatBytes(d['size']),
                'hash': hash,
                'rawUrl': hash.isNotEmpty ? 'magnet:?xt=urn:btih:$hash' : '',
                'createdAt': d['created_at']?.toString() ?? '',
                'updatedAt': d['updated_at']?.toString() ?? '',
              });
            }
          }
        }
      } catch (_) {}
    }

    // 3. Merge locally initiated jobs that haven't shown up in TorBox API yet
    for (final entry in _locallyInitiatedJobs.entries) {
      final local = entry.value;
      final localId = local['id']?.toString();
      if (localId != null && !seenIds.contains(localId)) {
        items.insert(0, Map<String, dynamic>.from(local));
      }
    }

    return items;
  }

  /// Deletes a web download or torrent item from TorBox cloud
  Future<bool> deleteQueueItem(String id, String type, String apiKey) async {
    final cleanKey = apiKey.trim();
    _locallyInitiatedJobs.remove(id);

    if (cleanKey.isEmpty || id.isEmpty) return true;

    try {
      if (type == 'torrent') {
        final uri = Uri.parse('$_apiBase/torrents/controltorrent');
        final res = await http.post(
          uri,
          headers: _headers(cleanKey),
          body: jsonEncode({
            'torrent_id': int.tryParse(id) ?? id,
            'operation': 'delete',
          }),
        ).timeout(const Duration(seconds: 8));
        return res.statusCode == 200;
      } else {
        final uri = Uri.parse('$_apiBase/webdl/controlwebdownload');
        final res = await http.post(
          uri,
          headers: _headers(cleanKey),
          body: jsonEncode({
            'webdownload_id': int.tryParse(id) ?? id,
            'operation': 'delete',
          }),
        ).timeout(const Duration(seconds: 8));
        return res.statusCode == 200;
      }
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the hoster is supported by TorBox
  bool isSupportedHoster(String url) {
    final clean = url.split('?').first.toLowerCase();
    if (clean.endsWith('.mp4') ||
        clean.endsWith('.mkv') ||
        clean.endsWith('.avi') ||
        clean.endsWith('.webm') ||
        clean.endsWith('.ts')) {
      return true;
    }

    final lower = url.toLowerCase();
    if (lower.contains('pixeldrain') ||
        lower.contains('gofile') ||
        lower.contains('buzzheavier') ||
        lower.contains('qiwi') ||
        lower.contains('multiup') ||
        lower.contains('krakenfiles') ||
        lower.contains('mixdrop') ||
        lower.contains('voe.sx') ||
        lower.contains('filemoon') ||
        lower.contains('doodstream') ||
        lower.contains('streamtape') ||
        lower.contains('1fichier') ||
        lower.contains('rapidgator') ||
        lower.contains('mega.nz') ||
        lower.contains('mediafire') ||
        lower.contains('ddownload') ||
        lower.contains('uptobox') ||
        lower.contains('drive.google.com') ||
        lower.contains('googleusercontent.com') ||
        lower.contains('hubcloud') ||
        lower.contains('hubdrive') ||
        lower.contains('driveseed') ||
        lower.contains('drivebot') ||
        lower.contains('fastdl') ||
        lower.contains('fast-dl') ||
        lower.contains('vgmlinks') ||
        lower.contains('vcloud') ||
        lower.contains('turbobit') ||
        lower.contains('katfile') ||
        lower.contains('nitroflare') ||
        lower.contains('fileq') ||
        lower.contains('workers.dev') ||
        lower.contains('archive.org') ||
        lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('vimeo.com') ||
        lower.contains('dailymotion.com')) {
      return true;
    }

    // Check dynamically cached hoster domains
    if (_cachedHosters != null) {
      for (final h in _cachedHosters!) {
        final domains = h['domains'];
        if (domains is List) {
          for (final d in domains) {
            if (lower.contains(d.toString().toLowerCase())) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }
}
