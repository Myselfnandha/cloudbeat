import 'dart:io';
import 'models.dart';

class ExternalTrackResult {
  final String id;
  final String title;
  final List<String> artists;
  final String album;
  final String? albumArtUrl;
  final int durationSeconds;
  final String backend; // 'spotify' | 'deezer' | 'qobuz' | 'tidal' | 'amazon' | 'ytmusic'
  final List<AudioQuality> availableQualities;
  final String? isrc;

  const ExternalTrackResult({
    required this.id,
    required this.title,
    required this.artists,
    required this.album,
    this.albumArtUrl,
    required this.durationSeconds,
    required this.backend,
    required this.availableQualities,
    this.isrc,
  });
}

class StreamResolution {
  final String streamUrl;
  final AudioQuality quality;
  final Map<String, String> headers;

  const StreamResolution({
    required this.streamUrl,
    required this.quality,
    this.headers = const {},
  });
}

class AcquiredAudioFiles {
  final Track track;
  final File flacFile;
  final File opusFile;
  final AudioQuality acquiredQuality;

  const AcquiredAudioFiles({
    required this.track,
    required this.flacFile,
    required this.opusFile,
    required this.acquiredQuality,
  });

  /// Deletes the temporary downloaded FLAC and Opus files to avoid disk leaks.
  /// Called in a `finally` block by the ingestion queue after upload success/failure.
  Future<void> cleanup() async {
    try {
      if (await flacFile.exists()) {
        await flacFile.delete();
      }
    } catch (_) {}
    try {
      if (await opusFile.exists()) {
        await opusFile.delete();
      }
    } catch (_) {}
  }
}

abstract class AcquisitionContract {
  // Search Across All Enabled Backends
  Future<List<ExternalTrackResult>> searchAllBackends(
    String query, {
    List<String>? backends,
    int limit = 20,
  });

  // Get trending/charts for a specific backend
  Future<List<ExternalTrackResult>> getTrending(String backend);

  // Instant Progressive Stream URL Resolver (via Zarz V2)
  Future<StreamResolution> resolveStreamUrl({
    required String trackId,
    required String backend,
    required AudioQuality requestedQuality,
  });

  // Full Lossless Download & Deezer Blowfish Decryption to Temp Disk Files
  Future<AcquiredAudioFiles> acquireLosslessTrack({
    required ExternalTrackResult trackResult,
    void Function(double progress)? onProgress,
  });

  // Purge any orphan temporary files in the acquisition scratch directory
  // Scheduled on app startup (Module 2) and periodic maintenance worker (Module 7)
  Future<void> purgeTempDirectory();

  // Health and Provider Session Verification
  Future<Map<String, bool>> checkBackendHealth();
}
