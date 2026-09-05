import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/catalog_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/audio_player/cloudbeat_audio_engine.dart';
import 'package:cloudbeat/features/audio_player/player_bloc.dart';

class MockCatalogContract implements CatalogContract {
  final List<Map<String, dynamic>> recordedEvents = [];

  @override
  Future<void> recordPlaybackEvent({
    required String trackId,
    required double completionRate,
    required bool wasSkipped,
    required DateTime timestamp,
  }) async {
    recordedEvents.add({
      'trackId': trackId,
      'completionRate': completionRate,
      'wasSkipped': wasSkipped,
      'timestamp': timestamp,
    });
  }

  @override
  Future<void> upsertTracks(List<Track> tracks) async {}
  @override
  Future<List<Track>> getRecentTracks({int limit = 50}) async => [];
  @override
  Future<List<Track>> getTracksByArtist(String artist) async => [];
  @override
  Future<List<Track>> getTracksByAlbum(String album) async => [];
  @override
  Future<List<Track>> getForgottenGems({int daysUnplayed = 30, int limit = 10}) async => [];
  @override
  Future<List<Track>> searchLocalTracks(String query) async => [];

  @override
  Future<void> setCacheData(String key, String data, {Duration expiresIn = const Duration(hours: 24)}) async {}

  @override
  Future<String?> getCacheData(String key) async => null;

  @override
  Future<Map<String, double>> getGenreAffinityScores() async => {};
  @override
  Future<List<Track>> getHighAffinityTracks({int limit = 20}) async => [];
  @override
  Future<void> markTrackOfflinePinned(String trackId, bool isPinned) async {}
  @override
  Future<void> removeTrack(String trackId) async {}

  @override
  Future<UploadJob?> dequeueNextUploadJob() async => null;
  @override
  Future<void> enqueueUploadJob(UploadJob job) async {}
  @override
  Future<void> removeUploadJob(String jobId) async {}
  @override
  Future<void> updateUploadJobStatus(String jobId, String status, {bool incrementAttempts = false}) async {}
  @override
  Future<List<Track>> getFavorites() async => [];
  @override
  Future<List<Track>> getDownloadedTracks() async => [];
  @override
  Future<void> toggleFavorite(String trackId, bool isFavorite) async {}
  @override
  Future<void> setDownloadState(String trackId, {required bool isDownloaded, String? localFilePath}) async {}
  @override
  Future<void> reconcileDownloads() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 4: Audio Engine Telemetry Integration Tests', () {
    late PlayerBloc bloc;
    late MockCatalogContract mockCatalog;
    late CloudBeatAudioEngine audioEngine;
    late Track testTrack;

    setUp(() {
      bloc = PlayerBloc();
      mockCatalog = MockCatalogContract();
      audioEngine = CloudBeatAudioEngine(
        bloc: bloc,
        catalog: mockCatalog,
      );
      testTrack = Track(
        id: 'track_telemetry_1',
        title: 'Telemetry Test Song',
        artists: ['Data Stream'],
        album: 'Metrics Vault',
        durationSeconds: 200,
        addedAt: DateTime.now(),
      );
    });

    tearDown(() {
      bloc.close();
    });

    test('records telemetry with wasSkipped=true when skipping a playing track', () async {
      // Simulate playing track at 50% position
      bloc.emit(PlayerState(
        status: PlaybackStatus.playing,
        currentTrack: testTrack,
        position: const Duration(seconds: 100),
        duration: const Duration(seconds: 200),
        queue: [testTrack],
      ));

      await audioEngine.skipToNext();

      expect(mockCatalog.recordedEvents.length, 1);
      final event = mockCatalog.recordedEvents.first;
      expect(event['trackId'], 'track_telemetry_1');
      expect(event['wasSkipped'], true);
      expect(event['completionRate'], 0.5);
    });
  });
}
