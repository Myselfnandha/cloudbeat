import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import '../../core/contracts/audio_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/contracts/vault_contract.dart';
import 'player_bloc.dart';
import 'telegram_stream_audio_source.dart';

class CloudBeatAudioEngine implements AudioEngineContract {
  final PlayerBloc _bloc;
  final AudioPlayer _player;
  final VaultContract _vault;
  final CatalogContract? _catalog;

  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _bufferedPositionSubscription;
  StreamSubscription? _durationSubscription;

  CloudBeatAudioEngine({
    required PlayerBloc bloc,
    required VaultContract vault,
    CatalogContract? catalog,
    AudioPlayer? player,
  })  : _bloc = bloc,
        _vault = vault,
        _catalog = catalog,
        _player = player ?? AudioPlayer() {
    _initSubscriptions();
  }

  void _initSubscriptions() {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.buffering) {
        _bloc.add(InternalStatusUpdateEvent(PlaybackStatus.buffering));
      } else if (state.processingState == ProcessingState.completed) {
        final finishedTrack = _bloc.state.currentTrack;
        if (finishedTrack != null) {
          _catalog?.recordPlaybackEvent(
            trackId: finishedTrack.id,
            completionRate: 1.0,
            wasSkipped: false,
            timestamp: DateTime.now(),
          );
        }
        _bloc.add(SkipNextEvent());
      } else if (state.playing) {
        _bloc.add(InternalStatusUpdateEvent(PlaybackStatus.playing));
      } else {
        _bloc.add(InternalStatusUpdateEvent(PlaybackStatus.paused));
      }
    });

    _positionSubscription = _player.positionStream.listen((pos) {
      _bloc.add(InternalPositionUpdateEvent(pos));
    });
  }

  @override
  Future<void> play(Track track) async {
    _bloc.add(PlayTrackEvent(track));

    final sourceIdentifier = track.opusFileId ?? track.flacFileId;

    try {
      if (sourceIdentifier != null) {
        if (sourceIdentifier.startsWith('http://') || sourceIdentifier.startsWith('https://')) {
          await _player.setUrl(sourceIdentifier);
          await _player.play();
          return;
        } else if (File(sourceIdentifier).existsSync()) {
          await _player.setFilePath(sourceIdentifier);
          await _player.play();
          return;
        }
      }

      // Telegram MTProto or stream fallback
      if (sourceIdentifier != null) {
        final source = TelegramStreamAudioSource(
          fileId: sourceIdentifier,
          totalBytes: 5 * 1024 * 1024,
          vault: _vault,
        );
        await _player.setAudioSource(source);
        await _player.play();
      }
    } catch (_) {
      // Audio engine fallback
    }
  }

  @override
  Future<void> pause() async {
    _bloc.add(PauseEvent());
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    _bloc.add(ResumeEvent());
    await _player.play();
  }

  @override
  Future<void> stop() async {
    _bloc.add(StopEvent());
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _bloc.add(SeekEvent(position));
    await _player.seek(position);
  }

  @override
  Future<void> setQueue(List<Track> queue, {int initialIndex = 0}) async {
    _bloc.add(SetQueueEvent(queue, initialIndex: initialIndex));
    if (queue.isNotEmpty && initialIndex < queue.length) {
      await play(queue[initialIndex]);
    }
  }

  @override
  Future<void> appendToQueue(Track track) async {
    _bloc.add(AppendQueueEvent(track));
  }

  @override
  Future<void> playNext(Track track) async {
    _bloc.add(PlayNextEvent(track));
  }

  @override
  Future<void> skipToNext() async {
    final prevTrack = _bloc.state.currentTrack;
    if (prevTrack != null && _bloc.state.duration != null && _bloc.state.duration!.inMilliseconds > 0) {
      final rate = _bloc.state.position.inMilliseconds / _bloc.state.duration!.inMilliseconds;
      _catalog?.recordPlaybackEvent(
        trackId: prevTrack.id,
        completionRate: rate.clamp(0.0, 1.0),
        wasSkipped: true,
        timestamp: DateTime.now(),
      );
    }
    _bloc.add(SkipNextEvent());
    final current = _bloc.state.currentTrack;
    if (current != null) {
      await play(current);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _bloc.add(SkipPreviousEvent());
    final current = _bloc.state.currentTrack;
    if (current != null) {
      await play(current);
    }
  }

  @override
  Future<void> removeQueueItem(int index) async {
    _bloc.add(RemoveQueueItemEvent(index));
  }

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    _bloc.add(ReorderQueueEvent(oldIndex, newIndex));
  }

  @override
  Future<void> setShuffleMode(bool enabled) async {
    _bloc.add(SetShuffleEvent(enabled));
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    _bloc.add(SetRepeatEvent(mode));
  }

  // --- Reactive Streams (Bridged from PlayerBloc state stream) ---
  @override
  Stream<PlaybackStatus> get statusStream =>
      _bloc.stream.map((s) => s.status).distinct();

  @override
  Stream<Track?> get currentTrackStream =>
      _bloc.stream.map((s) => s.currentTrack).distinct();

  @override
  Stream<Duration> get positionStream =>
      _bloc.stream.map((s) => s.position).distinct();

  @override
  Stream<Duration> get bufferedPositionStream =>
      _bloc.stream.map((s) => s.bufferedPosition).distinct();

  @override
  Stream<Duration?> get durationStream =>
      _bloc.stream.map((s) => s.duration).distinct();

  @override
  Stream<List<Track>> get queueStream =>
      _bloc.stream.map((s) => s.queue).distinct();

  @override
  Stream<bool> get shuffleModeStream =>
      _bloc.stream.map((s) => s.isShuffle).distinct();

  @override
  Stream<RepeatMode> get repeatModeStream =>
      _bloc.stream.map((s) => s.repeatMode).distinct();

  // --- Synchronous Getters ---
  @override
  PlaybackStatus get currentStatus => _bloc.state.status;

  @override
  Track? get currentTrack => _bloc.state.currentTrack;

  @override
  Duration get currentPosition => _bloc.state.position;

  @override
  List<Track> get currentQueue => _bloc.state.queue;

  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _bufferedPositionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
  }
}
