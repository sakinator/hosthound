import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/bolly4u.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/bollyflix.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/hdhub4u.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/hindmoviez.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/moviesdrive.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/moviesmod.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/playdesi.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/vegamovies.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/uhdmovies.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/fourkhdhub.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/yomovies.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/vadapav.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/multimovies.dart';

import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/dramaday.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/dramacool.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/kissasian.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/kisskh.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/hianime.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/animepahe.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/gogoanime.dart';
import 'package:playtorrio_nuvio_addon/upstream/services/scraper/sites/toonstream.dart';

void main() async {
  print('===============================================================');
  print('TESTING CURRENT HINDI / BOLLYWOOD SCRAPERS');
  print('===============================================================');

  final hindiScrapers = [
    Bolly4uScraper(),
    MoviesDriveScraper(),
    UHDMoviesScraper(),
    MoviesModScraper(),
    FourKHDHubScraper(),
    BollyflixScraper(),
    HDHub4uScraper(),
    VegamoviesScraper(),
    VadapavScraper(),
    HindMoviezScraper(),
    PlayDesiScraper(),
    YoMoviesScraper(),
    MultiMoviesScraper(),
  ];

  for (final s in hindiScrapers) {
    try {
      final count = await s.scrapeStream(type: 'movie', title: 'Jawan', year: 2023, imdbId: 'tt15354916')
          .take(5)
          .length
          .timeout(const Duration(seconds: 8));
      print('  ✅ [${s.providerName}] Found: $count stream(s)');
    } catch (e) {
      print('  ❌ [${s.providerName}] Error: $e');
    }
  }

  print('\n===============================================================');
  print('TESTING CURRENT ASIAN / ANIME / KDRAMA SCRAPERS');
  print('===============================================================');

  final asianScrapers = [
    DramaDayScraper(),
    DramacoolScraper(),
    KissAsianScraper(),
    KissKhScraper(),
    HiAnimeScraper(),
    AnimePaheScraper(),
    GogoanimeScraper(),
    ToonStreamScraper(),
  ];

  for (final s in asianScrapers) {
    try {
      final count = await s.scrapeStream(type: 'series', title: 'Queen of Tears', season: 1, episode: 1)
          .take(5)
          .length
          .timeout(const Duration(seconds: 8));
      print('  ✅ [${s.providerName}] Found: $count stream(s)');
    } catch (e) {
      print('  ❌ [${s.providerName}] Error: $e');
    }
  }
}
