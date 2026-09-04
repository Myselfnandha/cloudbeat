import 'models.dart';

abstract class CatalogContract {
  // Library Retrieval
  Future<List<Track>> getRecentTracks({int limit = 20});
  Future<List<Track>> getTracksByAlbum(String album);
  Future<List<Track>> getTracksByArtist(String artist);
  Future<List<Track>> getForgottenGems({int daysUnplayed = 30, int limit = 10});
  Future<List<Track>> searchLocalTracks(String query);

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
}
