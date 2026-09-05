import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudbeat/core/contracts/acquisition_contract.dart';
import 'package:cloudbeat/core/contracts/audio_contract.dart';
import 'package:cloudbeat/core/contracts/catalog_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/providers.dart';
import 'package:cloudbeat/main.dart';

class FakeAudioEngine implements AudioEngineContract {
  @override
  PlaybackStatus get currentStatus => PlaybackStatus.idle;

  @override
  Track? get currentTrack => null;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  List<Track> get currentQueue => const [];

  @override
  Stream<PlaybackStatus> get statusStream => const Stream.empty();

  @override
  Stream<Track?> get currentTrackStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<List<Track>> get queueStream => const Stream.empty();

  @override
  Stream<bool> get shuffleModeStream => const Stream.empty();

  @override
  Stream<RepeatMode> get repeatModeStream => const Stream.empty();

  @override
  Stream<AudioQuality> get activeQualityStream => const Stream.empty();

  @override
  AudioQuality get currentActiveQuality => AudioQuality.flac16Bit;

  @override
  Future<void> play(Track track) async {}

  @override
  Future<void> playTrack(Track track) async => play(track);

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setQueue(List<Track> queue, {int initialIndex = 0}) async {}

  @override
  Future<void> appendToQueue(Track track) async {}

  @override
  Future<void> playNext(Track track) async {}

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> removeQueueItem(int index) async {}

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {}

  @override
  Future<void> setShuffleMode(bool enabled) async {}

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {}
}

class FakeCatalogContract implements CatalogContract {
  final List<Track> _tracks = [
    Track(
      id: 'test_1',
      title: 'Lossless Echoes',
      artists: ['FLAC Artists'],
      album: 'Audiophile Vault',
      durationSeconds: 215,
      addedAt: DateTime.now(),
    ),
  ];

  @override
  Future<void> upsertTracks(List<Track> tracks) async {
    _tracks.addAll(tracks);
  }

  @override
  Future<List<Track>> getRecentTracks({int limit = 50}) async => _tracks;

  @override
  Future<List<Track>> getTracksByArtist(String artist) async => _tracks;

  @override
  Future<List<Track>> getTracksByAlbum(String album) async => _tracks;

  @override
  Future<List<Track>> getForgottenGems({int daysUnplayed = 30, int limit = 10}) async => [];

  @override
  Future<List<Track>> searchLocalTracks(String query) async => _tracks;

  @override
  Future<void> setCacheData(String key, String data, {Duration expiresIn = const Duration(hours: 24)}) async {}

  @override
  Future<String?> getCacheData(String key) async => null;

  @override
  Future<void> recordPlaybackEvent({
    required String trackId,
    required double completionRate,
    required bool wasSkipped,
    required DateTime timestamp,
  }) async {}

  @override
  Future<Map<String, double>> getGenreAffinityScores() async => {'Electronic': 0.9};

  @override
  Future<List<Track>> getHighAffinityTracks({int limit = 20}) async => _tracks;

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
  Future<List<Track>> getFavorites() async => _tracks;
  @override
  Future<List<Track>> getDownloadedTracks() async => _tracks;
  @override
  Future<void> toggleFavorite(String trackId, bool isFavorite) async {}
  @override
  Future<void> setDownloadState(String trackId, {required bool isDownloaded, String? localFilePath}) async {}
  @override
  Future<void> reconcileDownloads() async {}
}

class FakeAcquisitionContract implements AcquisitionContract {
  @override
  Future<List<ExternalTrackResult>> searchAllBackends(
    String query, {
    List<String>? backends,
    int limit = 20,
  }) async {
    if (query.isEmpty) return [];
    return [
      const ExternalTrackResult(
        id: 'ext_symphony',
        title: 'Online FLAC Symphony',
        artists: ['Orchestra Masters'],
        album: 'Lossless Masters',
        durationSeconds: 300,
        backend: 'deezer',
        availableQualities: [AudioQuality.flac16Bit],
      ),
    ];
  }

  @override
  Future<List<ExternalTrackResult>> getTrending(String backend) async {
    return [
      const ExternalTrackResult(
        id: 'trending_1',
        title: 'Trending Track',
        artists: ['Trending Artist'],
        album: 'Trending Album',
        durationSeconds: 200,
        backend: 'deezer',
        availableQualities: [AudioQuality.flac16Bit],
      ),
    ];
  }

  @override
  Future<StreamResolution> resolveStreamUrl({
    required String trackId,
    required String backend,
    required AudioQuality requestedQuality,
  }) async =>
      const StreamResolution(streamUrl: 'https://stream.example.com', quality: AudioQuality.flac16Bit);

  @override
  Future<AcquiredAudioFiles> acquireLosslessTrack({
    required ExternalTrackResult trackResult,
    void Function(double progress)? onProgress,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> purgeTempDirectory() async {}

  @override
  Future<Map<String, bool>> checkBackendHealth() async => {'deezer': true};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CloudBeatApp smoke test: mounts and renders navigation tabs and search wiring', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeAudioEngine = FakeAudioEngine();
    final fakeCatalog = FakeCatalogContract();
    final fakeAcquisition = FakeAcquisitionContract();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(fakeAudioEngine),
          catalogContractProvider.overrideWithValue(fakeCatalog),
          acquisitionContractProvider.overrideWithValue(fakeAcquisition),
        ],
        child: const CloudBeatApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify app title and navigation items
    expect(find.text('CloudBeat Lossless'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Tap Search tab
    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TextField), findsOneWidget);

    // Enter search text and verify both library and online results appear
    await tester.enterText(find.byType(TextField), 'Symphony');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('IN YOUR LIBRARY'), findsOneWidget);
    expect(find.text('ONLINE RESULTS'), findsOneWidget);
    expect(find.text('Online FLAC Symphony'), findsOneWidget);

    // Tap Library tab
    await tester.tap(find.text('Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Your Library'), findsOneWidget);

    // Tap Settings tab
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('AUDIO STREAMING QUALITY'), findsOneWidget);
    expect(find.text('DOWNLOADS & STORAGE'), findsOneWidget);
  });
}
