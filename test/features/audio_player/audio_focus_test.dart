import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/contracts/vault_contract.dart';
import 'package:cloudbeat/features/audio_player/cloudbeat_audio_engine.dart';
import 'package:cloudbeat/features/audio_player/cloudbeat_audio_handler.dart';
import 'package:cloudbeat/features/audio_player/player_bloc.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}
class MockVaultContract extends Mock implements VaultContract {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 4: Audio Focus & Interruption Policy Tests', () {
    late PlayerBloc bloc;
    late MockVaultContract mockVault;
    late MockAudioPlayer mockPlayer;
    late CloudBeatAudioHandler audioHandler;
    late CloudBeatAudioEngine audioEngine;
    late Track testTrack;

    setUp(() {
      bloc = PlayerBloc();
      mockVault = MockVaultContract();
      mockPlayer = MockAudioPlayer();
      audioHandler = CloudBeatAudioHandler();

      when(() => mockPlayer.playerStateStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayer.positionStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayer.bufferedPositionStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayer.durationStream).thenAnswer((_) => const Stream.empty());
      when(() => mockPlayer.volume).thenReturn(1.0);
      when(() => mockPlayer.position).thenReturn(Duration.zero);
      when(() => mockPlayer.bufferedPosition).thenReturn(Duration.zero);
      when(() => mockPlayer.duration).thenReturn(null);
      when(() => mockPlayer.setVolume(any())).thenAnswer((_) async {});
      when(() => mockPlayer.pause()).thenAnswer((_) async {});
      when(() => mockPlayer.play()).thenAnswer((_) async {});
      when(() => mockPlayer.stop()).thenAnswer((_) async {});
      when(() => mockPlayer.seek(any())).thenAnswer((_) async {});

      audioEngine = CloudBeatAudioEngine(
        bloc: bloc,
        vault: mockVault,
        player: mockPlayer,
        audioHandler: audioHandler,
      );

      testTrack = Track(
        id: 'test_focus_1',
        title: 'Focus Testing',
        artists: ['Audio Team'],
        album: 'Android Policy',
        durationSeconds: 180,
        addedAt: DateTime.now(),
      );
    });

    tearDown(() {
      bloc.close();
    });

    test('becomingNoisy pauses playback with becomingNoisy reason', () async {
      // Arrange: Playing state
      bloc.emit(PlayerState(status: PlaybackStatus.playing, currentTrack: testTrack));

      // Act: Headset unplugged / BT disconnected
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.becomingNoisy);
      await Future.delayed(Duration.zero);

      // Assert
      expect(audioEngine.currentPauseReason, PauseReason.becomingNoisy);
      expect(bloc.state.status, PlaybackStatus.paused);
      verify(() => mockPlayer.pause()).called(1);
    });

    test('lossTransientCanDuck ducks volume to 0.2 and gain restores it', () async {
      // Arrange: Playing state with full volume
      bloc.emit(PlayerState(status: PlaybackStatus.playing, currentTrack: testTrack));

      // Act: Nav notification chime interrupts
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.lossTransientCanDuck);

      // Assert: Ducked to 20% (-14dB)
      verify(() => mockPlayer.setVolume(0.2)).called(1);

      // Act: Chime finishes, gain focus
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.gain);

      // Assert: Volume restored to 1.0
      verify(() => mockPlayer.setVolume(1.0)).called(1);
    });

    test('lossTransient pauses on incoming call and gain auto-resumes', () async {
      // Arrange: Playing state
      bloc.emit(PlayerState(status: PlaybackStatus.playing, currentTrack: testTrack));

      // Act: Incoming phone call takes focus
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.lossTransient);
      await Future.delayed(Duration.zero);

      // Assert: Paused with focusLossTransient reason
      expect(audioEngine.currentPauseReason, PauseReason.focusLossTransient);
      expect(bloc.state.status, PlaybackStatus.paused);
      verify(() => mockPlayer.pause()).called(1);

      // Act: Phone call ends, focus gained
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.gain);
      await Future.delayed(Duration.zero);

      // Assert: Auto-resumes playback
      expect(audioEngine.currentPauseReason, PauseReason.none);
      expect(bloc.state.status, PlaybackStatus.playing);
      verify(() => mockPlayer.play()).called(1);
    });

    test('OVERLAP CRITICAL: User manual pause during phone call prevents auto-resume on call end', () async {
      // Arrange: Playing state
      bloc.emit(PlayerState(status: PlaybackStatus.playing, currentTrack: testTrack));

      // Act 1: Phone call interrupts playback
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.lossTransient);
      await Future.delayed(Duration.zero);
      expect(audioEngine.currentPauseReason, PauseReason.focusLossTransient);
      expect(bloc.state.status, PlaybackStatus.paused);

      // Act 2: User explicitly pauses during the call (e.g. via lockscreen/notification/UI)
      await audioEngine.pause(userInitiated: true);
      await Future.delayed(Duration.zero);
      expect(audioEngine.currentPauseReason, PauseReason.userInitiated);

      // Act 3: Phone call ends, audio focus is gained
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.gain);
      await Future.delayed(Duration.zero);

      // Assert: Player MUST NOT auto-resume because user deliberately paused during call!
      expect(audioEngine.currentPauseReason, PauseReason.userInitiated);
      expect(bloc.state.status, PlaybackStatus.paused);
      // verify play() was never called during gain
      verifyNever(() => mockPlayer.play());
    });

    test('OVERLAP CRITICAL: AudioHandler.pause() during phone call marks userInitiated and prevents auto-resume', () async {
      // Arrange: Playing state
      bloc.emit(PlayerState(status: PlaybackStatus.playing, currentTrack: testTrack));

      // Act 1: Phone call interrupts
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.lossTransient);
      await Future.delayed(Duration.zero);
      expect(audioEngine.currentPauseReason, PauseReason.focusLossTransient);

      // Act 2: User presses headset button or notification action triggering AudioHandler.pause()
      await audioHandler.pause();
      await Future.delayed(Duration.zero);
      expect(audioEngine.currentPauseReason, PauseReason.userInitiated);

      // Act 3: Phone call finishes
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.gain);
      await Future.delayed(Duration.zero);

      // Assert: Remains paused, no auto-resume
      expect(audioEngine.currentPauseReason, PauseReason.userInitiated);
      expect(bloc.state.status, PlaybackStatus.paused);
      verifyNever(() => mockPlayer.play());
    });

    test('lossPermanent pauses and abandons; gain does not auto-resume', () async {
      // Arrange: Playing state
      bloc.emit(PlayerState(status: PlaybackStatus.playing, currentTrack: testTrack));

      // Act: Another media player takes permanent focus
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.lossPermanent);
      await Future.delayed(Duration.zero);

      // Assert
      expect(audioEngine.currentPauseReason, PauseReason.lossPermanent);
      expect(bloc.state.status, PlaybackStatus.paused);
      verify(() => mockPlayer.pause()).called(1);

      // Act: Gain event fires later
      await audioEngine.handleAudioInterruption(AudioInterruptionEvent.gain);
      await Future.delayed(Duration.zero);

      // Assert: Still does not resume
      expect(audioEngine.currentPauseReason, PauseReason.lossPermanent);
      expect(bloc.state.status, PlaybackStatus.paused);
      verifyNever(() => mockPlayer.play());
    });
  });
}
