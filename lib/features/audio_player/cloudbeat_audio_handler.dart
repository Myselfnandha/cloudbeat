import 'dart:async';
import 'package:audio_service/audio_service.dart';
import '../../core/services/app_logger.dart';

/// Android MediaSession Background Audio Handler for CloudBeat
class CloudBeatAudioHandler extends BaseAudioHandler with SeekHandler {
  Future<void> Function()? onPlayCallback;
  Future<void> Function()? onPauseCallback;
  Future<void> Function()? onStopCallback;
  Future<void> Function(Duration position)? onSeekCallback;
  Future<void> Function()? onSkipToNextCallback;
  Future<void> Function()? onSkipToPreviousCallback;

  CloudBeatAudioHandler();

  void updateMetadata({
    required String id,
    required String title,
    required String artist,
    required String album,
    Duration? duration,
    Uri? artUri,
  }) {
    AppLogger.trace('CloudBeatAudioHandler', 'updateMetadata', {'id': id, 'title': title});
    mediaItem.add(
      MediaItem(
        id: id,
        album: album,
        title: title,
        artist: artist,
        duration: duration,
        artUri: artUri,
      ),
    );
  }

  void updateState({
    required bool isPlaying,
    required Duration position,
    required Duration bufferedPosition,
    bool isBuffering = false,
  }) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isBuffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: 1.0,
        queueIndex: 0,
      ),
    );
  }

  @override
  Future<void> play() async {
    AppLogger.trace('CloudBeatAudioHandler', 'play');
    await onPlayCallback?.call();
  }

  @override
  Future<void> pause() async {
    AppLogger.trace('CloudBeatAudioHandler', 'pause');
    await onPauseCallback?.call();
  }

  @override
  Future<void> stop() async {
    AppLogger.trace('CloudBeatAudioHandler', 'stop');
    await onStopCallback?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    AppLogger.trace('CloudBeatAudioHandler', 'seek', {'positionMs': position.inMilliseconds});
    await onSeekCallback?.call(position);
  }

  @override
  Future<void> skipToNext() async {
    AppLogger.trace('CloudBeatAudioHandler', 'skipToNext');
    await onSkipToNextCallback?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    AppLogger.trace('CloudBeatAudioHandler', 'skipToPrevious');
    await onSkipToPreviousCallback?.call();
  }
}
