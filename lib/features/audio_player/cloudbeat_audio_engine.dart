import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/contracts/audio_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/contracts/vault_contract.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../acquisition/ingestion_worker.dart';
import 'player_bloc.dart';
import 'telegram_stream_audio_source.dart';

class CloudBeatAudioEngine implements AudioEngineContract {
  final PlayerBloc _bloc;
  final AudioPlayer _player;
  final VaultContract _vault;
  final CatalogContract? _catalog;
  final AcquisitionContract? _acquisition;
  final IngestionWorker? _ingestion;

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
  })  : _bloc = bloc,
        _vault = vault,
        _catalog = catalog,
        _acquisition = acquisition,
        _ingestion = ingestion,
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

    // Case 1: Track is available in Telegram Vault (already acquired)
    final vaultSourceIdentifier = track.opusFileId ?? track.flacFileId;

    try {
      if (vaultSourceIdentifier != null && !track.id.contains(':')) {
        // Vault tracks use standard local IDs, external tracks use provider:id format
        if (vaultSourceIdentifier.startsWith('http://') || vaultSourceIdentifier.startsWith('https://')) {
          await _player.setUrl(vaultSourceIdentifier);
          await _player.play();
          return;
        } else if (File(vaultSourceIdentifier).existsSync()) {
          await _player.setFilePath(vaultSourceIdentifier);
          await _player.play();
          return;
        } else {
          // Telegram MTProto stream
          final source = TelegramStreamAudioSource(
            fileId: vaultSourceIdentifier,
            totalBytes: 5 * 1024 * 1024,
            vault: _vault,
          );
          await _player.setAudioSource(source);
          await _player.play();
          return;
        }
      }
      
      // Case 2: Unified Provider Waterfall (External Stream)
      if (_acquisition != null) {
        // Parse backend from track.id if available, fallback to search backend mapping or 'deezer'
        String backend = 'deezer'; // Default to Zarz/Deezer FLAC
        String realId = track.id;
        
        if (track.id.contains(':')) {
          final parts = track.id.split(':');
          backend = parts[0];
          realId = parts[1];
        }

        // Full-length progressive streaming via AcquisitionContract
        final streamRes = await _acquisition.resolveStreamUrl(
          trackId: realId,
          backend: backend,
          requestedQuality: AudioQuality.flac16Bit,
        );
        
        await _player.setUrl(streamRes.streamUrl, headers: streamRes.headers);
        await _player.play();
        
        // Background FLAC upload ingestion to Telegram
        if (_ingestion != null) {
          final extResult = ExternalTrackResult(
            id: track.id,
            title: track.title,
            artists: track.artists,
            album: track.album,
            albumArtUrl: track.albumArtUrl,
            durationSeconds: track.durationSeconds,
            backend: backend,
            availableQualities: [AudioQuality.flac16Bit],
            isrc: track.isrc,
          );
          
          // Fire and forget: queues download -> decrypt -> upload -> catalog
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
