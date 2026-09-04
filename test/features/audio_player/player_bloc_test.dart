import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/audio_player/player_bloc.dart';

void main() {
  group('PlayerBloc Audio State Machine Tests', () {
    late Track track1;
    late Track track2;

    setUp(() {
      track1 = Track(
        id: 't1',
        title: 'Song 1',
        artists: ['Artist 1'],
        album: 'Album 1',
        durationSeconds: 180,
        addedAt: DateTime.now(),
      );
      track2 = Track(
        id: 't2',
        title: 'Song 2',
        artists: ['Artist 2'],
        album: 'Album 2',
        durationSeconds: 240,
        addedAt: DateTime.now(),
      );
    });

    blocTest<PlayerBloc, PlayerState>(
      'emits playing state when PlayTrackEvent is added',
      build: () => PlayerBloc(),
      act: (bloc) => bloc.add(PlayTrackEvent(track1)),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlaybackStatus.playing)
            .having((s) => s.currentTrack?.id, 'currentTrack', 't1')
            .having((s) => s.duration, 'duration', const Duration(seconds: 180)),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'emits paused and playing on PauseEvent and ResumeEvent',
      build: () => PlayerBloc(),
      seed: () => PlayerState(
        status: PlaybackStatus.playing,
        currentTrack: track1,
        duration: const Duration(seconds: 180),
      ),
      act: (bloc) {
        bloc.add(PauseEvent());
        bloc.add(ResumeEvent());
      },
      expect: () => [
        isA<PlayerState>().having((s) => s.status, 'status', PlaybackStatus.paused),
        isA<PlayerState>().having((s) => s.status, 'status', PlaybackStatus.playing),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'SetQueueEvent updates queue and starts playing initial index',
      build: () => PlayerBloc(),
      act: (bloc) => bloc.add(SetQueueEvent([track1, track2], initialIndex: 1)),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.status, 'status', PlaybackStatus.playing)
            .having((s) => s.queue.length, 'queue length', 2)
            .having((s) => s.currentIndex, 'currentIndex', 1)
            .having((s) => s.currentTrack?.id, 'currentTrack', 't2'),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'SkipNextEvent advances to the next track in queue',
      build: () => PlayerBloc(),
      seed: () => PlayerState(
        status: PlaybackStatus.playing,
        queue: [track1, track2],
        currentIndex: 0,
        currentTrack: track1,
      ),
      act: (bloc) => bloc.add(SkipNextEvent()),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.currentIndex, 'currentIndex', 1)
            .having((s) => s.currentTrack?.id, 'currentTrack', 't2')
            .having((s) => s.status, 'status', PlaybackStatus.playing),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'SkipNextEvent at end of queue with RepeatMode.all loops to first track',
      build: () => PlayerBloc(),
      seed: () => PlayerState(
        status: PlaybackStatus.playing,
        queue: [track1, track2],
        currentIndex: 1,
        currentTrack: track2,
        repeatMode: RepeatMode.all,
      ),
      act: (bloc) => bloc.add(SkipNextEvent()),
      expect: () => [
        isA<PlayerState>()
            .having((s) => s.currentIndex, 'currentIndex', 0)
            .having((s) => s.currentTrack?.id, 'currentTrack', 't1')
            .having((s) => s.status, 'status', PlaybackStatus.playing),
      ],
    );

    blocTest<PlayerBloc, PlayerState>(
      'ReorderQueueEvent shifts track positions correctly',
      build: () => PlayerBloc(),
      seed: () => PlayerState(
        queue: [track1, track2],
      ),
      act: (bloc) => bloc.add(ReorderQueueEvent(0, 2)),
      expect: () => [
        isA<PlayerState>().having((s) => s.queue.first.id, 'first track', 't2'),
      ],
    );
  });
}
