import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'omdb_service.dart';
import 'fanart_service.dart';
import 'tvdb_service.dart';
import 'badge_service.dart';

class MediaMetadata {
  final String id;
  final String type; // 'movie' or 'series'
  final String title;
  final int? year;
  final int? season;
  final int? episode;
  final String? imdbId;
  final int? tmdbId;
  final int? tvdbId;

  // Enriched details
  final String? episodeTitle;
  final int? absoluteEpisode;
  final String? description;
  final List<String>? genres;
  final String? poster;
  final String? background;
  final String? logo;
  final OmdbMetadata? omdb;
  final ArtworkMetadata? artwork;
  final String? ottPlatform;

  MediaMetadata({
    required this.id,
    required this.type,
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.imdbId,
    this.tmdbId,
    this.tvdbId,
    this.episodeTitle,
    this.absoluteEpisode,
    this.description,
    this.genres,
    this.poster,
    this.background,
    this.logo,
    this.omdb,
    this.artwork,
    this.ottPlatform,
  });

  @override
  String toString() =>
      'MediaMetadata($type, "$title", year: $year, S${season}E${episode}, imdb: $imdbId, tmdb: $tmdbId, ep: "$episodeTitle", abs: $absoluteEpisode)';
}

class MetadataService {
  static String get _apiKey => AddonConfig.instance.tmdbApiKey;

  static const _tmdbDirect = 'https://api.themoviedb.org/3';
  static const _tmdbProxy = 'https://db.speedracelight.com/3';
  static const _cinemeta = 'https://v3-cinemeta.strem.io/meta';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  static final Map<String, MediaMetadata> _cache = {};

  /// Resolves an incoming Stremio / Nuvio media ID into complete metadata.
  /// Supports:
  /// - `tt1375666` (movie)
  /// - `tt0944947:1:1` (series: S01E01)
  /// - `tmdb:27205`
  /// - `tmdb:1399:1:1`
  static Future<MediaMetadata?> resolve({
    required String type, // 'movie' or 'series'
    required String rawId,
  }) async {
    final cacheKey = '$type|$rawId';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    String baseId = rawId;
    int? season;
    int? episode;

    if (rawId.contains(':')) {
      final parts = rawId.split(':');
      if (parts[0] == 'tmdb' && parts.length >= 4) {
        baseId = 'tmdb:${parts[1]}';
        season = int.tryParse(parts[2]);
        episode = int.tryParse(parts[3]);
      } else if (parts[0] == 'tmdb' && parts.length == 2) {
        baseId = rawId;
      } else if (parts.length >= 3) {
        baseId = parts[0];
        season = int.tryParse(parts[1]);
        episode = int.tryParse(parts[2]);
      } else if (parts.length == 2 && parts[0].startsWith('tt')) {
        baseId = parts[0];
        season = int.tryParse(parts[1]);
      }
    }

    String? imdbId;
    int? tmdbId;
    String? title;
    int? year;
    String? description;
    List<String>? genres;
    String? poster;
    String? background;
    String? logo;

    String? cinemetaRating;
    final isTv = (type == 'series' || type == 'tv');
    final cinemetaType = isTv ? 'series' : 'movie';
    final tmdbType = isTv ? 'tv' : 'movie';

    if (baseId.startsWith('tt')) {
      imdbId = baseId;

      // 1. Try Cinemeta (Fast, reliable, zero-key fallback for Stremio/Nuvio)
      try {
        final uri = Uri.parse('$_cinemeta/$cinemetaType/$imdbId.json');
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final meta = data['meta'];
          if (meta != null) {
            title = meta['name']?.toString();
            description = meta['description']?.toString();
            poster = meta['poster']?.toString();
            background = meta['background']?.toString();
            logo = meta['logo']?.toString();
            cinemetaRating = meta['imdbRating']?.toString();
            if (meta['genres'] is List) {
              genres = (meta['genres'] as List).map((e) => e.toString()).toList();
            }
            final yStr = meta['year']?.toString();
            if (yStr != null) {
              year = int.tryParse(yStr.split('–')[0].split('-')[0].trim());
            }
          }
        }
      } catch (_) {}

      // 2. Query TMDB Find to get TMDB ID and confirm title/year
      try {
        final uri = Uri.parse('$_tmdbDirect/find/$imdbId?api_key=$_apiKey&external_source=imdb_id');
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final results = isTv ? (data['tv_results'] as List?) : (data['movie_results'] as List?);
          if (results != null && results.isNotEmpty) {
            final first = results.first;
            tmdbId = first['id'] as int?;
            title ??= (first['name'] ?? first['title'])?.toString();
            description ??= first['overview']?.toString();
            final dateStr = (first['first_air_date'] ?? first['release_date'])?.toString();
            if (year == null && dateStr != null && dateStr.length >= 4) {
              year = int.tryParse(dateStr.substring(0, 4));
            }
          }
        }
      } catch (_) {
        // Fallback to TMDB proxy
        try {
          final uri = Uri.parse('$_tmdbProxy/find/$imdbId?external_source=imdb_id');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = isTv ? (data['tv_results'] as List?) : (data['movie_results'] as List?);
            if (results != null && results.isNotEmpty) {
              final first = results.first;
              tmdbId = first['id'] as int?;
              title ??= (first['name'] ?? first['title'])?.toString();
              description ??= first['overview']?.toString();
            }
          }
        } catch (_) {}
      }
    } else if (baseId.startsWith('tmdb:')) {
      final numericStr = baseId.replaceFirst('tmdb:', '');
      tmdbId = int.tryParse(numericStr);
      if (tmdbId != null) {
        try {
          final uri = Uri.parse('$_tmdbDirect/$tmdbType/$tmdbId?api_key=$_apiKey');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            title = (data['name'] ?? data['title'])?.toString();
            imdbId = data['imdb_id']?.toString();
            description = data['overview']?.toString();
            final dateStr = (data['first_air_date'] ?? data['release_date'])?.toString();
            if (dateStr != null && dateStr.length >= 4) {
              year = int.tryParse(dateStr.substring(0, 4));
            }
          }
        } catch (_) {}
      }
    }

    if (title == null || title.isEmpty) {
      return null;
    }

    // ── Concurrently Resolve APIs 4 (TVDB), 5 (OMDb), & 6 (Fanart.tv) ──
    EpisodeInfo? epInfo;
    OmdbMetadata? omdbData;
    ArtworkMetadata? artworkData;
    String? ottPlatform;

    try {
      final futures = <Future<void>>[];

      // API 5: OMDb & IMDb Ratings
      futures.add(
        OmdbService.instance.getMetadata(imdbId, title: title, year: year).then((val) {
          omdbData = val;
        }),
      );

      // API 6: Fanart.tv ClearLogos & 4K backdrops
      futures.add(
        FanartService.instance
            .getArtwork(type: isTv ? 'series' : 'movie', imdbId: imdbId, tmdbId: tmdbId)
            .then((val) {
          artworkData = val;
        }),
      );

      // API 4: TVDB / Episode Mapping for series
      if (isTv && season != null && episode != null && imdbId != null) {
        futures.add(
          TvdbService.instance
              .getEpisodeInfo(imdbId: imdbId, season: season, episode: episode, title: title)
              .then((val) {
            epInfo = val;
          }),
        );
      }

      // API 7: TVMaze lookup for series OTT Platform / Network (100% free, 0-key)
      if (isTv && imdbId != null) {
        futures.add(
          http.get(Uri.parse('https://api.tvmaze.com/lookup/shows?imdb=$imdbId'), headers: _headers)
              .timeout(const Duration(seconds: 3))
              .then((res) {
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              final webChannel = data['webChannel']?['name']?.toString();
              final network = data['network']?['name']?.toString();
              final detected = BadgeService.normalizeOttPlatform(webChannel ?? network);
              if (detected != null) {
                ottPlatform ??= detected;
              }
            }
          }).catchError((_) {}),
        );
      }

      // API 8: TMDB Watch Providers (Movies & Series - India & Global OTT)
      if (tmdbId != null) {
        futures.add(
          http.get(Uri.parse('$_tmdbDirect/$tmdbType/$tmdbId/watch/providers?api_key=$_apiKey'), headers: _headers)
              .timeout(const Duration(seconds: 3))
              .then((res) {
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              final results = data['results'] as Map<String, dynamic>?;
              if (results != null) {
                for (final country in ['IN', 'US', 'GB']) {
                  final cData = results[country] as Map<String, dynamic>?;
                  final flatrate = cData?['flatrate'] as List?;
                  if (flatrate != null && flatrate.isNotEmpty) {
                    for (final item in flatrate) {
                      final pName = item['provider_name']?.toString();
                      final detected = BadgeService.normalizeOttPlatform(pName);
                      if (detected != null) {
                        ottPlatform ??= detected;
                        break;
                      }
                    }
                  }
                  if (ottPlatform != null) break;
                }
              }
            }
          }).catchError((_) {}),
        );
      }

      await Future.wait(futures).timeout(const Duration(milliseconds: 3500));
    } catch (_) {}

    // Fallback: If OMDb was disabled, unreachable, or has no key, use zero-key Cinemeta IMDb rating
    if (omdbData == null && cinemetaRating != null && cinemetaRating.isNotEmpty) {
      omdbData = OmdbMetadata(
        imdbId: imdbId,
        title: title,
        year: year?.toString(),
        imdbRating: cinemetaRating,
      );
    }

    // Prefer Fanart ClearLogo and background if available; fallback to Cinemeta/Metahub (100% zero-key)
    final finalLogo = artworkData?.logo ?? logo ?? (imdbId != null ? 'https://images.metahub.space/logo/medium/$imdbId/img' : null);
    final finalBackground = artworkData?.background ?? background ?? (imdbId != null ? 'https://images.metahub.space/background/medium/$imdbId/img' : null);
    final finalPoster = artworkData?.poster ?? poster ?? (imdbId != null ? 'https://images.metahub.space/poster/medium/$imdbId/img' : null);

    final result = MediaMetadata(
      id: rawId,
      type: isTv ? 'series' : 'movie',
      title: title,
      year: year,
      season: season,
      episode: episode,
      imdbId: imdbId,
      tmdbId: tmdbId,
      episodeTitle: epInfo?.title,
      absoluteEpisode: epInfo?.absoluteEpisode,
      description: description ?? omdbData?.plot,
      genres: genres,
      poster: finalPoster,
      background: finalBackground,
      logo: finalLogo,
      omdb: omdbData,
      artwork: artworkData,
      ottPlatform: ottPlatform,
    );

    _cache[cacheKey] = result;
    return result;
  }

  /// Searches movies or series by text query using Cinemeta (and TMDB fallback).
  static Future<List<Map<String, dynamic>>> search({
    required String query,
    String type = 'movie',
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final cinemetaType = (type == 'series' || type == 'tv') ? 'series' : 'movie';
    final results = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    // 1. Cinemeta Catalog Search (zero-key, instant)
    try {
      final uri = Uri.parse('$_cinemeta/$cinemetaType/top/search=${Uri.encodeComponent(cleanQuery)}.json');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final metas = data['metas'] as List?;
        if (metas != null) {
          for (final m in metas) {
            final id = m['id']?.toString() ?? '';
            if (id.isNotEmpty && seenIds.add(id)) {
              results.add({
                'id': id,
                'name': m['name']?.toString() ?? '',
                'type': m['type']?.toString() ?? type,
                'year': m['releaseInfo']?.toString() ?? m['year']?.toString() ?? '',
                'poster': m['poster']?.toString() ?? 'https://images.metahub.space/poster/medium/$id/img',
                'description': m['description']?.toString() ?? '',
              });
            }
          }
        }
      }
    } catch (_) {}

    // 2. TMDB Search (if results are low or user provided custom key)
    if (results.length < 5) {
      final tmdbType = (type == 'series' || type == 'tv') ? 'tv' : 'movie';
      try {
        final uri = Uri.parse('$_tmdbDirect/search/$tmdbType?api_key=$_apiKey&query=${Uri.encodeComponent(cleanQuery)}');
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final list = data['results'] as List?;
          if (list != null) {
            for (final item in list) {
              final tmdbId = item['id'];
              final id = 'tmdb:$tmdbId';
              if (tmdbId != null && seenIds.add(id)) {
                final title = (item['title'] ?? item['name'])?.toString() ?? '';
                final date = (item['release_date'] ?? item['first_air_date'])?.toString() ?? '';
                final year = date.length >= 4 ? date.substring(0, 4) : '';
                final posterPath = item['poster_path']?.toString();
                final poster = posterPath != null ? 'https://image.tmdb.org/t/p/w300$posterPath' : null;
                results.add({
                  'id': id,
                  'name': title,
                  'type': type,
                  'year': year,
                  'poster': poster,
                  'description': item['overview']?.toString() ?? '',
                });
              }
            }
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// Fetches complete series catalog details including seasons and episodes.
  static Future<Map<String, dynamic>?> getSeriesDetails(String rawId) async {
    String baseId = rawId;
    if (baseId.contains(':')) {
      baseId = baseId.split(':')[0];
    }

    String? imdbId;
    if (baseId.startsWith('tt')) {
      imdbId = baseId;
    } else if (baseId.startsWith('tmdb:')) {
      final numericStr = baseId.replaceFirst('tmdb:', '');
      final tmdbId = int.tryParse(numericStr);
      if (tmdbId != null) {
        try {
          final uri = Uri.parse('$_tmdbDirect/tv/$tmdbId?api_key=$_apiKey');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            imdbId = data['external_ids']?['imdb_id'] ?? data['imdb_id'];
          }
        } catch (_) {}
      }
    }

    if (imdbId == null || !imdbId.startsWith('tt')) {
      return null;
    }

    try {
      final uri = Uri.parse('$_cinemeta/series/$imdbId.json');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final meta = data['meta'];
        if (meta != null) {
          final videos = (meta['videos'] as List?) ?? [];
          final seasonsSet = <int>{};
          final episodesBySeason = <String, List<Map<String, dynamic>>>{};

          for (final v in videos) {
            if (v is Map) {
              final sNum = v['season'] as int? ?? 1;
              final eNum = (v['number'] ?? v['episode']) as int? ?? 1;
              seasonsSet.add(sNum);
              final sKey = sNum.toString();
              episodesBySeason.putIfAbsent(sKey, () => []);
              episodesBySeason[sKey]!.add({
                'id': v['id']?.toString() ?? '$imdbId:$sNum:$eNum',
                'season': sNum,
                'episode': eNum,
                'name': v['name']?.toString() ?? 'Episode $eNum',
                'thumbnail': v['thumbnail']?.toString() ?? 'https://episodes.metahub.space/$imdbId/$sNum/$eNum/w780.jpg',
                'overview': v['overview']?.toString() ?? v['description']?.toString() ?? '',
                'released': v['released']?.toString() ?? v['firstAired']?.toString() ?? '',
              });
            }
          }

          final sortedSeasons = seasonsSet.toList()..sort();

          return {
            'id': imdbId,
            'name': meta['name']?.toString() ?? '',
            'year': meta['year']?.toString() ?? meta['releaseInfo']?.toString() ?? '',
            'poster': meta['poster']?.toString() ?? 'https://images.metahub.space/poster/medium/$imdbId/img',
            'background': meta['background']?.toString() ?? 'https://images.metahub.space/background/medium/$imdbId/img',
            'description': meta['description']?.toString() ?? '',
            'imdbRating': meta['imdbRating']?.toString() ?? '',
            'genres': meta['genres'] ?? [],
            'seasons': sortedSeasons,
            'episodesBySeason': episodesBySeason,
          };
        }
      }
    } catch (_) {}

    return null;
  }

  /// Fetches complete media catalog details (movie or series) including poster, backdrop, synopsis, rating, and episodes.
  static Future<Map<String, dynamic>?> getMediaDetails(String rawId, {String type = 'movie'}) async {
    final cleanType = (type == 'series' || type == 'tv') ? 'series' : 'movie';
    if (cleanType == 'series') {
      return getSeriesDetails(rawId);
    }

    String baseId = rawId;
    if (baseId.contains(':')) {
      baseId = baseId.split(':')[0];
    }

    String? imdbId;
    if (baseId.startsWith('tt')) {
      imdbId = baseId;
    } else if (baseId.startsWith('tmdb:')) {
      final numericStr = baseId.replaceFirst('tmdb:', '');
      final tmdbId = int.tryParse(numericStr);
      if (tmdbId != null) {
        try {
          final uri = Uri.parse('$_tmdbDirect/movie/$tmdbId?api_key=$_apiKey');
          final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            imdbId = data['external_ids']?['imdb_id'] ?? data['imdb_id'];
            if (imdbId == null || !imdbId.startsWith('tt')) {
              return {
                'id': rawId,
                'name': data['title']?.toString() ?? '',
                'year': (data['release_date']?.toString() ?? '').split('-').first,
                'poster': data['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${data['poster_path']}' : null,
                'background': data['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/original${data['backdrop_path']}' : null,
                'description': data['overview']?.toString() ?? '',
                'imdbRating': data['vote_average']?.toString() ?? '',
                'genres': (data['genres'] as List?)?.map((g) => g['name']?.toString() ?? '').toList() ?? [],
                'type': 'movie',
              };
            }
          }
        } catch (_) {}
      }
    }

    if (imdbId == null || !imdbId.startsWith('tt')) {
      return null;
    }

    try {
      final uri = Uri.parse('$_cinemeta/movie/$imdbId.json');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final meta = data['meta'];
        if (meta != null) {
          return {
            'id': imdbId,
            'name': meta['name']?.toString() ?? '',
            'year': meta['year']?.toString() ?? meta['releaseInfo']?.toString() ?? '',
            'poster': meta['poster']?.toString() ?? 'https://images.metahub.space/poster/medium/$imdbId/img',
            'background': meta['background']?.toString() ?? 'https://images.metahub.space/background/medium/$imdbId/img',
            'description': meta['description']?.toString() ?? '',
            'imdbRating': meta['imdbRating']?.toString() ?? '',
            'genres': meta['genres'] ?? [],
            'type': 'movie',
          };
        }
      }
    } catch (_) {}

    return null;
  }
}

