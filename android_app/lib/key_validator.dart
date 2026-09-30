import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'torbox_service.dart';

class KeyValidationResult {
  final bool valid;
  final String message;
  final Map<String, dynamic>? details;

  KeyValidationResult({
    required this.valid,
    required this.message,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        'valid': valid,
        'message': message,
        if (details != null) 'details': details,
      };
}

class KeyValidator {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  /// Validates an API key for any supported integration.
  static Future<KeyValidationResult> validate(String service, String rawKey) async {
    final key = rawKey.trim();
    if (key.isEmpty) {
      return KeyValidationResult(
        valid: true,
        message: 'Empty key — using built-in public zero-key fallback.',
      );
    }

    switch (service.toLowerCase()) {
      case 'torbox':
        return _validateTorbox(key);
      case 'omdb':
        return _validateOmdb(key);
      case 'fanart':
        return _validateFanart(key);
      case 'tvdb':
        return _validateTvdb(key);
      case 'tmdb':
        return _validateTmdb(key);
      case 'dtdd':
        return _validateDtdd(key);
      default:
        return KeyValidationResult(
          valid: false,
          message: 'Unknown service: $service',
        );
    }
  }

  static Future<KeyValidationResult> _validateTorbox(String key) async {
    try {
      final acc = await TorboxService.instance.validateAccount(key);
      if (acc['valid'] == true) {
        final plan = acc['plan'] ?? 'Active';
        final email = acc['email'] ?? '';
        return KeyValidationResult(
          valid: true,
          message: 'Valid TorBox account ($plan${email.isNotEmpty ? ' - $email' : ''})',
          details: acc,
        );
      } else {
        return KeyValidationResult(
          valid: false,
          message: acc['message'] ?? 'Invalid TorBox API Key',
        );
      }
    } catch (e) {
      return KeyValidationResult(
        valid: false,
        message: 'TorBox verification error: $e',
      );
    }
  }

  static Future<KeyValidationResult> _validateOmdb(String key) async {
    try {
      final uri = Uri.parse('https://www.omdbapi.com/?i=tt1375666&apikey=$key');
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await utf8.decodeStream(res);
      final json = jsonDecode(body);
      if (json is Map && json['Response'] == 'True') {
        return KeyValidationResult(
          valid: true,
          message: 'Valid OMDb API Key (Connected successfully)',
        );
      } else {
        final err = json is Map ? json['Error'] : 'Invalid OMDb Key';
        return KeyValidationResult(
          valid: false,
          message: err?.toString() ?? 'Invalid OMDb Key',
        );
      }
    } catch (e) {
      return KeyValidationResult(
        valid: false,
        message: 'Could not connect to OMDb: $e',
      );
    }
  }

  static Future<KeyValidationResult> _validateFanart(String key) async {
    try {
      // Test movie ID 27205 (Inception)
      final uri = Uri.parse('https://webservice.fanart.tv/v3/movies/27205?api_key=$key');
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>();
      if (res.statusCode == 200) {
        return KeyValidationResult(
          valid: true,
          message: 'Valid Fanart.tv API Key (ClearLogos & 4K artwork ready)',
        );
      } else if (res.statusCode == 401) {
        return KeyValidationResult(
          valid: false,
          message: 'Invalid Fanart.tv API Key (HTTP 401 Unauthorized)',
        );
      } else {
        return KeyValidationResult(
          valid: false,
          message: 'Fanart.tv returned HTTP ${res.statusCode}',
        );
      }
    } catch (e) {
      return KeyValidationResult(
        valid: false,
        message: 'Could not connect to Fanart.tv: $e',
      );
    }
  }

  static Future<KeyValidationResult> _validateTvdb(String key) async {
    try {
      final uri = Uri.parse('https://api4.thetvdb.com/v4/login');
      final req = await _client.postUrl(uri).timeout(const Duration(seconds: 4));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'apikey': key}));
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await utf8.decodeStream(res);
      final json = jsonDecode(body);
      if (res.statusCode == 200 && json is Map && json['status'] == 'success') {
        return KeyValidationResult(
          valid: true,
          message: 'Valid TheTVDB v4 API Key (Episode mappings ready)',
        );
      } else {
        final msg = json is Map ? json['message'] : 'Invalid TheTVDB API key';
        return KeyValidationResult(
          valid: false,
          message: msg?.toString() ?? 'Invalid TheTVDB Key',
        );
      }
    } catch (e) {
      return KeyValidationResult(
        valid: false,
        message: 'Could not connect to TheTVDB: $e',
      );
    }
  }

  static Future<KeyValidationResult> _validateTmdb(String key) async {
    try {
      final uri = Uri.parse('https://api.themoviedb.org/3/authentication?api_key=$key');
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await utf8.decodeStream(res);
      final json = jsonDecode(body);
      if (res.statusCode == 200 && json is Map && json['success'] == true) {
        return KeyValidationResult(
          valid: true,
          message: 'Valid TMDB API Key',
        );
      } else {
        final msg = json is Map ? json['status_message'] : 'Invalid TMDB API key';
        return KeyValidationResult(
          valid: false,
          message: msg?.toString() ?? 'Invalid TMDB Key',
        );
      }
    } catch (e) {
      return KeyValidationResult(
        valid: false,
        message: 'Could not connect to TMDB: $e',
      );
    }
  }

  static Future<KeyValidationResult> _validateDtdd(String key) async {
    try {
      final uri = Uri.parse('https://api.doesthedogdie.com/dddsearch?imdb=tt1375666');
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 4));
      req.headers.set('Accept', 'application/json');
      req.headers.set('X-API-KEY', key);
      req.headers.set('User-Agent', 'Hostreamio/1.0');
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        return KeyValidationResult(
          valid: true,
          message: 'Valid DoesTheDogDie API Key',
        );
      } else {
        return KeyValidationResult(
          valid: false,
          message: 'Invalid DoesTheDogDie API Key (HTTP ${res.statusCode})',
        );
      }
    } catch (e) {
      return KeyValidationResult(
        valid: false,
        message: 'Could not connect to DoesTheDogDie: $e',
      );
    }
  }
}
