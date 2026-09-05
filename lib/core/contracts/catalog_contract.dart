import 'models.dart';

abstract class CatalogContract {
  // Library Retrieval
  Future<List<Track>> getRecentTracks({int limit = 20});
  Future<List<Track>> getTracksByAlbum(String album);
  Future<List<Track>> getTracksByArtist(String artist);
  Future<List<Track>> getForgottenGems({int daysUnplayed = 30, int limit = 10});
  Future<List<Track>> searchLocalTracks(String query);
  Future<List<Track>> getFavorites();
  Future<List<Track>> getDownloadedTracks();
  Future<void> toggleFavorite(String trackId, bool isFavorite);
  Future<void> setDownloadState(String trackId, {required bool isDownloaded, String? localFilePath});
  Future<void> reconcileDownloads();

  // Telemetry & On-Device ML Features (Consumed by Module 6: Discovery)
  Future<void> recordPlaybackEvent({
    required String trackId,
    required double completionRate,
    required bool wasSkipped,
    required DateTime timestamp,
  });
  Future<Map<String, double>> getGenreAffinityScores();
  Future<List<Track>> getHighAffinityTracks({int limit = 50});

  // Persistence & Storage State
  Future<void> upsertTracks(List<Track> tracks);
  Future<void> markTrackOfflinePinned(String trackId, bool isPinned);
  Future<void> removeTrack(String trackId);

  // Caching
  Future<void> setCacheData(String key, String data, {Duration expiresIn = const Duration(hours: 24)});
  Future<String?> getCacheData(String key);

  // Queue Resilience
  Future<void> enqueueUploadJob(UploadJob job);
  Future<UploadJob?> dequeueNextUploadJob();
  Future<void> updateUploadJobStatus(String jobId, String status, {bool incrementAttempts = false});
  Future<void> removeUploadJob(String jobId);
}
