import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as hp;

void main() async {
  final cleanTitle = 'Queen of Tears';
  final ep = 1;
  final epStr = ep.toString().padLeft(2, '0');

  final res = await http.get(Uri.parse('https://dramaday.me/?s=${Uri.encodeComponent(cleanTitle)}'), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  });
  final doc = hp.parse(res.body);
  String? seriesLink;
  for (final a in doc.querySelectorAll('h2 a, h3 a')) {
    final t = a.text.trim().toLowerCase();
    if (t.contains(cleanTitle.toLowerCase()) && !t.contains('ost')) {
      seriesLink = a.attributes['href'];
      print('Found drama post: ${a.text.trim()} -> $seriesLink');
      break;
    }
  }

  if (seriesLink != null) {
    final pRes = await http.get(Uri.parse(seriesLink), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    });
    final pDoc = hp.parse(pRes.body);
    for (final p in pDoc.querySelectorAll('p, tr, div')) {
      final text = p.text.trim();
      if (text.startsWith('$epStr ') || text.startsWith('Episode $ep') || text.startsWith('EP $ep')) {
        print('Matched episode paragraph: $text');
        for (final a in p.querySelectorAll('a[href]')) {
          final href = a.attributes['href'] ?? '';
          final aText = a.text.trim();
          if (href.contains('dddrive') || href.contains('pixeldrain') || href.contains('mega') || href.contains('kraken') || href.contains('gofile') || href.contains('1fichier') || href.contains('ouo.io')) {
            print('  Yielding: "$aText" -> $href');
          }
        }
        break;
      }
    }
  }
}
