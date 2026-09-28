import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as hp;

void main() async {
  final sites = {
    '67movies': 'https://67movies.st',
    '7movies': 'https://7movies.ac',
    '1flex': 'https://www.1flex.org',
    'atlantic': 'https://atlantic.st',
  };

  for (final entry in sites.entries) {
    try {
      final res = await http.get(Uri.parse(entry.value), headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'});
      print('=== ${entry.key} === (${res.statusCode})');
      final doc = hp.parse(res.body);
      final forms = doc.querySelectorAll('form');
      for (final f in forms) {
        print('  Form action: ${f.attributes["action"]}, method: ${f.attributes["method"]}');
      }
      final inputs = doc.querySelectorAll('input');
      for (final inp in inputs) {
        if (inp.attributes['name'] != null) {
          print('  Input name: ${inp.attributes["name"]} (placeholder: ${inp.attributes["placeholder"]})');
        }
      }
    } catch (e) {
      print('=== ${entry.key} error: $e ===');
    }
  }
}
