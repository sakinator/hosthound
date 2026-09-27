import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final candidates = [
    'https://bolly4u.day',
    'https://cinevood.world',
    'https://dramaday.me',
    'https://allmovieshub.ink',
    'https://allmovieshub.in',
    'https://skymovieshd.cfd',
    'https://skymovieshd.ink',
    'https://7starhd.city',
    'https://7starhd.run',
    'https://hindilinks4u.to',
    'https://filmyfly.com',
    'https://crazy4tv.com',
    'https://topmovies.vip',
    'https://topmovies.lat',
    'https://anitaku.to',
    'https://anitaku.so',
    'https://animefire.plus',
    'https://kisscenter.net'
  ];

  for (final url in candidates) {
    try {
      final uri = Uri.parse(url);
      final res = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      }).timeout(const Duration(seconds: 4));
      print('$url -> ${res.statusCode} (Length: ${res.body.length}, Location: ${res.headers["location"]})');
    } catch (e) {
      print('$url -> FAILED: $e');
    }
  }
}
