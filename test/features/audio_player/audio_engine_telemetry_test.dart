import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/catalog_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/contracts/vault_contract.dart';
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
}

class MockVaultContract implements VaultContract {
  @override
  Stream<VaultAuthState> get authStateStream => const Stream.empty();
  @override
  VaultAuthState get currentAuthState => VaultAuthState.authenticated;
  @override
  Future<void> sendPhoneNumber(String phoneNumber) async {}
  @override
  Future<void> sendAuthCode(String code) async {}
  @override
  Future<void> sendPassword(String password) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<Uint8List> streamChunk({required String fileId, required int offset, required int length}) async => Uint8List(0);
  @override
  Future<Track> uploadTrackFiles({required Track track, required File flacFile, required File opusFile, void Function(double progress)? onProgress}) async => track;
  @override
  Future<List<Track>> downloadMasterManifest() async => [];
  @override
  Future<void> publishMasterManifest(List<Track> catalog) async {}
  @override
  Future<int> getOrCreateDecadeSupergroup(int year) async => -100123456789;
  @override
  Future<int> getOrCreateGenreTopic(int supergroupId, String genreOrLanguage) async => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 4: Audio Engine Telemetry Integration Tests', () {
    late PlayerBloc bloc;
    late MockCatalogContract mockCatalog;
    late MockVaultContract mockVault;
    late CloudBeatAudioEngine audioEngine;
    late Track testTrack;

    setUp(() {
      bloc = PlayerBloc();
      mockCatalog = MockCatalogContract();
      mockVault = MockVaultContract();
      audioEngine = CloudBeatAudioEngine(
        bloc: bloc,
        vault: mockVault,
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
