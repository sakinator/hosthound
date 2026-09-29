import 'dart:io';

void main() async {
  final sitesDir = Directory('lib/upstream/services/scraper/sites');
  if (!await sitesDir.exists()) {
    print('Error: sites directory not found at ${sitesDir.path}');
    exit(1);
  }

  final files = await sitesDir.list().where((e) => e is File && e.path.endsWith('.dart')).cast<File>().toList();
  files.sort((a, b) => a.path.compareTo(b.path));

  final scrapers = <Map<String, String>>[];
  final classRegex = RegExp(r'class\s+(\w+Scraper)\s+extends\s+StreamScraper');

  for (final file in files) {
    final fileName = file.uri.pathSegments.last;
    final content = await file.readAsString();
    final match = classRegex.firstMatch(content);
    if (match != null) {
      final className = match.group(1)!;
      scrapers.add({
        'file': fileName,
        'class': className,
      });
    }
  }

  print('Discovered ${scrapers.length} stream and torrent scrapers.');

  final buffer = StringBuffer();
  buffer.writeln('// AUTO-GENERATED SCRAPER REGISTRY - DO NOT EDIT MANUALLY');
  buffer.writeln('// Generated at: ${DateTime.now().toIso8601String()}');
  buffer.writeln('// Run "dart run tool/generate_registry.dart" or "pipeline/update.ps1" to regenerate.\n');
  buffer.writeln("import 'upstream/services/scraper/stream_scraper.dart';");

  for (final s in scrapers) {
    buffer.writeln("import 'upstream/services/scraper/sites/${s['file']}';");
  }

  buffer.writeln('\nclass ScraperRegistry {');
  buffer.writeln('  static List<StreamScraper> getAllScrapers() => [');
  for (final s in scrapers) {
    buffer.writeln("    ${s['class']}(),");
  }
  buffer.writeln('  ];');
  buffer.writeln('}');

  final outFile = File('lib/scraper_registry.dart');
  await outFile.writeAsString(buffer.toString());
  print('Successfully wrote ${outFile.path} with ${scrapers.length} scrapers!');
}
