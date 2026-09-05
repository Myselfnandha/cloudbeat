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
import 'package:shared_preferences/shared_preferences.dart';

class NativeAcquisitionService implements AcquisitionContract {
  final AcquisitionFfiBridge _ffi;
  final http.Client _client;
  final List<String> _supportedBackends = ['qobuz', 'tidal', 'deezer', 'spotify', 'apple', 'amazon'];
  
  final String _extensionBaseUrl = 'https://raw.githubusercontent.com/spotiflacapp/spotiflac-extension/main/dist';
  
  bool _initialized = false;
  final Map<String, bool> _loadedExtensions = {};

  NativeAcquisitionService(this._ffi, {http.Client? client}) : _client = client ?? http.Client();

  Future<void> initialize() async {
    if (_initialized) return;
    
    // Step 1: Load bundled local extensions immediately (works offline & on cold start)
    for (final backend in _supportedBackends) {
      await _loadBundledExtension(backend);
    }
    _initialized = true;

    // Step 2: Fire-and-forget background check for remote updates
    _checkRemoteUpdatesInBackground();
  }

  Future<void> _loadBundledExtension(String backend) async {
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
    
    // Pure-Dart Deezer search fallback (strictly scoped to deezer per grill-me decision)
    if (results.isEmpty) {
      final deezerFallback = await searchDeezerDirect(query, limit: limit);
      if (deezerFallback.isNotEmpty) {
        return deezerFallback;
      }
      final fallbackResults = await _ffi.searchAllBackends(query, limit: limit);
      return fallbackResults;
    }
    
    return results.take(limit).toList();
  }

  /// Direct Pure-Dart Deezer search via public REST API (fallback when native FFI is uninitialized)
  Future<List<ExternalTrackResult>> searchDeezerDirect(String query, {int limit = 20}) async {
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
  }) async {
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

      if (_loadedExtensions[currentBackend] != true) continue;

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

    // Direct 320k stream resolution when title is provided
    if (title != null && title.isNotEmpty) {
      final directStream = await _resolveDirectMediaStream(title, artist ?? '');
      if (directStream != null) {
        return StreamResolution(
          streamUrl: directStream,
          quality: AudioQuality.opus320k,
        );
      }
    }

    // If native FFI engine is not loaded on this platform/ABI, throw explicit exception
    if (!_ffi.isNativeLoaded) {
      throw const NativeEngineUnavailableException(
        'Hi-Res streaming unavailable — native engine not loaded',
      );
    }

    // Default fallback to FFI bridge resolver if native is loaded
    return await _ffi.resolveStreamUrl(
      trackId: effectiveTrackId,
      backend: backend,
      requestedQuality: requestedQuality,
      title: title,
      artist: artist,
    );
  }

  Future<String?> _resolveDirectMediaStream(String title, String artist) async {
    try {
      final query = Uri.encodeComponent('$title $artist'.trim());
      final searchUri = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getResults&q=$query&n=3&p=1&_format=json&_marker=0&ctx=android',
      );
      final searchRes = await _client.get(searchUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
      }).timeout(const Duration(seconds: 5));
      if (searchRes.statusCode != 200) return null;

      final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final results = searchData['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      final encUrl = first['encrypted_media_url'] as String?;
      if (encUrl == null || encUrl.isEmpty) return null;

      final authUri = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=song.generateAuthToken&url=${Uri.encodeComponent(encUrl)}&bitrate=320&api_version=4&_format=json&ctx=android&_marker=0',
      );
      final authRes = await _client.get(authUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
      }).timeout(const Duration(seconds: 5));
      if (authRes.statusCode != 200) return null;

      final authData = jsonDecode(authRes.body) as Map<String, dynamic>;
      return authData['auth_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ExternalTrackResult>> getTrending(String backend) async {
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

    // Pure-Dart Deezer chart fallback (strictly scoped to deezer per grill-me decision)
    if (backend == 'deezer' || backend.isEmpty || backend == 'all') {
      final directChart = await getDeezerChartDirect(limit: 30);
      if (directChart.isNotEmpty) return directChart;
    }

    return await _ffi.getTrending(backend);
  }

  @override
  Future<AcquiredAudioFiles> acquireLosslessTrack({
    required ExternalTrackResult trackResult,
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final scratchDir = Directory(p.join(tempDir.path, 'cloudbeat_scratch'));
    if (!scratchDir.existsSync()) {
      scratchDir.createSync(recursive: true);
    }

    final flacPath = p.join(scratchDir.path, '${trackResult.id}.flac');
    final opusPath = p.join(scratchDir.path, '${trackResult.id}.opus');

    final flacFile = File(flacPath);
    final opusFile = File(opusPath);

    await flacFile.writeAsString('CLOUDBEAT_FLAC_RAW_${trackResult.id}');
    await opusFile.writeAsString('CLOUDBEAT_OPUS_320K_${trackResult.id}');

    final track = Track(
      id: trackResult.id,
      title: trackResult.title,
      artists: trackResult.artists,
      album: trackResult.album,
      albumArtUrl: trackResult.albumArtUrl,
      durationSeconds: trackResult.durationSeconds,
      genre: 'Soundtrack',
      isrc: trackResult.isrc,
      quality: trackResult.availableQualities.isNotEmpty
          ? trackResult.availableQualities.first
          : AudioQuality.flac16Bit,
      addedAt: DateTime.now(),
    );

    return AcquiredAudioFiles(
      track: track,
      flacFile: flacFile,
      opusFile: opusFile,
      acquiredQuality: track.quality,
    );
  }

  @override
  Future<void> purgeTempDirectory() async {
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
    if (!_initialized) await initialize();
    return _loadedExtensions;
  }
}
