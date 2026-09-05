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
  final List<String> _supportedBackends = ['qobuz', 'tidal', 'deezer', 'spotify', 'apple', 'amazon'];
  
  final String _extensionBaseUrl = 'https://raw.githubusercontent.com/spotiflacapp/spotiflac-extension/main/dist';
  
  bool _initialized = false;
  final Map<String, bool> _loadedExtensions = {};

  NativeAcquisitionService(this._ffi);

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
          
          final manifestRes = await http.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 5));
          final scriptRes = await http.get(Uri.parse(scriptUrl)).timeout(const Duration(seconds: 5));
          
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
    
    // Fallback to FFI bridge search if extensions return empty (e.g. unit test environment)
    if (results.isEmpty) {
      final fallbackResults = await _ffi.searchAllBackends(query, limit: limit);
      return fallbackResults;
    }
    
    return results.take(limit).toList();
  }

  @override
  Future<StreamResolution> resolveStreamUrl({
    required String trackId,
    required String backend,
    required AudioQuality requestedQuality,
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
        final res = _ffi.executeCommand(currentBackend, 'resolveStreamUrl', [trackId, qualityStr]);
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

    // Default fallback to FFI bridge resolver
    return await _ffi.resolveStreamUrl(
      trackId: trackId,
      backend: backend,
      requestedQuality: requestedQuality,
    );
  }

  @override
  Future<List<ExternalTrackResult>> getTrending(String backend) async {
    if (!_initialized) await initialize();
    if (_loadedExtensions[backend] != true) {
      return await _ffi.getTrending(backend);
    }
    
    try {
      final res = _ffi.executeCommand(backend, 'getTrending', []);
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
      debugPrint('Error getting trending for $backend: $e');
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
