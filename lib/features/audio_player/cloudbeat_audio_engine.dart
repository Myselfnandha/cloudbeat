import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/contracts/audio_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/contracts/vault_contract.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../acquisition/ingestion_worker.dart';
import 'cloudbeat_audio_handler.dart';
import 'player_bloc.dart';
import 'telegram_stream_audio_source.dart';

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
  final VaultContract _vault;
  final CatalogContract? _catalog;
  final AcquisitionContract? _acquisition;
  final IngestionWorker? _ingestion;
  final CloudBeatAudioHandler? _audioHandler;

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
    required VaultContract vault,
    CatalogContract? catalog,
    AcquisitionContract? acquisition,
    IngestionWorker? ingestion,
    AudioPlayer? player,
    CloudBeatAudioHandler? audioHandler,
  })  : _bloc = bloc,
        _vault = vault,
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
      } else {
        _bloc.add(InternalStatusUpdateEvent(PlaybackStatus.paused));
      }

      _syncMediaNotificationState(isBuffering: isBuffering);
    });

    _positionSubscription = _player.positionStream.listen((pos) {
      _bloc.add(InternalPositionUpdateEvent(pos));
      _syncMediaNotificationState();
    });

    _bufferedPositionSubscription = _player.bufferedPositionStream.listen((bPos) {
      _bloc.add(InternalBufferedUpdateEvent(bPos));
      _syncMediaNotificationState();
    });
  }

  void _syncMediaNotificationState({bool isBuffering = false}) {
    final isPlaying = _bloc.state.status == PlaybackStatus.playing;
    _audioHandler?.updateState(
      isPlaying: isPlaying,
      position: _player.position,
      bufferedPosition: _player.bufferedPosition,
      isBuffering: isBuffering,
    );
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              handleAudioInterruption(AudioInterruptionEvent.lossTransientCanDuck);
              break;
            case AudioInterruptionType.pause:
              handleAudioInterruption(AudioInterruptionEvent.lossTransient);
              break;
            case AudioInterruptionType.unknown:
              handleAudioInterruption(AudioInterruptionEvent.lossPermanent);
              break;
          }
        } else {
          handleAudioInterruption(AudioInterruptionEvent.gain);
        }
      });
      session.becomingNoisyEventStream.listen((_) {
        handleAudioInterruption(AudioInterruptionEvent.becomingNoisy);
      });
    } catch (e) {
      debugPrint('AudioSession init error: $e');
    }
  }

  // --- Audio Focus Policy ---
  PauseReason get currentPauseReason => _pauseReason;

  Future<void> handleAudioInterruption(AudioInterruptionEvent event) async {
    switch (event) {
      case AudioInterruptionEvent.becomingNoisy:
        _pauseReason = PauseReason.becomingNoisy;
        await pause(userInitiated: false);
        break;

      case AudioInterruptionEvent.lossTransientCanDuck:
        if (_bloc.state.status == PlaybackStatus.playing) {
          _isDucked = true;
          _preDuckVolume = _player.volume;
          await _player.setVolume(0.2); // Duck volume to 20% (-14dB)
        }
        break;

      case AudioInterruptionEvent.lossTransient:
        if (_bloc.state.status == PlaybackStatus.playing) {
          _pauseReason = PauseReason.focusLossTransient;
          await pause(userInitiated: false);
        }
        break;

      case AudioInterruptionEvent.lossPermanent:
        _pauseReason = PauseReason.lossPermanent;
        await pause(userInitiated: false);
        break;

      case AudioInterruptionEvent.gain:
        if (_isDucked) {
          _isDucked = false;
          await _player.setVolume(_preDuckVolume);
        }
        // Strict auto-resume condition: ONLY if user did not manually pause during interruption!
        if (_pauseReason == PauseReason.focusLossTransient) {
          _pauseReason = PauseReason.none;
          await resume();
        }
        break;
    }
  }

  // --- Adaptive Audiophile Quality Resolution ---
  static AudioQuality resolveBestQuality(Track track) {
    if (track.quality == AudioQuality.flac24Bit) {
      return AudioQuality.flac24Bit;
    }
    if (track.flacFileId != null && track.flacFileId!.isNotEmpty) {
      return AudioQuality.flac16Bit;
    }
    if ((track.opusFileId != null && track.opusFileId!.isNotEmpty) ||
        track.quality == AudioQuality.opus320k) {
      return AudioQuality.opus320k;
    }
    return track.quality;
  }

  AudioQuality _resolveBestQuality(Track track) => resolveBestQuality(track);

  void _updateActiveQuality(AudioQuality quality) {
    _currentActiveQuality = quality;
    _activeQualityController.add(quality);
  }

  @override
  Future<void> play(Track track) async {
    _pauseReason = PauseReason.none;
    _bloc.add(PlayTrackEvent(track));

    // Update MediaSession metadata
    _audioHandler?.updateMetadata(
      id: track.id,
      title: track.title,
      artist: track.artists.join(', '),
      album: track.album,
      duration: Duration(seconds: track.durationSeconds),
      artUri: track.albumArtUrl != null ? Uri.tryParse(track.albumArtUrl!) : null,
    );

    // Resolve highest adaptive quality
    final targetQuality = _resolveBestQuality(track);
    _updateActiveQuality(targetQuality);

    // Case 1: Track available in Telegram Vault
    final vaultSourceIdentifier = track.opusFileId ?? track.flacFileId;

    try {
      if (vaultSourceIdentifier != null && !track.id.contains(':')) {
        if (vaultSourceIdentifier.startsWith('http://') || vaultSourceIdentifier.startsWith('https://')) {
          await _player.setUrl(vaultSourceIdentifier);
          await _player.play();
          return;
        } else if (File(vaultSourceIdentifier).existsSync()) {
          await _player.setFilePath(vaultSourceIdentifier);
          await _player.play();
          return;
        } else {
          final isFlac = track.flacFileId != null && track.flacFileId == vaultSourceIdentifier;
          final source = TelegramStreamAudioSource(
            fileId: vaultSourceIdentifier,
            totalBytes: isFlac ? 25 * 1024 * 1024 : 5 * 1024 * 1024,
            vault: _vault,
            contentType: isFlac ? 'audio/flac' : 'audio/ogg',
          );
          _updateActiveQuality(isFlac ? AudioQuality.flac16Bit : AudioQuality.opus320k);
          await _player.setAudioSource(source);
          await _player.play();
          return;
        }
      }

      // Case 2: Multi-Provider Waterfall
      if (_acquisition != null) {
        String backend = 'deezer';
        String realId = track.id;

        if (track.id.contains(':')) {
          final parts = track.id.split(':');
          backend = parts[0];
          realId = parts[1];
        }

        final streamRes = await _acquisition.resolveStreamUrl(
          trackId: realId,
          backend: backend,
          requestedQuality: targetQuality,
        );

        _updateActiveQuality(streamRes.quality);

        await _player.setUrl(streamRes.streamUrl, headers: streamRes.headers);
        await _player.play();

        // Background auto-vaulting
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

          _ingestion.ingestTrack(extResult).catchError((e) {
            debugPrint('Background ingestion failed: $e');
            return track;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Audio Engine Playback error: $e');
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
    _pauseReason = PauseReason.userInitiated;
    _bloc.add(StopEvent());
    await _player.stop();
    _syncMediaNotificationState();
  }

  @override
  Future<void> seek(Duration position) async {
    _bloc.add(SeekEvent(position));
    await _player.seek(position);
    _syncMediaNotificationState();
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

  // --- Reactive Streams ---
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

  @override
  Stream<AudioQuality> get activeQualityStream => _activeQualityController.stream;

  // --- Synchronous Getters ---
  @override
  PlaybackStatus get currentStatus => _bloc.state.status;

  @override
  Track? get currentTrack => _bloc.state.currentTrack;

  @override
  Duration get currentPosition => _bloc.state.position;

  @override
  List<Track> get currentQueue => _bloc.state.queue;

  @override
  AudioQuality get currentActiveQuality => _currentActiveQuality;

  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _bufferedPositionSubscription?.cancel();
    _durationSubscription?.cancel();
    _activeQualityController.close();
    _player.dispose();
  }
}
