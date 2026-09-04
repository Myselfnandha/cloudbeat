import 'models.dart';

abstract class AudioEngineContract {
  // Playback Transport Controls
  Future<void> play(Track track);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);

  // Queue & Playback Order
  Future<void> setQueue(List<Track> queue, {int initialIndex = 0});
  Future<void> appendToQueue(Track track);
  Future<void> playNext(Track track);
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> removeQueueItem(int index);
  Future<void> reorderQueue(int oldIndex, int newIndex);
  Future<void> setShuffleMode(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);

  // Reactive State Streams
  Stream<PlaybackStatus> get statusStream;
  Stream<Track?> get currentTrackStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<Duration?> get durationStream;
  Stream<List<Track>> get queueStream;
  Stream<bool> get shuffleModeStream;
  Stream<RepeatMode> get repeatModeStream;

  // Synchronous State Getters
  PlaybackStatus get currentStatus;
  Track? get currentTrack;
  Duration get currentPosition;
  List<Track> get currentQueue;
}
