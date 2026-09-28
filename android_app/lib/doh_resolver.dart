import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// DNS-over-HTTPS (DoH) Resolver with In-Memory Cache and System DNS Fallback.
///
/// Unblocks ISP-blocked streaming domains (e.g. Airtel, Jio, ACT in India, or European ISPs)
/// by querying Cloudflare (1.1.1.1) and Google (8.8.8.8) DoH over encrypted HTTPS.
class DohResolver {
  static final DohResolver instance = DohResolver._();

  DohResolver._();

  // In-memory DNS cache: host -> _DnsEntry
  final Map<String, _DnsEntry> _cache = {};

  // Direct HTTP client for DoH queries (avoids recursion and ignores cert errors)
  static final HttpClient _dohHttpClient = HttpClient()
    ..badCertificateCallback = ((cert, host, port) => true)
    ..connectionTimeout = const Duration(seconds: 4);

  // Common ISP blocked/redirect sinkhole IPs
  static const Set<String> _sinkholeIps = {
    '0.0.0.0',
    '127.0.0.1',
    '255.255.255.255',
    '103.224.212.222', // Bodis / Trellian ISP parking
    '103.224.182.245',
    '192.168.1.1',
  };

  /// Resolves [host] into a list of [InternetAddress].
  ///
  /// Order of resolution:
  /// 1. IP literal check (if host is already IPv4/IPv6, returns immediately)
  /// 2. In-memory cache check (TTL: 15-30 mins)
  /// 3. System DNS lookup (with 1.5s timeout)
  /// 4. Cloudflare DoH (1.1.1.1)
  /// 5. Google DoH (8.8.8.8)
  Future<List<InternetAddress>> resolve(String host) async {
    final cleanHost = host.trim().toLowerCase();

    // 1. Literal IP check
    final literal = InternetAddress.tryParse(cleanHost);
    if (literal != null) {
      return [literal];
    }

    // 2. In-memory cache check
    final now = DateTime.now();
    final cached = _cache[cleanHost];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.addresses;
    }

    // 3. Try System DNS first with short timeout
    try {
      final systemResults = await InternetAddress.lookup(cleanHost)
          .timeout(const Duration(milliseconds: 1500));
      
      final validResults = systemResults.where((addr) => !_sinkholeIps.contains(addr.address)).toList();
      if (validResults.isNotEmpty) {
        _cache[cleanHost] = _DnsEntry(
          addresses: validResults,
          expiresAt: now.add(const Duration(minutes: 15)),
        );
        return validResults;
      }
    } catch (_) {
      // System DNS failed or timed out; proceed to DoH fallback
    }

    // 4. Cloudflare DoH Fallback (1.1.1.1)
    try {
      final cfAddrs = await _queryCloudflareDoh(cleanHost);
      if (cfAddrs.isNotEmpty) {
        _cache[cleanHost] = _DnsEntry(
          addresses: cfAddrs,
          expiresAt: now.add(const Duration(minutes: 20)),
        );
        return cfAddrs;
      }
    } catch (_) {}

    // 5. Google DoH Fallback (8.8.8.8)
    try {
      final gAddrs = await _queryGoogleDoh(cleanHost);
      if (gAddrs.isNotEmpty) {
        _cache[cleanHost] = _DnsEntry(
          addresses: gAddrs,
          expiresAt: now.add(const Duration(minutes: 20)),
        );
        return gAddrs;
      }
    } catch (_) {}

    // If all fail, perform standard lookup as last ditch
    return await InternetAddress.lookup(cleanHost);
  }

  /// Queries Cloudflare DoH endpoint directly by IP to prevent circular DNS calls.
  Future<List<InternetAddress>> _queryCloudflareDoh(String host) async {
    final uri = Uri.parse('https://1.1.1.1/dns-query?name=${Uri.encodeComponent(host)}&type=A');
    final req = await _dohHttpClient.getUrl(uri);
    req.headers.set('accept', 'application/dns-json');
    req.headers.set('host', 'cloudflare-dns.com');
    final res = await req.close().timeout(const Duration(seconds: 4));

    if (res.statusCode == HttpStatus.ok) {
      final body = await res.transform(utf8.decoder).join();
      return _parseDnsJson(body);
    }
    return [];
  }

  /// Queries Google DoH endpoint directly by IP to prevent circular DNS calls.
  Future<List<InternetAddress>> _queryGoogleDoh(String host) async {
    final uri = Uri.parse('https://8.8.8.8/resolve?name=${Uri.encodeComponent(host)}&type=A');
    final req = await _dohHttpClient.getUrl(uri);
    req.headers.set('accept', 'application/dns-json');
    req.headers.set('host', 'dns.google');
    final res = await req.close().timeout(const Duration(seconds: 4));

    if (res.statusCode == HttpStatus.ok) {
      final body = await res.transform(utf8.decoder).join();
      return _parseDnsJson(body);
    }
    return [];
  }

  List<InternetAddress> _parseDnsJson(String jsonStr) {
    final results = <InternetAddress>[];
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final answers = map['Answer'] as List<dynamic>?;
      if (answers != null) {
        for (final ans in answers) {
          if (ans is Map && ans['type'] == 1) { // Type 1 = A record (IPv4)
            final ipStr = ans['data']?.toString().trim();
            if (ipStr != null && !_sinkholeIps.contains(ipStr)) {
              final addr = InternetAddress.tryParse(ipStr);
              if (addr != null) {
                results.add(addr);
              }
            }
          }
        }
      }
    } catch (_) {}
    return results;
  }

  /// Pre-warms DNS cache for critical domains.
  Future<void> prewarm(List<String> domains) async {
    for (final domain in domains) {
      try {
        await resolve(domain);
      } catch (_) {}
    }
  }
}

class _DnsEntry {
  final List<InternetAddress> addresses;
  final DateTime expiresAt;

  _DnsEntry({required this.addresses, required this.expiresAt});
}

/// Global HttpOverrides that routes all socket connections through [DohResolver].
class HostreamioHttpOverrides extends HttpOverrides {
  static const Set<String> _officialApiDomains = {
    'themoviedb.org',
    'torbox.app',
    'omdbapi.com',
    'thetvdb.com',
    'fanart.tv',
    'github.com',
  };

  static bool _isOfficialApi(String host) {
    final lower = host.toLowerCase();
    return _officialApiDomains.any((d) => lower == d || lower.endsWith('.$d'));
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) {
      if (_isOfficialApi(host)) {
        final subject = cert.subject.toLowerCase();
        return subject.contains(host.toLowerCase());
      }
      return true; // Relaxed for unofficial scrapers and video hosts
    };
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
      final addresses = await DohResolver.instance.resolve(uri.host);
      final target = addresses.isNotEmpty ? addresses.first : (await InternetAddress.lookup(uri.host)).first;
      if (uri.isScheme('https')) {
        return SecureSocket.startConnect(
          target,
          uri.port,
          onBadCertificate: (cert) {
            if (_isOfficialApi(uri.host)) {
              final subject = cert.subject.toLowerCase();
              return subject.contains(uri.host.toLowerCase());
            }
            return true;
          },
        );
      } else {
        return Socket.startConnect(target, uri.port);
      }
    };
    return client;
  }
}

typedef HosthoundHttpOverrides = HostreamioHttpOverrides;
typedef MegascraperHttpOverrides = HostreamioHttpOverrides;
typedef UnboundHttpOverrides = HostreamioHttpOverrides;
