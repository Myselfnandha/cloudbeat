import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/ffi/acquisition_ffi.dart';
import '../../core/matching/track_matcher.dart';
import '../../core/session/zarz_session_manager.dart';
import '../../core/services/piped_stream_resolver.dart';
import '../../core/services/deezer_stream_resolver.dart';
import '../../core/services/cobalt_stream_resolver.dart';
import '../../core/services/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NativeAcquisitionService implements AcquisitionContract {
  final AcquisitionFfiBridge _ffi;
  final http.Client _client;
  final ZarzSessionManager zarzSession;
  final PipedStreamResolver _pipedResolver;
  final DeezerStreamResolver _deezerResolver;
  final CobaltStreamResolver _cobaltResolver;
  final List<String> _supportedBackends = ['qobuz', 'tidal', 'deezer', 'spotify', 'apple', 'amazon', 'ytmusic'];
  
  final String _extensionBaseUrl = 'https://raw.githubusercontent.com/spotiflacapp/spotiflac-extension/main/dist';
  
  bool _initialized = false;
  final Map<String, bool> _loadedExtensions = {};

  NativeAcquisitionService(
    this._ffi, {
    http.Client? client,
    ZarzSessionManager? zarzSession,
    PipedStreamResolver? pipedResolver,
    DeezerStreamResolver? deezerResolver,
    CobaltStreamResolver? cobaltResolver,
  })  : _client = client ?? http.Client(),
        zarzSession = zarzSession ?? ZarzSessionManager(),
        _pipedResolver = pipedResolver ?? PipedStreamResolver(client: client),
        _deezerResolver = deezerResolver ?? DeezerStreamResolver(client: client, zarzSession: zarzSession),
        _cobaltResolver = cobaltResolver ?? CobaltStreamResolver(client: client);

  Future<void> initialize() async {
    AppLogger.trace('NativeAcquisitionService', 'initialize');
    if (_initialized) return;
    
    await zarzSession.initialize();

    // Step 1: Load bundled local extensions immediately (works offline & on cold start)
    for (final backend in _supportedBackends) {
      await _loadBundledExtension(backend);
    }
    _initialized = true;

    // Step 2: Fire-and-forget background check for remote updates
    _checkRemoteUpdatesInBackground();
  }

  Future<void> _loadBundledExtension(String backend) async {
    AppLogger.trace('NativeAcquisitionService', '_loadBundledExtension', {'backend': backend});
    try {
      final manifestStr = await rootBundle.loadString('assets/extensions/$backend/manifest.json');
      final scriptStr = await rootBundle.loadString('assets/extensions/$backend/index.js');
      final success = _ffi.loadExtension(backend, manifestStr, scriptStr);
      _loadedExtensions[backend] = success;
    } catch (_) {
      // If asset loading not available (e.g. in headless unit tests), mark false
      _loadedExtensions[backend] = false;
    }
  }

  void _checkRemoteUpdatesInBackground() {
    AppLogger.trace('NativeAcquisitionService', '_checkRemoteUpdatesInBackground');
    Future.microtask(() async {
      for (final backend in _supportedBackends) {
        try {
          final manifestUrl = '$_extensionBaseUrl/$backend/manifest.json';
          final scriptUrl = '$_extensionBaseUrl/$backend/index.js';
          
          final manifestRes = await _client.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 5));
          final scriptRes = await _client.get(Uri.parse(scriptUrl)).timeout(const Duration(seconds: 5));
          
          if (manifestRes.statusCode == 200 && scriptRes.statusCode == 200) {
            _ffi.loadExtension(backend, manifestRes.body, scriptRes.body);
            _loadedExtensions[backend] = true;
          }
        } catch (_) {}
      }
    });
  }

  Future<List<String>> _getWaterfallPriority() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('provider_waterfall_priority');
    if (saved != null && saved.isNotEmpty) {
      return saved.where((b) => _supportedBackends.contains(b)).toList();
    }
    return _supportedBackends;
  }

  @override
  Future<List<ExternalTrackResult>> searchAllBackends(
    String query, {
    List<String>? backends,
    int limit = 20,
  }) async {
    AppLogger.trace('NativeAcquisitionService', 'searchAllBackends', {'query': query, 'limit': limit});
    if (!_initialized) await initialize();
    
    final priority = backends ?? await _getWaterfallPriority();
    
    final prefs = await SharedPreferences.getInstance();
    final activeBackends = priority
        .where((b) => b != 'ytmusic' && b != 'youtube')
        .where((b) => prefs.getBool('provider_${b}_enabled') ?? true)
        .toList();

    List<ExternalTrackResult> results = [];
    
    final futures = activeBackends.map((backend) async {
      if (_loadedExtensions[backend] != true) return <ExternalTrackResult>[];
      
      try {
        final res = _ffi.executeCommand(backend, 'search', [query]);
        if (res is List) {
          return res.map((item) {
            final map = item as Map<String, dynamic>;
            List<AudioQuality> qualities = [AudioQuality.flac16Bit];
            if (map['availableQualities'] is List) {
              qualities = (map['availableQualities'] as List).map((q) {
                switch (q.toString().toLowerCase()) {
                  case 'flac_24': return AudioQuality.flac24Bit;
                  case 'flac_16': return AudioQuality.flac16Bit;
                  case 'opus_320': return AudioQuality.opus320k;
                  default: return AudioQuality.flac16Bit;
                }
              }).toList();
            }
            
            return ExternalTrackResult(
              id: map['id']?.toString() ?? '',
              title: map['title']?.toString() ?? 'Unknown',
              artists: (map['artists'] as List?)?.map((e) => e.toString()).toList() ?? [],
              album: map['album']?.toString() ?? 'Single',
              albumArtUrl: map['albumArtUrl']?.toString(),
              durationSeconds: map['durationSeconds'] as int? ?? 180,
              backend: backend,
              availableQualities: qualities,
              isrc: map['isrc']?.toString(),
            );
          }).toList();
        }
      } catch (e) {
        debugPrint('Error searching backend $backend: $e');
      }
      return <ExternalTrackResult>[];
    });

    final allResults = await Future.wait(futures);
    for (final res in allResults) {
      results.addAll(res);
    }
    
    // Multi-source Pure-Dart search fallback
    if (results.isEmpty) {
      final deezerFallback = await searchDeezerDirect(query, limit: limit);
      if (deezerFallback.isNotEmpty) {
        return deezerFallback;
      }
      final jioFallback = await searchJioSaavnDirect(query, limit: limit);
      if (jioFallback.isNotEmpty) {
        return jioFallback;
      }
      final fallbackResults = await _ffi.searchAllBackends(query, limit: limit);
      return fallbackResults;
    }
    
    return results.take(limit).toList();
  }

  /// Direct Pure-Dart Deezer search via public REST API (fallback when native FFI is uninitialized)
  Future<List<ExternalTrackResult>> searchDeezerDirect(String query, {int limit = 20}) async {
    AppLogger.trace('NativeAcquisitionService', 'searchDeezerDirect', {'query': query, 'limit': limit});
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final uri = Uri.parse(
        'https://api.deezer.com/search?q=${Uri.encodeComponent(trimmed)}&limit=$limit',
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];

      return list.map<ExternalTrackResult>((item) {
        final m = item as Map<String, dynamic>;
        final artistObj = m['artist'] as Map<String, dynamic>?;
        final albumObj = m['album'] as Map<String, dynamic>?;

        final albumArt = albumObj?['cover_xl']?.toString() ??
            albumObj?['cover_big']?.toString() ??
            albumObj?['cover_medium']?.toString();

        return ExternalTrackResult(
          id: m['id'].toString(),
          title: m['title']?.toString() ?? 'Unknown',
          artists: [artistObj?['name']?.toString() ?? 'Unknown Artist'],
          album: albumObj?['title']?.toString() ?? 'Single',
          albumArtUrl: albumArt,
          durationSeconds: m['duration'] as int? ?? 180,
          backend: 'deezer',
          availableQualities: const [
            AudioQuality.flac16Bit,
            AudioQuality.opus320k,
          ],
          isrc: m['isrc']?.toString(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Direct Pure-Dart Deezer charts via public REST API (fallback when native FFI is uninitialized)
  Future<List<ExternalTrackResult>> getDeezerChartDirect({int limit = 30}) async {
    AppLogger.trace('NativeAcquisitionService', 'getDeezerChartDirect', {'limit': limit});
    try {
      final uri = Uri.parse('https://api.deezer.com/chart/0/tracks?limit=$limit');
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];

      return list.map<ExternalTrackResult>((item) {
        final m = item as Map<String, dynamic>;
        final artistObj = m['artist'] as Map<String, dynamic>?;
        final albumObj = m['album'] as Map<String, dynamic>?;

        final albumArt = albumObj?['cover_xl']?.toString() ??
            albumObj?['cover_big']?.toString() ??
            albumObj?['cover_medium']?.toString();

        return ExternalTrackResult(
          id: m['id'].toString(),
          title: m['title']?.toString() ?? 'Unknown',
          artists: [artistObj?['name']?.toString() ?? 'Unknown Artist'],
          album: albumObj?['title']?.toString() ?? 'Single',
          albumArtUrl: albumArt,
          durationSeconds: m['duration'] as int? ?? 180,
          backend: 'deezer',
          availableQualities: const [
            AudioQuality.flac16Bit,
            AudioQuality.opus320k,
          ],
          isrc: m['isrc']?.toString(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<StreamResolution> resolveStreamUrl({
    required String trackId,
    required String backend,
    required AudioQuality requestedQuality,
    String? title,
    String? artist,
    int durationSeconds = 0,
  }) async {
    AppLogger.trace('NativeAcquisitionService', 'resolveStreamUrl', {
      'trackId': trackId,
      'backend': backend,
      'quality': requestedQuality.name,
      'title': title,
    });
    if (!_initialized) await initialize();

    // Determine cascade priority list
    final List<String> cascadeOrder;
    switch (requestedQuality) {
      case AudioQuality.flac24Bit:
        cascadeOrder = [backend, 'qobuz', 'tidal', 'deezer', 'apple', 'amazon'];
        break;
      case AudioQuality.flac16Bit:
        cascadeOrder = [backend, 'deezer', 'tidal', 'qobuz', 'apple', 'amazon'];
        break;
      case AudioQuality.opus320k:
        cascadeOrder = [backend, 'deezer', 'spotify', 'amazon', 'qobuz'];
        break;
      case AudioQuality.lossyFallback:
        cascadeOrder = [backend, 'deezer', 'spotify'];
        break;
    }

    final triedBackends = <String>{};

    var effectiveTrackId = trackId;
    if (int.tryParse(effectiveTrackId) == null && title != null && title.isNotEmpty) {
      try {
        final searchResults = await searchDeezerDirect('$title ${artist ?? ''}'.trim(), limit: 1);
        if (searchResults.isNotEmpty) {
          effectiveTrackId = searchResults.first.id;
        }
      } catch (_) {}
    }

    for (final currentBackend in cascadeOrder) {
      if (triedBackends.contains(currentBackend)) continue;
      triedBackends.add(currentBackend);

      // Attempt 1: Authenticated Zarz V2 two-phase stream resolution (Qobuz / Tidal / Deezer)
      if (['qobuz', 'deezer', 'tidal', 'amazon'].contains(currentBackend)) {
        if (zarzSession.hasValidSession) {
          try {
            final desc = await zarzSession.resolveStreamDescriptor(
              provider: currentBackend,
              trackId: effectiveTrackId,
              format: requestedQuality == AudioQuality.flac24Bit ? 'FLAC_24' : 'FLAC',
            );
            final directUrl = desc['direct_download_url']?.toString() ?? desc['url']?.toString();
            if (directUrl != null && directUrl.isNotEmpty) {
              return StreamResolution(
                streamUrl: directUrl,
                quality: requestedQuality,
              );
            }
          } catch (e) {
            debugPrint('[Acquisition] Zarz descriptor failed for $currentBackend: $e');
            if (e.toString().contains('401') || e.toString().contains('403')) {
              zarzSession.invalidateSession();
            }
          }
        }
      }

      // Attempt 2: Extension runtime execution if loaded
      if (_loadedExtensions[currentBackend] == true) {
        String qualityStr = 'FLAC_16';
        switch (requestedQuality) {
          case AudioQuality.flac24Bit: qualityStr = 'FLAC_24'; break;
          case AudioQuality.opus320k: qualityStr = 'OPUS_320'; break;
          default: qualityStr = 'FLAC_16';
        }

        try {
          final res = _ffi.executeCommand(currentBackend, 'resolveStreamUrl', [effectiveTrackId, qualityStr]);
          if (res is Map<String, dynamic>) {
            final streamUrl = res['streamUrl'] as String?;
            if (streamUrl != null && streamUrl.isNotEmpty) {
              return StreamResolution(
                streamUrl: streamUrl,
                quality: requestedQuality,
                headers: (res['headers'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? const {},
              );
            }
          }
        } catch (_) {
          // Cascade to next backend
        }
      }
    }

    // Direct 320k stream resolution with SongStore fuzzy candidate scoring (JioSaavn)
    if (title != null && title.isNotEmpty) {
      final directStream = await _resolveDirectMediaStream(title, artist ?? '', durationSeconds: durationSeconds);
      if (directStream != null) {
        return StreamResolution(
          streamUrl: directStream,
          quality: AudioQuality.opus320k,
        );
      }
    }

    // Direct Deezer stream resolver (preview or FLAC via Zarz)
    try {
      final deezerStream = await _deezerResolver.resolveAudioStream(
        trackId: effectiveTrackId,
        title: title,
        artist: artist,
        durationSeconds: durationSeconds,
        requestedQuality: requestedQuality,
      );
      if (deezerStream != null) {
        return deezerStream;
      }
    } catch (_) {}

    // Cobalt high-speed stream resolver (resolves canonical YouTube media URL via video ID)
    if (title != null && title.isNotEmpty) {
      try {
        final videoId = await _pipedResolver.findBestVideoId(
          title: title,
          artist: artist ?? '',
          durationSeconds: durationSeconds,
        );
        if (videoId != null && videoId.isNotEmpty) {
          final cobaltRes = await _cobaltResolver.resolveMediaUrl('https://www.youtube.com/watch?v=$videoId');
          if (cobaltRes != null) {
            return cobaltRes;
          }
        }
      } catch (_) {}
    }

    // Piped / YouTube Music stream resolver (universal fallback)
    if (title != null && title.isNotEmpty) {
      try {
        final pipedStream = await _pipedResolver.resolveAudioStream(
          title: title,
          artist: artist ?? '',
          durationSeconds: durationSeconds,
        );
        if (pipedStream != null) {
          return pipedStream;
        }
      } catch (_) {}
    }

    // iTunes direct AAC preview stream fallback (guaranteed high-availability)
    if (title != null && title.isNotEmpty) {
      final itunesStream = await _resolveItunesPreviewStream(title, artist ?? '');
      if (itunesStream != null) {
        return itunesStream;
      }
    }

    // Prompt user for one-time Turnstile verification if Zarz session expired
    if (!zarzSession.hasValidSession) {
      try {
        await zarzSession.launchTurnstileChallenge();
      } catch (_) {}
    }

    if (!_ffi.isNativeLoaded) {
      throw const NativeEngineUnavailableException(
        'Hi-Res streaming unavailable — native engine not loaded',
      );
    }

    throw const NativeEngineUnavailableException(
      'All streaming providers exhausted for track',
    );
  }

  Future<String?> _resolveDirectMediaStream(String title, String artist, {int durationSeconds = 0}) async {
    AppLogger.trace('NativeAcquisitionService', '_resolveDirectMediaStream', {
      'title': title,
      'artist': artist,
      'duration': durationSeconds,
    });
    try {
      final query = Uri.encodeComponent('$title $artist'.trim());
      final searchUri = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getResults&q=$query&n=10&p=1&_format=json&_marker=0&ctx=android',
      );
      final searchRes = await _client.get(searchUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
      }).timeout(const Duration(seconds: 6));
      if (searchRes.statusCode != 200) return null;

      final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final results = searchData['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      // SongStore multi-candidate evaluation using TrackMatcher
      String? bestEncUrl;
      double bestScore = 0.0;

      for (final item in results) {
        final cand = item as Map<String, dynamic>;
        final candTitle = cand['title']?.toString() ?? cand['song']?.toString() ?? '';
        final candArtist = cand['primary_artists']?.toString() ?? cand['subtitle']?.toString() ?? '';
        final moreInfo = (cand['more_info'] as Map<String, dynamic>?) ?? cand;
        final candDuration = int.tryParse(moreInfo['duration']?.toString() ?? '') ?? 0;
        final encUrl = cand['encrypted_media_url']?.toString() ?? moreInfo['encrypted_media_url']?.toString();

        if (encUrl == null || encUrl.isEmpty) continue;

        double score = TrackMatcher.scoreTrackMatch(
          targetTitle: title,
          targetArtist: artist,
          candidateTitle: candTitle,
          candidateArtist: candArtist,
          targetDuration: durationSeconds,
          candidateDuration: candDuration,
        );

        // Prefer tracks with verified lyrics (guarantees studio vocal release vs BGM/dialogue cut)
        final hasLyrics = moreInfo['has_lyrics']?.toString() == 'true' || moreInfo['has_lyrics']?.toString() == '1';
        if (hasLyrics) {
          score += 10.0;
        }

        if (score > bestScore && score >= 40.0) {
          bestScore = score;
          bestEncUrl = encUrl;
        }
      }

      // Do not fall back to results.first if no candidate met quality/cleanliness threshold
      final selectedEncUrl = bestEncUrl;
      if (selectedEncUrl == null || selectedEncUrl.isEmpty) return null;

      final authUri = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=song.generateAuthToken&url=${Uri.encodeComponent(selectedEncUrl)}&bitrate=320&api_version=4&_format=json&ctx=android&_marker=0',
      );
      final authRes = await _client.get(authUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
      }).timeout(const Duration(seconds: 6));
      if (authRes.statusCode != 200) return null;

      final authData = jsonDecode(authRes.body) as Map<String, dynamic>;
      return authData['auth_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ExternalTrackResult>> getTrending(String backend) async {
    AppLogger.trace('NativeAcquisitionService', 'getTrending', {'backend': backend});
    if (!_initialized) await initialize();
    if (_loadedExtensions[backend] == true) {
      try {
        final res = _ffi.executeCommand(backend, 'getTrending', []);
        if (res is List && res.isNotEmpty) {
          return res.map((item) {
            final map = item as Map<String, dynamic>;
            List<AudioQuality> qualities = [AudioQuality.flac16Bit];
            if (map['availableQualities'] is List) {
              qualities = (map['availableQualities'] as List).map((q) {
                switch (q.toString().toLowerCase()) {
                  case 'flac_24': return AudioQuality.flac24Bit;
                  case 'flac_16': return AudioQuality.flac16Bit;
                  case 'opus_320': return AudioQuality.opus320k;
                  default: return AudioQuality.flac16Bit;
                }
              }).toList();
            }
            
            return ExternalTrackResult(
              id: map['id']?.toString() ?? '',
              title: map['title']?.toString() ?? 'Unknown',
              artists: (map['artists'] as List?)?.map((e) => e.toString()).toList() ?? [],
              album: map['album']?.toString() ?? 'Single',
              albumArtUrl: map['albumArtUrl']?.toString(),
              durationSeconds: map['durationSeconds'] as int? ?? 180,
              backend: backend,
              availableQualities: qualities,
              isrc: map['isrc']?.toString(),
            );
          }).toList();
        }
      } catch (e) {
        debugPrint('Error getting trending for $backend: $e');
      }
    }

    // Pure-Dart multi-source chart fallback
    final directChart = await getDeezerChartDirect(limit: 30);
    if (directChart.isNotEmpty) return directChart;

    final itunesTrending = await _getItunesTrending(limit: 30);
    if (itunesTrending.isNotEmpty) return itunesTrending;

    return await _ffi.getTrending(backend);
  }

  /// Search JioSaavn directly for tracks (320kbps catalog)
  Future<List<ExternalTrackResult>> searchJioSaavnDirect(String query, {int limit = 20}) async {
    AppLogger.trace('NativeAcquisitionService', 'searchJioSaavnDirect', {'query': query, 'limit': limit});
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final uri = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getResults&q=${Uri.encodeComponent(trimmed)}&n=$limit&p=1&_format=json&_marker=0&ctx=android',
      );
      final res = await _client.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
      }).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      return results.map<ExternalTrackResult>((item) {
        final cand = item as Map<String, dynamic>;
        final candTitle = cand['title']?.toString() ?? cand['song']?.toString() ?? 'Unknown';
        final candArtist = cand['primary_artists']?.toString() ?? cand['subtitle']?.toString() ?? 'Unknown Artist';
        final moreInfo = (cand['more_info'] as Map<String, dynamic>?) ?? cand;
        final duration = int.tryParse(moreInfo['duration']?.toString() ?? '') ?? 180;
        final rawArt = cand['image']?.toString() ?? moreInfo['image']?.toString();
        final hdArt = rawArt?.replaceAll('150x150', '500x500');
        final id = cand['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        return ExternalTrackResult(
          id: id,
          title: candTitle.replaceAll('&quot;', '"').replaceAll('&#039;', "'"),
          artists: [candArtist.replaceAll('&quot;', '"').replaceAll('&#039;', "'")],
          album: moreInfo['album']?.toString() ?? 'Single',
          albumArtUrl: hdArt,
          durationSeconds: duration,
          backend: 'jiosaavn',
          availableQualities: const [AudioQuality.opus320k],
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Direct iTunes preview stream fallback (guaranteed high-availability AAC)
  Future<StreamResolution?> _resolveItunesPreviewStream(String title, String artist) async {
    AppLogger.trace('NativeAcquisitionService', '_resolveItunesPreviewStream', {'title': title, 'artist': artist});
    try {
      final query = Uri.encodeComponent('$title $artist'.trim());
      final uri = Uri.parse('https://itunes.apple.com/search?term=$query&entity=song&limit=5');
      final res = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      for (final item in results) {
        final previewUrl = item['previewUrl']?.toString();
        if (previewUrl != null && previewUrl.isNotEmpty) {
          return StreamResolution(
            streamUrl: previewUrl,
            quality: AudioQuality.opus320k,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Trending tracks from iTunes charts for empty shelves
  Future<List<ExternalTrackResult>> _getItunesTrending({int limit = 30}) async {
    AppLogger.trace('NativeAcquisitionService', '_getItunesTrending', {'limit': limit});
    try {
      final uri = Uri.parse('https://itunes.apple.com/search?term=Top+Hits&entity=song&limit=$limit');
      final res = await _client.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      return results.map<ExternalTrackResult>((item) {
        final m = item as Map<String, dynamic>;
        final rawArt = m['artworkUrl100'] as String?;
        final hdArt = rawArt?.replaceAll('100x100bb', '600x600bb');
        return ExternalTrackResult(
          id: m['trackId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          title: m['trackName']?.toString() ?? 'Unknown',
          artists: [m['artistName']?.toString() ?? 'Unknown Artist'],
          album: m['collectionName']?.toString() ?? 'Single',
          albumArtUrl: hdArt,
          durationSeconds: ((m['trackTimeMillis'] as num? ?? 180000) / 1000).round(),
          backend: 'apple',
          availableQualities: const [AudioQuality.flac16Bit, AudioQuality.opus320k],
          isrc: m['isrc']?.toString(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<AcquiredAudioFiles> acquireLosslessTrack({
    required ExternalTrackResult trackResult,
    void Function(double progress)? onProgress,
  }) async {
    AppLogger.trace('NativeAcquisitionService', 'acquireLosslessTrack', {'trackId': trackResult.id});
    final tempDir = await getTemporaryDirectory();
    final scratchDir = Directory(p.join(tempDir.path, 'cloudbeat_scratch'));
    if (!scratchDir.existsSync()) {
      scratchDir.createSync(recursive: true);
    }

    final sanitizedId = trackResult.id.replaceAll(RegExp(r'[^\w\-]'), '_');
    final flacPath = p.join(scratchDir.path, '$sanitizedId.flac');
    final opusPath = p.join(scratchDir.path, '$sanitizedId.opus');

    final flacFile = File(flacPath);
    final opusFile = File(opusPath);

    onProgress?.call(0.1);

    // Resolve direct audio stream through waterfall cascade
    final resolution = await resolveStreamUrl(
      trackId: trackResult.id,
      backend: trackResult.backend,
      requestedQuality: trackResult.availableQualities.isNotEmpty
          ? trackResult.availableQualities.first
          : AudioQuality.flac16Bit,
      title: trackResult.title,
      artist: trackResult.artists.isNotEmpty ? trackResult.artists.first : null,
      durationSeconds: trackResult.durationSeconds,
    );

    onProgress?.call(0.25);

    // Stream download audio chunks into scratch flac file
    final request = http.Request('GET', Uri.parse(resolution.streamUrl));
    if (resolution.headers.isNotEmpty) {
      request.headers.addAll(resolution.headers);
    }

    final streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode >= 400) {
      throw Exception('Failed to download audio: HTTP ${streamedResponse.statusCode}');
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    int receivedBytes = 0;
    final sink = flacFile.openWrite();

    try {
      await streamedResponse.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(0.25 + (0.70 * (receivedBytes / totalBytes)));
        }
      }).asFuture();
    } finally {
      await sink.flush();
      await sink.close();
    }

    // Mirror audio to opus scratch file for secondary format consumers
    if (flacFile.existsSync() && flacFile.lengthSync() > 0) {
      await flacFile.copy(opusFile.path);
    }

    onProgress?.call(1.0);

    final track = Track(
      id: trackResult.id,
      title: trackResult.title,
      artists: trackResult.artists,
      album: trackResult.album,
      albumArtUrl: trackResult.albumArtUrl,
      durationSeconds: trackResult.durationSeconds,
      genre: 'Soundtrack',
      isrc: trackResult.isrc,
      quality: resolution.quality,
      addedAt: DateTime.now(),
    );

    return AcquiredAudioFiles(
      track: track,
      flacFile: flacFile,
      opusFile: opusFile,
      acquiredQuality: resolution.quality,
    );
  }

  @override
  Future<void> purgeTempDirectory() async {
    AppLogger.trace('NativeAcquisitionService', 'purgeTempDirectory');
    try {
      final tempDir = await getTemporaryDirectory();
      final scratchDir = Directory(p.join(tempDir.path, 'cloudbeat_scratch'));
      if (scratchDir.existsSync()) {
        await scratchDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  @override
  Future<Map<String, bool>> checkBackendHealth() async {
    AppLogger.trace('NativeAcquisitionService', 'checkBackendHealth');
    if (!_initialized) await initialize();
    return _loadedExtensions;
  }
}
