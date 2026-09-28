import 'package:http/http.dart' as http;

void main() async {
  final res = await http.get(Uri.parse('https://bolly4u.day/search.html?q=jawan'), headers: {'User-Agent': 'Mozilla/5.0'});
  print(res.body.substring(0, res.body.length > 500 ? 500 : res.body.length));
}
