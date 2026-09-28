import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as hp;

void main() async {
  print('========================================================');
  print('PART 1: DIAGNOSING FMHY HIGH-RATED AGGREGATORS');
  print('========================================================\n');

  // 1. 67movies
  try {
    print('[1] 67movies (https://67movies.st):');
    final res = await http.get(Uri.parse('https://67movies.st/'), headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'});
    print('  Homepage status: ${res.statusCode}');
    final doc = hp.parse(res.body);
    final scripts = doc.querySelectorAll('script');
    print('  Found ${scripts.length} script tags.');
    final title = doc.querySelector('title')?.text.trim();
    print('  Page Title: "$title"');
  } catch (e) {
    print('  67movies error: $e');
  }

  // 2. Atlantic
  try {
    print('\n[2] Atlantic (https://atlantic.st):');
    final res = await http.get(Uri.parse('https://atlantic.st/'), headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'});
    print('  Homepage status: ${res.statusCode}');
    print('  HTML snippet: ${res.body.replaceAll("\n", " ").substring(0, res.body.length > 200 ? 200 : res.body.length)}');
  } catch (e) {
    print('  Atlantic error: $e');
  }

  // 3. 1Flex / 1Shows
  try {
    print('\n[3] 1Flex (https://www.1flex.org):');
    final res = await http.get(Uri.parse('https://www.1flex.org/'), headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'});
    print('  Homepage status: ${res.statusCode}');
    final doc = hp.parse(res.body);
    print('  Title: "${doc.querySelector('title')?.text.trim()}"');
    for (final s in doc.querySelectorAll('script[src]')) {
      print('  Script: ${s.attributes["src"]}');
    }
  } catch (e) {
    print('  1Flex error: $e');
  }

  // 4. 7Movies
  try {
    print('\n[4] 7Movies (https://7movies.ac):');
    final res = await http.get(Uri.parse('https://7movies.ac/'), headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'});
    print('  Homepage status: ${res.statusCode}');
    final doc = hp.parse(res.body);
    print('  Title: "${doc.querySelector('title')?.text.trim()}"');
  } catch (e) {
    print('  7Movies error: $e');
  }
}
