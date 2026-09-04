import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/ffi/acquisition_ffi.dart';
import 'package:cloudbeat/features/telegram_vault/telegram_vault_service.dart';
import 'package:cloudbeat/features/audio_player/player_bloc.dart';

void main() {
  HttpOverrides.global = null;

  group('End-to-End Headless Smoke Test', () {
    late AcquisitionFfiBridge acquisitionBridge;
    late TelegramVaultService mockVault;
    late PlayerBloc playerBloc;

    setUp(() {
      acquisitionBridge = AcquisitionFfiBridge.instance(
        customLibPath: 'go_core/libcloudbeat_core.so',
      );
      mockVault = TelegramVaultService();
      playerBloc = PlayerBloc();
    });

    tearDown(() async {
      await playerBloc.close();
    });

    test('E2E pipeline: search query -> resolve stream -> mock chunk receipt -> audio initialization', () async {
      // 1. Execute search query via acquisition engine
      final results = await acquisitionBridge.searchAllBackends('Daft Punk', limit: 3);
      expect(results, isNotEmpty);
      final firstTrack = results.first;
      expect(firstTrack.title, isNotEmpty);
      expect(firstTrack.artists, isNotEmpty);

      // 2. Resolve stream URL
      final resolution = await acquisitionBridge.resolveStreamUrl(
        trackId: firstTrack.id,
        backend: firstTrack.backend,
        requestedQuality: AudioQuality.flac16Bit,
      );
      expect(resolution.streamUrl, isNotEmpty);

      // 3. Mock TDLib chunk receipt
      final chunkBytes = await mockVault.streamChunk(
        fileId: 'mock_file_123',
        offset: 0,
        length: 4096,
      );
      expect(chunkBytes.length, 4096);

      // 4. Assert audio state machine handles track playback
      final playTrack = Track(
        id: firstTrack.id,
        title: firstTrack.title,
        artists: firstTrack.artists,
        album: firstTrack.album,
        albumArtUrl: firstTrack.albumArtUrl,
        durationSeconds: firstTrack.durationSeconds,
        isrc: resolution.streamUrl,
        flacFileId: 'mock_file_123',
        addedAt: DateTime.now(),
      );

      playerBloc.add(PlayTrackEvent(playTrack));
      await expectLater(
        playerBloc.stream,
        emitsThrough(predicate<PlayerState>((state) =>
            state.status == PlaybackStatus.playing && state.currentTrack?.id == playTrack.id)),
      );
    });
  });
}
