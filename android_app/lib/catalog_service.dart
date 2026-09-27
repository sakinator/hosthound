import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CatalogService {
  static final CatalogService instance = CatalogService._();

  CatalogService._();

  // Invidious public instances with automatic fallback
  static const List<String> _invidiousInstances = [
    'https://invidious.projectsegfau.lt',
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://vid.puffyan.us',
    'https://inv.tux.pizza',
  ];

  static final Map<String, dynamic> _cache = {};

  /// Returns catalog specifications for manifest.json
  static List<Map<String, dynamic>> getCatalogs() {
    return [
      {
        'type': 'movie',
        'id': 'yt_indian',
        'name': 'YouTube Indian Cinema',
        'posterShape': 'landscape',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Bollywood Full Movies',
              'South Hindi Dubbed',
              'Indian Web Series',
              'Classic Hindi',
              'Comedy Hindi Movies',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'yt_international',
        'name': 'YouTube International',
        'posterShape': 'landscape',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Action Movies',
              'Sci-Fi & Thriller',
              'Documentaries',
              'Indie Cinema',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'vimeo_picks',
        'name': 'Vimeo Staff Picks & Shorts',
        'posterShape': 'landscape',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Staff Picks',
              'Short of the Week',
              'Animation',
              'Documentaries',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'archive_movies',
        'name': 'Internet Archive Movies',
        'posterShape': 'landscape',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Indian Classics',
              'Golden Era Hollywood',
              'Film Noir',
              'Sci-Fi & Horror',
              'Silent Era',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'dm_movies',
        'name': 'Dailymotion Indian & Global',
        'posterShape': 'landscape',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Hindi Movies & Dramas',
              'Pakistani Dramas',
              'International Movies',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
    ];
  }

  /// Handles /catalog/:type/:id.json and /catalog/:type/:id/:extra.json
  Future<List<Map<String, dynamic>>> getCatalogItems({
    required String type,
    required String id,
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    final cacheKey = '$id:$search:$genre:$skip';
    if (_cache.containsKey(cacheKey)) {
      return List<Map<String, dynamic>>.from(_cache[cacheKey]);
    }

    List<Map<String, dynamic>> items = [];

    try {
      if (id == 'yt_indian') {
        items = await _fetchYouTubeIndian(search: search, genre: genre, skip: skip);
      } else if (id == 'yt_international') {
        items = await _fetchYouTubeInternational(search: search, genre: genre, skip: skip);
      } else if (id == 'vimeo_picks') {
        items = await _fetchVimeo(search: search, genre: genre, skip: skip);
      } else if (id == 'archive_movies') {
        items = await _fetchArchiveOrg(search: search, genre: genre, skip: skip);
      } else if (id == 'dm_movies') {
        items = await _fetchDailymotion(search: search, genre: genre, skip: skip);
      }
    } catch (e) {
      print('[CatalogService] Error fetching catalog $id: $e');
    }

    _cache[cacheKey] = items;
    return items;
  }

  // ── YouTube Indian Fetcher ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchYouTubeIndian({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String query;
    if (search != null && search.isNotEmpty) {
      query = '$search full movie hindi';
    } else {
      switch (genre) {
        case 'South Hindi Dubbed':
          query = 'south indian full movie hindi dubbed hd';
          break;
        case 'Indian Web Series':
          query = 'hindi web series full episodes hd';
          break;
        case 'Classic Hindi':
          query = 'old classic hindi full movie';
          break;
        case 'Comedy Hindi Movies':
          query = 'comedy full movie hindi';
          break;
        case 'Bollywood Full Movies':
        default:
          query = 'bollywood full movie hd';
          break;
      }
    }

    return _searchInvidious(query, genre: genre ?? 'Indian');
  }

  // ── YouTube International Fetcher ───────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchYouTubeInternational({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String query;
    if (search != null && search.isNotEmpty) {
      query = '$search full movie';
    } else {
      switch (genre) {
        case 'Sci-Fi & Thriller':
          query = 'sci-fi thriller full movie english';
          break;
        case 'Documentaries':
          query = 'documentary full movie english hd';
          break;
        case 'Indie Cinema':
          query = 'award winning indie full movie';
          break;
        case 'Action Movies':
        default:
          query = 'action full movie english hd';
          break;
      }
    }

    return _searchInvidious(query, genre: genre ?? 'International');
  }

  Future<List<Map<String, dynamic>>> _searchInvidious(String query, {required String genre}) async {
    for (final instance in _invidiousInstances) {
      try {
        final url = Uri.parse('$instance/api/v1/search?q=${Uri.encodeComponent(query)}&type=video');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List;
          final metas = <Map<String, dynamic>>[];
          for (final item in list) {
            final vId = item['videoId']?.toString() ?? '';
            final title = item['title']?.toString() ?? '';
            if (vId.isEmpty || title.isEmpty) continue;

            // Prefer HD 720p crisp thumbnail for YouTube
            final thumbs = item['videoThumbnails'] as List?;
            String poster = 'https://i.ytimg.com/vi/$vId/hq720.jpg';
            if (thumbs != null && thumbs.isNotEmpty) {
              final raw = thumbs.last['url']?.toString() ?? '';
              if (raw.startsWith('http') && !raw.contains('mqdefault') && !raw.contains('default.jpg')) {
                poster = raw;
              } else if (raw.isNotEmpty && !raw.contains('mqdefault')) {
                poster = 'https://i.ytimg.com$raw';
              }
            }

            metas.add({
              'id': 'yt:$vId',
              'type': 'movie',
              'name': title,
              'poster': poster,
              'background': 'https://i.ytimg.com/vi/$vId/maxresdefault.jpg',
              'description': item['description']?.toString() ?? 'YouTube Media ($genre)',
              'releaseInfo': item['publishedText']?.toString() ?? '',
              'genres': ['YouTube', genre],
            });
          }
          if (metas.isNotEmpty) return metas;
        }
      } catch (_) {}
    }
    return [];
  }

  // ── Internet Archive Fetcher ────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchArchiveOrg({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String q;
    if (search != null && search.isNotEmpty) {
      q = 'mediatype:movies AND (title:${Uri.encodeComponent(search)} OR description:${Uri.encodeComponent(search)})';
    } else {
      switch (genre) {
        case 'Indian Classics':
          q = 'mediatype:movies AND (title:hindi OR title:india OR title:bollywood OR collection:hindi_movies)';
          break;
        case 'Film Noir':
          q = 'mediatype:movies AND (collection:Film_Noir OR subject:film-noir)';
          break;
        case 'Sci-Fi & Horror':
          q = 'mediatype:movies AND (collection:SciFi_Horror OR subject:horror)';
          break;
        case 'Silent Era':
          q = 'mediatype:movies AND collection:silent_films';
          break;
        case 'Golden Era Hollywood':
        default:
          q = 'mediatype:movies AND collection:feature_films';
          break;
      }
    }

    final page = (skip / 20).floor() + 1;
    final url = Uri.parse(
        'https://archive.org/advancedsearch.php?q=$q&fl[]=identifier,title,description,year&sort[]=downloads+desc&rows=20&page=$page&output=json');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['response']['docs'] as List;
        return docs.map<Map<String, dynamic>>((doc) {
          final id = doc['identifier']?.toString() ?? '';
          final title = doc['title']?.toString() ?? id;
          final year = doc['year']?.toString() ?? '';
          final desc = doc['description']?.toString() ?? 'Internet Archive Classic';
          final poster = 'https://archive.org/download/$id/__ia_thumb.jpg';

          return {
            'id': 'archive:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'background': poster,
            'description': desc,
            'releaseInfo': year,
            'genres': ['Archive.org', genre ?? 'Classic'],
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Archive.org error: $e');
    }
    return [];
  }

  // ── Vimeo Fetcher ───────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchVimeo({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String channel = 'staffpicks';
    if (genre == 'Short of the Week') {
      channel = 'shortsoftheweek';
    } else if (genre == 'Animation') {
      channel = 'animation';
    } else if (genre == 'Documentaries') {
      channel = 'documentary';
    }
    final page = (skip / 20).floor() + 1;
    final url = Uri.parse('https://vimeo.com/api/v2/channel/$channel/videos.json?page=$page');
    try {
      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        return list.map<Map<String, dynamic>>((item) {
          final id = item['id'].toString();
          final title = item['title']?.toString() ?? 'Vimeo Video';
          final desc = (item['description']?.toString() ?? '')
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim();
          final poster = item['thumbnail_large']?.toString() ?? item['thumbnail_medium']?.toString() ?? '';
          final durationSec = item['duration'] is int ? item['duration'] as int : 0;
          final durationMin = (durationSec / 60).round();
          return {
            'id': 'vimeo:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'background': poster,
            'description': desc.isNotEmpty ? desc : 'Vimeo Staff Pick',
            'releaseInfo': durationMin > 0 ? '$durationMin min' : '',
            'genres': ['Vimeo', genre ?? 'Staff Picks'],
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Vimeo error: $e');
    }
    return [];
  }

  // ── Dailymotion Fetcher ─────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchDailymotion({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String q;
    if (search != null && search.isNotEmpty) {
      q = search;
    } else {
      switch (genre) {
        case 'Pakistani Dramas':
          q = 'pakistani drama full episode';
          break;
        case 'International Movies':
          q = 'full movie english';
          break;
        case 'Hindi Movies & Dramas':
        default:
          q = 'hindi full movie hd';
          break;
      }
    }

    final page = (skip / 20).floor() + 1;
    final url = Uri.parse(
        'https://api.dailymotion.com/videos?fields=id,title,description,thumbnail_1080_url,thumbnail_720_url,thumbnail_480_url,thumbnail_url,created_time&search=${Uri.encodeComponent(q)}&limit=20&page=$page');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['list'] as List;
        return list.map<Map<String, dynamic>>((item) {
          final id = item['id']?.toString() ?? '';
          final title = item['title']?.toString() ?? id;
          final desc = item['description']?.toString() ?? 'Dailymotion Stream';
          final poster = item['thumbnail_1080_url']?.toString() ??
              item['thumbnail_720_url']?.toString() ??
              item['thumbnail_480_url']?.toString() ??
              item['thumbnail_url']?.toString() ??
              '';

          return {
            'id': 'dm:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'background': poster,
            'description': desc,
            'genres': ['Dailymotion', genre ?? 'Video'],
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Dailymotion error: $e');
    }
    return [];
  }

  // ── Meta Details Resolver (/meta/:type/:id.json) ───────────────────────────
  Future<Map<String, dynamic>?> getMetaDetail(String type, String id) async {
    if (id.startsWith('yt:')) {
      final vId = id.replaceFirst('yt:', '');
      return {
        'id': id,
        'type': type,
        'name': 'YouTube Video',
        'poster': 'https://i.ytimg.com/vi/$vId/hqdefault.jpg',
        'background': 'https://i.ytimg.com/vi/$vId/maxresdefault.jpg',
        'description': 'Direct YouTube Stream',
      };
    }

    if (id.startsWith('archive:')) {
      final ident = id.replaceFirst('archive:', '');
      try {
        final res = await http.get(Uri.parse('https://archive.org/metadata/$ident')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final meta = json['metadata'] ?? {};
          final title = meta['title'] ?? ident;
          final desc = meta['description'] ?? 'Internet Archive Classic';
          final year = meta['year'] ?? '';
          final poster = 'https://archive.org/services/img/$ident';
          return {
            'id': id,
            'type': type,
            'name': title,
            'poster': poster,
            'background': poster,
            'description': desc,
            'releaseInfo': year,
          };
        }
      } catch (_) {}
      return {
        'id': id,
        'type': type,
        'name': ident,
        'poster': 'https://archive.org/services/img/$ident',
        'description': 'Internet Archive Media',
      };
    }

    if (id.startsWith('dm:')) {
      final vId = id.replaceFirst('dm:', '');
      try {
        final res = await http.get(Uri.parse('https://api.dailymotion.com/video/$vId?fields=title,description,thumbnail_720_url')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          return {
            'id': id,
            'type': type,
            'name': json['title'] ?? 'Dailymotion Video',
            'poster': json['thumbnail_720_url'] ?? '',
            'background': json['thumbnail_720_url'] ?? '',
            'description': json['description'] ?? '',
          };
        }
      } catch (_) {}
      return {
        'id': id,
        'type': type,
        'name': 'Dailymotion Video',
        'description': 'Dailymotion Stream',
      };
    }

    if (id.startsWith('vimeo:')) {
      final vId = id.replaceFirst('vimeo:', '');
      try {
        final res = await http.get(Uri.parse('https://vimeo.com/api/oembed.json?url=https://vimeo.com/$vId')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final title = json['title']?.toString() ?? 'Vimeo Video';
          final poster = json['thumbnail_url']?.toString() ?? '';
          final author = json['author_name']?.toString() ?? '';
          final desc = json['description']?.toString() ?? (author.isNotEmpty ? 'By $author on Vimeo' : 'Vimeo Staff Pick');
          return {
            'id': id,
            'type': type,
            'name': title,
            'poster': poster,
            'background': poster,
            'description': desc,
          };
        }
      } catch (_) {}
      return {
        'id': id,
        'type': type,
        'name': 'Vimeo Video',
        'description': 'Vimeo Stream',
      };
    }

    return null;
  }

  // ── Stream Resolvers (/stream/:type/:id.json) ──────────────────────────────
  Future<List<Map<String, dynamic>>> resolveCustomStreams(String type, String id) async {
    // 1. YouTube Stream Resolver
    if (id.startsWith('yt:')) {
      final vId = id.replaceFirst('yt:', '');
      return _resolveYouTubeStreams(vId);
    }

    // 2. Vimeo Stream Resolver
    if (id.startsWith('vimeo:')) {
      final vId = id.replaceFirst('vimeo:', '');
      return _resolveVimeoStreams(vId);
    }

    // 3. Internet Archive Stream Resolver
    if (id.startsWith('archive:')) {
      final ident = id.replaceFirst('archive:', '');
      return _resolveArchiveStreams(ident);
    }

    // 4. Dailymotion Stream Resolver
    if (id.startsWith('dm:')) {
      final vId = id.replaceFirst('dm:', '');
      return _resolveDailymotionStreams(vId);
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> _resolveYouTubeStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    for (final instance in _invidiousInstances) {
      try {
        final url = Uri.parse('$instance/api/v1/videos/$vId');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final formatStreams = json['formatStreams'] as List?;
          if (formatStreams != null) {
            for (final f in formatStreams) {
              final streamUrl = f['url']?.toString();
              final quality = f['qualityLabel']?.toString() ?? f['resolution']?.toString() ?? 'Direct';
              if (streamUrl != null && streamUrl.isNotEmpty) {
                streams.add({
                  'name': 'YouTube ($quality)',
                  'title': '⚡ Direct Stream (Non-Torrent) • $quality',
                  'url': streamUrl,
                  'behaviorHints': {'notWebReady': false},
                });
              }
            }
          }
          final hlsUrl = json['hlsUrl']?.toString();
          if (hlsUrl != null && hlsUrl.isNotEmpty) {
            streams.insert(0, {
              'name': 'YouTube HLS',
              'title': '⚡ Adaptive HLS Master Stream (Non-Torrent)',
              'url': hlsUrl,
              'behaviorHints': {'notWebReady': false},
            });
          }
          if (streams.isNotEmpty) return streams;
        }
      } catch (_) {}
    }

    // Fallback: direct invidious playback url
    streams.add({
      'name': 'YouTube Web Player',
      'title': 'Direct Stream Link',
      'url': 'https://www.youtube.com/watch?v=$vId',
    });
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveVimeoStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final url = Uri.parse('https://player.vimeo.com/video/$vId');
      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://vimeo.com/$vId',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final html = res.body;
        final m = RegExp(r'(\{"cdn_url":.+?\})\s*</script>').firstMatch(html);
        if (m != null) {
          final data = jsonDecode(m.group(1)!);
          final files = data['request']?['files'] as Map?;
          if (files != null) {
            final hls = files['hls'] as Map?;
            if (hls != null) {
              final cdns = hls['cdns'] as Map?;
              if (cdns != null && cdns.isNotEmpty) {
                final defaultCdn = hls['default_cdn']?.toString() ?? cdns.keys.first;
                final cdnObj = cdns[defaultCdn] ?? cdns.values.first;
                final m3u8Url = cdnObj?['url']?.toString();
                if (m3u8Url != null && m3u8Url.isNotEmpty) {
                  streams.add({
                    'name': '⚡ Vimeo Master HLS',
                    'title': '⚡ Adaptive Quality Master Stream (Direct CDN)',
                    'url': m3u8Url,
                    'behaviorHints': {'notWebReady': false},
                  });
                }
              }
            }
            final progressive = files['progressive'] as List?;
            if (progressive != null) {
              for (final p in progressive) {
                if (p is Map) {
                  final q = p['quality']?.toString() ?? 'HD';
                  final pUrl = p['url']?.toString();
                  if (pUrl != null && pUrl.isNotEmpty) {
                    streams.add({
                      'name': '🌐 Vimeo Direct ($q)',
                      'title': '🌐 Direct MP4 Video • $q',
                      'url': pUrl,
                      'behaviorHints': {'notWebReady': false},
                    });
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Vimeo resolve error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Vimeo Web Player',
        'title': '⚡ Direct Web Stream',
        'url': 'https://vimeo.com/$vId',
      });
    }
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveArchiveStreams(String ident) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final res = await http.get(Uri.parse('https://archive.org/metadata/$ident')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final files = data['files'] as List?;
        if (files != null) {
          // Find MP4 or MKV video files
          for (final f in files) {
            final name = f['name']?.toString() ?? '';
            final format = f['format']?.toString() ?? '';
            if (name.endsWith('.mp4') || format.contains('MPEG4') || format.contains('h.264')) {
              final size = f['size'] != null ? ' (${(int.parse(f['size'].toString()) / (1024 * 1024)).toStringAsFixed(1)} MB)' : '';
              streams.add({
                'name': 'Archive.org',
                'title': '⚡ $name$size • Direct Cloud Stream (Non-Torrent)',
                'url': 'https://archive.org/download/$ident/$name',
                'behaviorHints': {'notWebReady': false},
              });
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Archive stream resolve error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Archive.org',
        'title': '⚡ Direct Video Download/Stream',
        'url': 'https://archive.org/download/$ident/$ident.mp4',
      });
    }
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveDailymotionStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final metaUrl = Uri.parse('https://www.dailymotion.com/player/metadata/video/$vId');
      final res = await http.get(metaUrl).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final qualities = json['qualities'] as Map?;
        if (qualities != null) {
          final auto = qualities['auto'] as List?;
          if (auto != null && auto.isNotEmpty) {
            final hlsUrl = auto.first['url']?.toString();
            if (hlsUrl != null && hlsUrl.isNotEmpty) {
              streams.add({
                'name': 'Dailymotion HLS',
                'title': '⚡ Adaptive Auto Quality HLS • Direct Stream (Non-Torrent)',
                'url': hlsUrl,
                'behaviorHints': {'notWebReady': false},
              });
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Dailymotion stream error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Dailymotion Direct',
        'title': '⚡ Direct Web Stream',
        'url': 'https://www.dailymotion.com/video/$vId',
      });
    }
    return streams;
  }
}
