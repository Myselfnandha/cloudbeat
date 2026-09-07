import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/contracts/models.dart';
import '../../core/services/app_logger.dart';

/// InnerTube Music Discovery Service
/// Powers Home shelves (Charts, Moods & Genres, New Releases) and Search Autocomplete
class InnerTubeService {
  final http.Client _httpClient;

  InnerTubeService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  static const String _suggestUrl = 'https://suggestqueries.google.com/complete/search';
  static const String _innerTubeBase = 'https://music.youtube.com/youtubei/v1';

  /// Predefined Moods & Genres matching M3-Play
  static const List<String> moodsAndGenres = [
    'Chill',
    'Focus',
    'Workout',
    'Party',
    'Sleep',
    'Romance',
    'Energize',
    'Feel Good',
  ];

  /// Get search autocomplete suggestions
  Future<List<String>> getSearchSuggestions(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.parse(_suggestUrl).replace(queryParameters: {
        'client': 'firefox',
        'ds': 'yt',
        'q': query,
      });

      final resp = await _httpClient.get(
        uri,
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as List<dynamic>;
      if (data.length >= 2 && data[1] is List) {
        return (data[1] as List).map((e) => e.toString()).toList();
      }
    } catch (e) {
      AppLogger.trace('InnerTubeService', 'suggestError', {'error': e.toString()});
    }
    return [];
  }

  /// Fetch top trending / chart songs using InnerTube payload
  Future<List<Track>> getCharts({int limit = 20}) async {
    AppLogger.trace('InnerTubeService', 'getCharts');
    try {
      final uri = Uri.parse('$_innerTubeBase/browse');
      final payload = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'browseId': 'FEmusic_charts',
      };

      final resp = await _httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.youtube.com/',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final parsed = _parseInnerTubeTracks(resp.body);
        if (parsed.isNotEmpty) {
          return parsed.take(limit).toList();
        }
      }
    } catch (e) {
      AppLogger.trace('InnerTubeService', 'chartsError', {'error': e.toString()});
    }

    // Fallback seed tracks if network error
    return _buildSeedCharts();
  }

  /// Fetch tracks for a specific Mood or Genre
  Future<List<Track>> getMoodTracks(String mood, {int limit = 15}) async {
    AppLogger.trace('InnerTubeService', 'getMoodTracks', {'mood': mood});
    try {
      final uri = Uri.parse('$_innerTubeBase/search');
      final payload = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'query': '$mood Music Hits',
      };

      final resp = await _httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.youtube.com/',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final parsed = _parseInnerTubeTracks(resp.body);
        if (parsed.isNotEmpty) {
          return parsed.take(limit).toList();
        }
      }
    } catch (_) {}

    return _buildSeedMoodTracks(mood);
  }

  List<Track> _parseInnerTubeTracks(String jsonStr) {
    final tracks = <Track>[];
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      void searchIn(dynamic node) {
        if (node is Map<String, dynamic>) {
          if (node.containsKey('musicResponsiveListItemRenderer')) {
            final renderer = node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
            final track = _extractTrackFromRenderer(renderer);
            if (track != null) tracks.add(track);
            return;
          }
          for (final val in node.values) {
            searchIn(val);
          }
        } else if (node is List) {
          for (final item in node) {
            searchIn(item);
          }
        }
      }

      searchIn(data);
    } catch (e) {
      AppLogger.trace('InnerTubeService', 'parseError', {'error': e.toString()});
    }
    return tracks;
  }

  Track? _extractTrackFromRenderer(Map<String, dynamic> r) {
    try {
      final flexColumns = r['flexColumns'] as List<dynamic>?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      // Title
      final col0 = flexColumns[0] as Map<String, dynamic>;
      final titleRuns = col0['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
      final title = titleRuns?.isNotEmpty == true ? titleRuns![0]['text'] as String : '';
      if (title.isEmpty) return null;

      // Artists & Album
      String artist = 'Unknown Artist';
      String album = 'Single';
      if (flexColumns.length > 1) {
        final col1 = flexColumns[1] as Map<String, dynamic>;
        final runs = col1['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
        if (runs != null && runs.isNotEmpty) {
          artist = runs[0]['text'] as String? ?? 'Unknown Artist';
          if (runs.length > 2) {
            album = runs[2]['text'] as String? ?? 'Single';
          }
        }
      }

      // Thumbnail
      String? thumbUrl;
      final thumbs = r['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List<dynamic>?;
      if (thumbs != null && thumbs.isNotEmpty) {
        thumbUrl = thumbs.last['url'] as String?;
      }

      // ID
      final navEndpoint = r['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint'];
      final videoId = navEndpoint?['watchEndpoint']?['videoId'] as String? ??
          navEndpoint?['watchPlaylistEndpoint']?['videoId'] as String? ??
          'it_${title.hashCode}';

      return Track(
        id: 'innertube:$videoId',
        title: title,
        artists: [artist],
        album: album,
        albumArtUrl: thumbUrl,
        durationSeconds: 210,
        isDownloaded: false,
        addedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  List<Track> _buildSeedCharts() {
    return [
      Track(
        id: 'innertube:chart_1',
        title: 'Espresso',
        artists: ['Sabrina Carpenter'],
        album: 'Short n\' Sweet',
        albumArtUrl: 'https://i.scdn.co/image/ab67616d0000b2737197b1022f4ce8e7fb0d6ae3',
        durationSeconds: 175,
        isDownloaded: false,
        addedAt: DateTime.now(),
      ),
      Track(
        id: 'innertube:chart_2',
        title: 'Birds of a Feather',
        artists: ['Billie Eilish'],
        album: 'HIT ME HARD AND SOFT',
        albumArtUrl: 'https://i.scdn.co/image/ab67616d0000b27371d62ea7ea8a5be92d3c1f62',
        durationSeconds: 196,
        isDownloaded: false,
        addedAt: DateTime.now(),
      ),
      Track(
        id: 'innertube:chart_3',
        title: 'Good Luck, Babe!',
        artists: ['Chappell Roan'],
        album: 'Good Luck, Babe!',
        albumArtUrl: 'https://i.scdn.co/image/ab67616d0000b27329d9fd4b98685e1358ae6ec6',
        durationSeconds: 218,
        isDownloaded: false,
        addedAt: DateTime.now(),
      ),
      Track(
        id: 'innertube:chart_4',
        title: 'A Bar Song (Tipsy)',
        artists: ['Shaboozey'],
        album: 'Where I\'ve Been, Isn\'t Where I\'m Going',
        albumArtUrl: 'https://i.scdn.co/image/ab67616d0000b273010f13554cc4199c0da186bd',
        durationSeconds: 171,
        isDownloaded: false,
        addedAt: DateTime.now(),
      ),
    ];
  }

  List<Track> _buildSeedMoodTracks(String mood) {
    return [
      Track(
        id: 'innertube:mood_${mood}_1',
        title: '$mood Horizon',
        artists: ['Ambient Soundscapes'],
        album: '$mood Vibes',
        albumArtUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=500',
        durationSeconds: 180,
        isDownloaded: false,
        addedAt: DateTime.now(),
      ),
      Track(
        id: 'innertube:mood_${mood}_2',
        title: 'Midnight Reflection',
        artists: ['Solar Drift'],
        album: '$mood Sessions',
        albumArtUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=500',
        durationSeconds: 210,
        isDownloaded: false,
        addedAt: DateTime.now(),
      ),
    ];
  }
}
