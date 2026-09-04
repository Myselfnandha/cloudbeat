import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/ffi/acquisition_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NativeAcquisitionService implements AcquisitionContract {
  final AcquisitionFfiBridge _ffi;
  final List<String> _supportedBackends = ['deezer', 'qobuz', 'tidal', 'amazon', 'ytmusic'];
  
  // Extension GitHub URL
  final String _extensionBaseUrl = 'https://raw.githubusercontent.com/spotiflacapp/spotiflac-extension/main/dist';
  
  bool _initialized = false;
  Map<String, bool> _loadedExtensions = {};

  NativeAcquisitionService(this._ffi);

  Future<void> initialize() async {
    if (_initialized) return;
    
    // Download and load extensions
    await Future.wait(_supportedBackends.map((backend) => _loadExtension(backend)));
    _initialized = true;
  }
  
  Future<void> _loadExtension(String backend) async {
    try {
      final manifestUrl = '$_extensionBaseUrl/$backend/manifest.json';
      final scriptUrl = '$_extensionBaseUrl/$backend/index.js';
      
      final manifestRes = await http.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 10));
      final scriptRes = await http.get(Uri.parse(scriptUrl)).timeout(const Duration(seconds: 10));
      
      if (manifestRes.statusCode == 200 && scriptRes.statusCode == 200) {
        final success = _ffi.loadExtension(backend, manifestRes.body, scriptRes.body);
        _loadedExtensions[backend] = success;
      } else {
        _loadedExtensions[backend] = false;
      }
    } catch (e) {
      _loadedExtensions[backend] = false;
    }
  }

  Future<List<String>> _getWaterfallPriority() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('provider_waterfall_priority');
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    return _supportedBackends; // Default order
  }

  @override
  Future<List<ExternalTrackResult>> searchAllBackends(
    String query, {
    List<String>? backends,
    int limit = 20,
  }) async {
    if (!_initialized) await initialize();
    
    final priority = backends ?? await _getWaterfallPriority();
    
    // Gather all enabled backends
    final prefs = await SharedPreferences.getInstance();
    final activeBackends = priority.where((b) => prefs.getBool('provider_${b}_enabled') ?? true).toList();

    List<ExternalTrackResult> results = [];
    
    // We execute searches in parallel
    final futures = activeBackends.map((backend) async {
      if (_loadedExtensions[backend] != true) return <ExternalTrackResult>[];
      
      try {
        final res = _ffi.executeCommand(backend, 'search', [query]);
        if (res is List) {
          return res.map((item) {
            final map = item as Map<String, dynamic>;
            
            // Map JS result to ExternalTrackResult
            // Assuming extension returns: id, title, artists, album, durationSeconds, availableQualities
            List<AudioQuality> qualities = [AudioQuality.flac16Bit]; // default
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
        print('Error searching backend $backend: $e');
      }
      return <ExternalTrackResult>[];
    });

    final allResults = await Future.wait(futures);
    for (final res in allResults) {
      results.addAll(res);
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
    if (_loadedExtensions[backend] != true) throw Exception('Backend $backend not loaded');
    
    String qualityStr = 'FLAC_16';
    switch (requestedQuality) {
      case AudioQuality.flac24Bit: qualityStr = 'FLAC_24'; break;
      case AudioQuality.opus320k: qualityStr = 'OPUS_320'; break;
      default: qualityStr = 'FLAC_16';
    }
    
    final res = _ffi.executeCommand(backend, 'resolveStreamUrl', [trackId, qualityStr]);
    if (res is Map<String, dynamic>) {
      final streamUrl = res['streamUrl'] as String?;
      if (streamUrl == null) throw Exception('No streamUrl returned');
      
      // Decryptor key derivation integration here if required by extension logic
      return StreamResolution(
        streamUrl: streamUrl,
        quality: requestedQuality,
      );
    }
    
    throw Exception('Invalid stream resolution response from $backend');
  }

  @override
  Future<AcquiredAudioFiles> acquireLosslessTrack({
    required ExternalTrackResult trackResult,
    void Function(double progress)? onProgress,
  }) async {
    // This maintains the existing dummy implementation for background uploading tests,
    // as building a full chunked downloader and tagging pipeline is complex.
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
