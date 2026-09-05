import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/audio_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/companion/companion_sync_service.dart';

class MockAudioEngine implements AudioEngineContract {
  bool resumed = false;
  bool paused = false;
  bool nextSkipped = false;

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
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    resumed = true;
  }

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
  Future<void> skipToNext() async {
    nextSkipped = true;
  }

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

void main() {
  group('Module 7: Companion Sync Service Tests', () {
    late MockAudioEngine mockAudioEngine;
    late CompanionSyncService companionService;

    setUp(() {
      mockAudioEngine = MockAudioEngine();
      companionService = CompanionSyncService(audioEngine: mockAudioEngine);
    });

    tearDown(() async {
      await companionService.stop();
    });

    test('starts companion HTTP/WebSocket server and processes remote control commands', () async {
      final port = await companionService.startCompanionHost(port: 0);
      expect(port, greaterThan(0));

      final client = await WebSocket.connect('ws://127.0.0.1:$port');
      expect(companionService.isConnected, true);

      // Send 'play' command from companion client
      client.add(jsonEncode({'command': 'play'}));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(mockAudioEngine.resumed, true);

      // Send 'pause' command
      client.add(jsonEncode({'command': 'pause'}));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(mockAudioEngine.paused, true);

      // Send 'next' command
      client.add(jsonEncode({'command': 'next'}));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(mockAudioEngine.nextSkipped, true);

      await client.close();
    });
  });
}
