import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Prowlarr-style Captcha & Cloudflare Challenge Proxy Resolver.
///
/// Features:
/// 1. Automated Captcha & Cloudflare Turnstile / IUAM Detection (403, 503, "Just a moment...").
/// 2. Prowlarr / Jackett standard FlareSolverr Proxy Solver bridge (e.g., http://localhost:8191/v1).
/// 3. Clearance Cookie Store: Caches solved `cf_clearance` & session cookies per host domain
///    so captchas are only solved once, allowing subsequent requests to run at instant zero-wait speeds.
/// 4. Prowlarr Origin-Fresh Headers to prevent stale/broken CDN cache hits.
class ProxyResolverService {
  static final ProxyResolverService instance = ProxyResolverService._();

  ProxyResolverService._();

  // In-memory clearance cookie store: domain -> 'cookie1=val; cookie2=val'
  final Map<String, _ClearanceSession> _clearanceStore = {};

  /// Prowlarr-standard cache bypass headers
  static Map<String, String> get originFreshHeaders => {
    'Cache-Control': 'no-cache, no-store, max-age=0, must-revalidate',
    'Pragma': 'no-cache',
    'Expires': '0',
  };

  /// Fetches a URL with automatic Captcha detection and Prowlarr FlareSolverr solving.
  Future<http.Response> fetch(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
    bool bypassCache = true,
  }) async {
    final cfg = AddonConfig.instance;
    final host = uri.host.toLowerCase();

    // Check if we have an active, non-expired clearance cookie from a previous solve
    final clearance = _clearanceStore[host];
    final clearanceHeaders = <String, String>{};
    if (clearance != null && !clearance.isExpired) {
      clearanceHeaders['Cookie'] = clearance.cookieString;
      if (clearance.userAgent != null && clearance.userAgent!.isNotEmpty) {
        clearanceHeaders['User-Agent'] = clearance.userAgent!;
      }
    }

    final mergedHeaders = <String, String>{
      'User-Agent': clearance?.userAgent ??
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    if (bypassCache && cfg.enableCacheBypass) {
      mergedHeaders.addAll(originFreshHeaders);
    }
    mergedHeaders.addAll(clearanceHeaders);
    if (headers != null) {
      mergedHeaders.addAll(headers);
    }

    // 1. Direct fetch
    try {
      final res = await http.get(uri, headers: mergedHeaders).timeout(timeout);
      if (!isCaptchaChallenge(res.body, res.statusCode)) {
        return res;
      }
      print('[ProxyResolver] Captcha / Cloudflare challenge detected for ${uri.host} (HTTP ${res.statusCode}).');
    } catch (e) {
      print('[ProxyResolver] Direct fetch failed for $uri ($e).');
    }

    // 2. Fallback to FlareSolverr Captcha Proxy Solver if configured (like Prowlarr)
    final solverUrl = cfg.proxyResolverUrl.trim();
    if (solverUrl.isNotEmpty) {
      print('[ProxyResolver] Dispatching captcha to FlareSolverr at $solverUrl...');
      final solvedRes = await _solveViaFlareSolverr(uri, solverUrl, timeout);
      if (solvedRes != null) {
        return solvedRes;
      }
    }

    // 3. Fallback request
    return http.get(uri, headers: mergedHeaders).timeout(timeout);
  }

  /// Detects Cloudflare IUAM, Turnstile, hCaptcha, DDoS-GUARD, and 403/503 security blocks.
  static bool isCaptchaChallenge(String body, int statusCode) {
    if (statusCode == 403 || statusCode == 503) {
      return true;
    }
    if (body.isEmpty) return false;
    final lower = body.toLowerCase();
    return lower.contains('just a moment...') ||
        lower.contains('attention required! | cloudflare') ||
        lower.contains('cf-chl-widget') ||
        lower.contains('challenge-platform') ||
        lower.contains('cf-browser-verification') ||
        lower.contains('ddos-guard') ||
        lower.contains('hcaptcha.com') ||
        lower.contains('google.com/recaptcha');
  }

  /// Solves captcha challenge using FlareSolverr v1 API and stores clearance cookies.
  Future<http.Response?> _solveViaFlareSolverr(
    Uri targetUri,
    String flaresolverrUrl,
    Duration timeout,
  ) async {
    try {
      final endpoint = flaresolverrUrl.endsWith('/v1') ? flaresolverrUrl : '$flaresolverrUrl/v1';
      final payload = jsonEncode({
        'cmd': 'request.get',
        'url': targetUri.toString(),
        'maxTimeout': (timeout.inMilliseconds * 2).clamp(10000, 45000),
      });

      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      ).timeout(const Duration(seconds: 40));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['status'] == 'ok') {
          final solution = data['solution'] as Map<String, dynamic>?;
          if (solution != null) {
            final htmlBody = solution['response']?.toString() ?? '';
            final status = solution['status'] is int ? solution['status'] as int : 200;
            final userAgent = solution['userAgent']?.toString();

            // Extract & save clearance cookies
            final cookiesList = solution['cookies'] as List<dynamic>?;
            if (cookiesList != null && cookiesList.isNotEmpty) {
              final cookiePairs = <String>[];
              for (final c in cookiesList) {
                if (c is Map && c['name'] != null && c['value'] != null) {
                  cookiePairs.add('${c['name']}=${c['value']}');
                }
              }
              if (cookiePairs.isNotEmpty) {
                final domain = targetUri.host.toLowerCase();
                _clearanceStore[domain] = _ClearanceSession(
                  cookieString: cookiePairs.join('; '),
                  userAgent: userAgent,
                  expiresAt: DateTime.now().add(const Duration(minutes: 50)),
                );
                print('[ProxyResolver] Saved clearance cookies for $domain from FlareSolverr.');
              }
            }

            return http.Response(
              htmlBody,
              status,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
        }
      }
    } catch (e) {
      print('[ProxyResolver] FlareSolverr solve failed: $e');
    }
    return null;
  }
}

class _ClearanceSession {
  final String cookieString;
  final String? userAgent;
  final DateTime expiresAt;

  _ClearanceSession({
    required this.cookieString,
    this.userAgent,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
