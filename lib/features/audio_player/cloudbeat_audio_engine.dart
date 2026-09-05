import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/contracts/audio_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../acquisition/ingestion_worker.dart';
import 'cloudbeat_audio_handler.dart';
import 'player_bloc.dart';

enum PauseReason {
  none,
  userInitiated,
  focusLossTransient,
  becomingNoisy,
  lossPermanent,
}

enum AudioInterruptionEvent {
  becomingNoisy,
  lossTransientCanDuck,
  lossTransient,
  lossPermanent,
  gain,
}

class CloudBeatAudioEngine implements AudioEngineContract {
  final PlayerBloc _bloc;
  final AudioPlayer _player;
  final CatalogContract? _catalog;
  final AcquisitionContract? _acquisition;
  final IngestionWorker? _ingestion;
  final CloudBeatAudioHandler? _audioHandler;

  AudioQualityMode qualityMode = AudioQualityMode.maxLossless;
  PlaybackSource activePlaybackSource = PlaybackSource.onlineWaterfall;

  final _activeQualityController = StreamController<AudioQuality>.broadcast();
  AudioQuality _currentActiveQuality = AudioQuality.flac16Bit;

  PauseReason _pauseReason = PauseReason.none;
  double _preDuckVolume = 1.0;
  bool _isDucked = false;

  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _bufferedPositionSubscription;
  StreamSubscription? _durationSubscription;

  CloudBeatAudioEngine({
    required PlayerBloc bloc,
    CatalogContract? catalog,
    AcquisitionContract? acquisition,
    IngestionWorker? ingestion,
    AudioPlayer? player,
    CloudBeatAudioHandler? audioHandler,
    this.qualityMode = AudioQualityMode.maxLossless,
  })  : _bloc = bloc,
        _catalog = catalog,
        _acquisition = acquisition,
        _ingestion = ingestion,
        _player = player ?? AudioPlayer(),
        _audioHandler = audioHandler {
    _initSubscriptions();
    _initAudioHandler();
    _initAudioSession();
  }

  void _initAudioHandler() {
    if (_audioHandler == null) return;
    _audioHandler.onPlayCallback = () => resume();
    _audioHandler.onPauseCallback = () => pause();
    _audioHandler.onStopCallback = () => stop();
    _audioHandler.onSeekCallback = (pos) => seek(pos);
    _audioHandler.onSkipToNextCallback = () => skipToNext();
    _audioHandler.onSkipToPreviousCallback = () => skipToPrevious();
  }

  void _initSubscriptions() {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      final isBuffering = state.processingState == ProcessingState.buffering;
      if (isBuffering) {
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
      } else if (state.processingState == ProcessingState.ready && !state.playing) {
        _bloc.add(InternalStatusUpdateEvent(PlaybackStatus.paused));
      }
      _syncMediaNotificationState();
    });

    _positionSubscription = _player.positionStream.listen((pos) {
      _bloc.add(InternalPositionUpdateEvent(pos));
      _syncMediaNotificationState();
    });

    _bufferedPositionSubscription = _player.bufferedPositionStream.listen((buffered) {
      _bloc.add(InternalBufferedUpdateEvent(buffered));
    });

    _durationSubscription = _player.durationStream.listen((dur) {
      if (dur != null) {
        _bloc.add(InternalDurationUpdateEvent(dur));
        _syncMediaNotificationState();
      }
    });
  }

  void _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.becomingNoisyEventStream.listen((_) {
        handleInterruption(AudioInterruptionEvent.becomingNoisy);
      });

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              handleInterruption(AudioInterruptionEvent.lossTransientCanDuck);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              handleInterruption(AudioInterruptionEvent.lossTransient);
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              handleInterruption(AudioInterruptionEvent.gain);
              break;
          }
        }
      });
    } catch (e) {
      debugPrint('AudioSession configuration skipped: $e');
    }
  }

  PauseReason get currentPauseReason => _pauseReason;
  Future<void> handleAudioInterruption(AudioInterruptionEvent event) async => handleInterruption(event);
  static AudioQuality resolveBestQuality(Track track) => track.quality;
  @override
  Future<void> play(Track track) => playTrack(track);

  @override
  Track? get currentTrack => _bloc.state.currentTrack;

  @override
  PlaybackStatus get currentStatus => _bloc.state.status;

  @override
  Duration get currentPosition => _bloc.state.position;

  @override
  List<Track> get currentQueue => _bloc.state.queue;

  @override
  Future<void> setQueue(List<Track> queue, {int initialIndex = 0}) async {
    _bloc.add(SetQueueEvent(queue, initialIndex: initialIndex));
    if (queue.isNotEmpty && initialIndex < queue.length) {
      await playTrack(queue[initialIndex]);
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
    await _player.setShuffleModeEnabled(enabled);
  }

  void handleInterruption(AudioInterruptionEvent event) {
    switch (event) {
      case AudioInterruptionEvent.becomingNoisy:
        if (_bloc.state.status == PlaybackStatus.playing) {
          _pauseReason = PauseReason.becomingNoisy;
          pause(userInitiated: false);
        }
        break;
      case AudioInterruptionEvent.lossTransientCanDuck:
        if (_bloc.state.status == PlaybackStatus.playing) {
          _isDucked = true;
          _preDuckVolume = _player.volume;
          _player.setVolume(0.2);
        }
        break;
      case AudioInterruptionEvent.lossTransient:
        if (_bloc.state.status == PlaybackStatus.playing) {
          _pauseReason = PauseReason.focusLossTransient;
          pause(userInitiated: false);
        }
        break;
      case AudioInterruptionEvent.lossPermanent:
        if (_bloc.state.status == PlaybackStatus.playing) {
          _pauseReason = PauseReason.lossPermanent;
          pause(userInitiated: false);
        }
        break;
      case AudioInterruptionEvent.gain:
        if (_isDucked) {
          _player.setVolume(_preDuckVolume);
          _isDucked = false;
        } else if (_pauseReason == PauseReason.focusLossTransient) {
          _pauseReason = PauseReason.none;
          resume();
        }
        break;
    }
  }

  void _syncMediaNotificationState() {
    if (_audioHandler == null) return;
    bool isPlaying = false;
    try {
      isPlaying = _player.playing;
    } catch (_) {
      isPlaying = _bloc.state.status == PlaybackStatus.playing;
    }
    ProcessingState processingState = ProcessingState.idle;
    try {
      processingState = _player.processingState;
    } catch (_) {}
    final isBuffering = processingState == ProcessingState.buffering || processingState == ProcessingState.loading;
    Duration position = Duration.zero;
    try {
      position = _player.position;
    } catch (_) {}
    Duration bufferedPosition = Duration.zero;
    try {
      bufferedPosition = _player.bufferedPosition;
    } catch (_) {}

    _audioHandler.updateState(
      isPlaying: isPlaying,
      position: position,
      bufferedPosition: bufferedPosition,
      isBuffering: isBuffering,
    );
  }

  Future<File?> _getCachedFile(String trackId) async {
    try {
      final docDir = await getApplicationSupportDirectory();
      final cacheFile = File(p.join(docDir.path, 'streaming_cache', '$trackId.flac'));
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 0) {
        return cacheFile;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> playTrack(Track track) async {
    final prevTrack = _bloc.state.currentTrack;
    if (prevTrack != null && prevTrack.id != track.id) {
      final currentPos = _player.position.inSeconds;
      final duration = _player.duration?.inSeconds ?? prevTrack.durationSeconds;
      final completion = duration > 0 ? (currentPos / duration).clamp(0.0, 1.0) : 0.0;
      _catalog?.recordPlaybackEvent(
        trackId: prevTrack.id,
        completionRate: completion,
        wasSkipped: completion < 0.8,
        timestamp: DateTime.now(),
      );
    }

    _bloc.add(PlayTrackEvent(track));

    _audioHandler?.updateMetadata(
      id: track.id,
      title: track.title,
      artist: track.artists.join(', '),
      album: track.album,
      duration: Duration(seconds: track.durationSeconds),
      artUri: track.albumArtUrl != null ? Uri.tryParse(track.albumArtUrl!) : null,
    );
    _bloc.add(SeekEvent(Duration.zero));

    // Tier 1: Local File (Downloaded)
    if (track.isDownloaded && track.localFilePath != null && File(track.localFilePath!).existsSync()) {
      activePlaybackSource = PlaybackSource.localFile;
      _updateActiveQuality(track.quality);
      await _player.setFilePath(track.localFilePath!, initialPosition: Duration.zero);
      await _player.play();
      return;
    }

    // Tier 2: Streaming LRU Cache
    final cachedFile = await _getCachedFile(track.id);
    if (cachedFile != null) {
      activePlaybackSource = PlaybackSource.streamingCache;
      _updateActiveQuality(track.quality);
      await _player.setFilePath(cachedFile.path, initialPosition: Duration.zero);
      await _player.play();
      return;
    }

    // Tier 3: Online Waterfall
    activePlaybackSource = PlaybackSource.onlineWaterfall;
    // Emit buffering immediately for 1-frame instant feedback
    _bloc.add(InternalStatusUpdateEvent(PlaybackStatus.buffering));

    if (_acquisition != null) {
      String backend = 'deezer';
      String realId = track.id;

      if (track.id.contains(':')) {
        final colonIndex = track.id.indexOf(':');
        backend = track.id.substring(0, colonIndex);
        realId = track.id.substring(colonIndex + 1);
      }

      AudioQuality targetQuality;
      switch (qualityMode) {
        case AudioQualityMode.maxLossless:
          targetQuality = AudioQuality.flac24Bit;
          break;
        case AudioQualityMode.cdQuality:
          targetQuality = AudioQuality.flac16Bit;
          break;
        case AudioQualityMode.dataSaver:
          targetQuality = AudioQuality.opus320k;
          break;
        case AudioQualityMode.adaptive:
          targetQuality = AudioQuality.flac16Bit;
          break;
      }

      try {
        debugPrint('[AudioEngine] Resolving stream for "${track.title}" (backend: $backend, id: $realId)...');
        final streamRes = await _acquisition.resolveStreamUrl(
          trackId: realId,
          backend: backend,
          requestedQuality: targetQuality,
          title: track.title,
          artist: track.artists.isNotEmpty ? track.artists.first : null,
        );

        debugPrint('[AudioEngine] Resolved streamUrl: ${streamRes.streamUrl} (quality: ${streamRes.quality})');
        _updateActiveQuality(streamRes.quality);
        await _player.setUrl(
          streamRes.streamUrl,
          initialPosition: Duration.zero,
          headers: streamRes.headers.isEmpty ? null : streamRes.headers,
        );
        await _player.play();
        debugPrint('[AudioEngine] Playback started successfully!');

        // Background caching
        if (_ingestion != null) {
          final extResult = ExternalTrackResult(
            id: track.id,
            title: track.title,
            artists: track.artists,
            album: track.album,
            albumArtUrl: track.albumArtUrl,
            durationSeconds: track.durationSeconds,
            backend: backend,
            availableQualities: [streamRes.quality],
            isrc: track.isrc,
          );
          _ingestion.ingestTrack(extResult).catchError((_) => track);
        }
        return;
      } catch (e, stack) {
        debugPrint('[AudioEngine] Stream resolution/playback failed: $e');
        debugPrint('[AudioEngine] Stack: $stack');
      }
    }
  }

  @override
  Future<void> pause({bool userInitiated = true}) async {
    if (userInitiated) {
      _pauseReason = PauseReason.userInitiated;
    }
    _bloc.add(PauseEvent());
    await _player.pause();
    _syncMediaNotificationState();
  }

  @override
  Future<void> resume() async {
    _pauseReason = PauseReason.none;
    _bloc.add(ResumeEvent());
    await _player.play();
    _syncMediaNotificationState();
  }

  @override
  Future<void> stop() async {
    _pauseReason = PauseReason.none;
    _bloc.add(StopEvent());
    await _player.stop();
    _syncMediaNotificationState();
  }

  @override
  Future<void> seek(Duration position) async {
    _bloc.add(SeekEvent(position));
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    final currentTrack = _bloc.state.currentTrack;
    if (currentTrack != null && _bloc.state.status == PlaybackStatus.playing) {
      final dur = _bloc.state.duration?.inSeconds ?? currentTrack.durationSeconds;
      final pos = _bloc.state.position.inSeconds;
      final completionRate = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
      _catalog?.recordPlaybackEvent(
        trackId: currentTrack.id,
        completionRate: completionRate,
        wasSkipped: true,
        timestamp: DateTime.now(),
      );
    }
    _bloc.add(SkipNextEvent());
    final nextTrack = _bloc.state.currentTrack;
    if (nextTrack != null) {
      await playTrack(nextTrack);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _bloc.add(SkipPreviousEvent());
    final prevTrack = _bloc.state.currentTrack;
    if (prevTrack != null) {
      await playTrack(prevTrack);
    }
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    _bloc.add(SetRepeatModeEvent(mode));
    switch (mode) {
      case RepeatMode.off:
        await _player.setLoopMode(LoopMode.off);
        break;
      case RepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
        break;
      case RepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
    }
  }

  Future<void> toggleShuffle() async {
    _bloc.add(ToggleShuffleEvent());
    await _player.setShuffleModeEnabled(!_bloc.state.isShuffle);
  }

  @override
  Stream<PlaybackStatus> get statusStream => _bloc.stream.map((s) => s.status).distinct();

  @override
  Stream<Track?> get currentTrackStream => _bloc.stream.map((s) => s.currentTrack).distinct();

  @override
  Stream<Duration> get positionStream => _bloc.stream.map((s) => s.position).distinct();

  @override
  Stream<Duration> get bufferedPositionStream => _bloc.stream.map((s) => s.bufferedPosition).distinct();

  @override
  Stream<Duration?> get durationStream => _bloc.stream.map((s) => s.duration).distinct();

  @override
  Stream<List<Track>> get queueStream => _bloc.stream.map((s) => s.queue).distinct();

  @override
  Stream<bool> get shuffleModeStream => _bloc.stream.map((s) => s.isShuffle).distinct();

  @override
  Stream<RepeatMode> get repeatModeStream => _bloc.stream.map((s) => s.repeatMode).distinct();

  @override
  Stream<AudioQuality> get activeQualityStream => _activeQualityController.stream;

  @override
  AudioQuality get currentActiveQuality => _currentActiveQuality;

  void _updateActiveQuality(AudioQuality quality) {
    _currentActiveQuality = quality;
    _activeQualityController.add(quality);
  }

  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _bufferedPositionSubscription?.cancel();
    _durationSubscription?.cancel();
    _activeQualityController.close();
    _player.dispose();
  }
}
