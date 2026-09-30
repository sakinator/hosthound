import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'config.dart';

class OmdbMetadata {
  final String? imdbId;
  final String? title;
  final String? year;
  final String? rated;
  final String? runtime;
  final String? genre;
  final String? director;
  final String? writer;
  final String? actors;
  final String? plot;
  final String? awards;
  final String? poster;
  final String? imdbRating;
  final String? imdbVotes;
  final String? metascore;
  final String? rottenTomatoes;
  final String? boxOffice;
  final String? country;
  final String? language;

  OmdbMetadata({
    this.imdbId,
    this.title,
    this.year,
    this.rated,
    this.runtime,
    this.genre,
    this.director,
    this.writer,
    this.actors,
    this.plot,
    this.awards,
    this.poster,
    this.imdbRating,
    this.imdbVotes,
    this.metascore,
    this.rottenTomatoes,
    this.boxOffice,
    this.country,
    this.language,
  });

  /// Produces a sleek, compact rating badge string suitable for stream cards:
  /// e.g. "⭐ 8.8 IMDb • 🍅 86% RT • Ⓜ️ 74 Metascore"
  String get formattedRatingBadge {
    final parts = <String>[];
    if (imdbRating != null && imdbRating != 'N/A' && imdbRating!.isNotEmpty) {
      parts.add('⭐ $imdbRating IMDb');
    }
    if (rottenTomatoes != null && rottenTomatoes != 'N/A' && rottenTomatoes!.isNotEmpty) {
      parts.add('🍅 $rottenTomatoes RT');
    }
    if (metascore != null && metascore != 'N/A' && metascore!.isNotEmpty) {
      parts.add('Ⓜ️ $metascore Metascore');
    }
    return parts.join(' • ');
  }

  factory OmdbMetadata.fromJson(Map<String, dynamic> json) {
    String? rt;
    final ratings = json['Ratings'] as List?;
    if (ratings != null) {
      for (final r in ratings) {
        if (r is Map && r['Source'] == 'Rotten Tomatoes') {
          rt = r['Value']?.toString();
          break;
        }
      }
    }

    return OmdbMetadata(
      imdbId: json['imdbID']?.toString(),
      title: json['Title']?.toString(),
      year: json['Year']?.toString(),
      rated: json['Rated']?.toString(),
      runtime: json['Runtime']?.toString(),
      genre: json['Genre']?.toString(),
      director: json['Director']?.toString(),
      writer: json['Writer']?.toString(),
      actors: json['Actors']?.toString(),
      plot: json['Plot']?.toString(),
      awards: json['Awards']?.toString(),
      poster: json['Poster']?.toString(),
      imdbRating: json['imdbRating']?.toString(),
      imdbVotes: json['imdbVotes']?.toString(),
      metascore: json['Metascore']?.toString(),
      rottenTomatoes: rt,
      boxOffice: json['BoxOffice']?.toString(),
      country: json['Country']?.toString(),
      language: json['Language']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (imdbId != null) 'imdbId': imdbId,
        if (title != null) 'title': title,
        if (year != null) 'year': year,
        if (rated != null) 'rated': rated,
        if (runtime != null) 'runtime': runtime,
        if (genre != null) 'genre': genre,
        if (director != null) 'director': director,
        if (writer != null) 'writer': writer,
        if (actors != null) 'actors': actors,
        if (plot != null) 'plot': plot,
        if (awards != null) 'awards': awards,
        if (poster != null) 'poster': poster,
        if (imdbRating != null) 'imdbRating': imdbRating,
        if (imdbVotes != null) 'imdbVotes': imdbVotes,
        if (metascore != null) 'metascore': metascore,
        if (rottenTomatoes != null) 'rottenTomatoes': rottenTomatoes,
        if (boxOffice != null) 'boxOffice': boxOffice,
        if (country != null) 'country': country,
        if (language != null) 'language': language,
      };
}

class OmdbService {
  static final OmdbService instance = OmdbService._();

  OmdbService._();

  static final Map<String, OmdbMetadata> _cache = {};
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

  /// Resolves live ratings and metadata from OMDb API.
  Future<OmdbMetadata?> getMetadata(
    String? imdbId, {
    String? title,
    int? year,
  }) async {
    final key = imdbId ?? '${title}_$year';
    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    final userKey = AddonConfig.instance.omdbApiKey.trim();
    final apiKey = userKey.isNotEmpty ? userKey : 'b9a5e69d';

    Uri uri;
    if (imdbId != null && imdbId.startsWith('tt')) {
      uri = Uri.parse('https://www.omdbapi.com/?i=$imdbId&apikey=$apiKey');
    } else if (title != null && title.isNotEmpty) {
      final yParam = year != null ? '&y=$year' : '';
      uri = Uri.parse('https://www.omdbapi.com/?t=${Uri.encodeComponent(title)}$yParam&apikey=$apiKey');
    } else {
      return null;
    }

    try {
      final req = await _client.getUrl(uri).timeout(const Duration(milliseconds: 3500));
      final res = await req.close().timeout(const Duration(milliseconds: 3500));
      if (res.statusCode == 200) {
        final body = await utf8.decodeStream(res);
        final json = jsonDecode(body);
        if (json is Map<String, dynamic> && json['Response'] == 'True') {
          final data = OmdbMetadata.fromJson(json);
          _cache[key] = data;
          return data;
        }
      } else {
        await res.drain<void>();
      }
    } catch (e) {
      // Graceful timeout/fallback – never block scraping
      print('[OmdbService] Warning: Failed to query OMDb: $e');
    }

    return null;
  }
}
