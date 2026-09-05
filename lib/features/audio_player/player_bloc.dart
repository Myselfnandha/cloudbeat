import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/contracts/models.dart';

// --- Events ---
abstract class PlayerEvent {}

class PlayTrackEvent extends PlayerEvent {
  final Track track;
  PlayTrackEvent(this.track);
}

class PauseEvent extends PlayerEvent {}

class ResumeEvent extends PlayerEvent {}

class StopEvent extends PlayerEvent {}

class SeekEvent extends PlayerEvent {
  final Duration position;
  SeekEvent(this.position);
}

class SetQueueEvent extends PlayerEvent {
  final List<Track> queue;
  final int initialIndex;
  SetQueueEvent(this.queue, {this.initialIndex = 0});
}

class AppendQueueEvent extends PlayerEvent {
  final Track track;
  AppendQueueEvent(this.track);
}

class PlayNextEvent extends PlayerEvent {
  final Track track;
  PlayNextEvent(this.track);
}

class SkipNextEvent extends PlayerEvent {}

class SkipPreviousEvent extends PlayerEvent {}

class RemoveQueueItemEvent extends PlayerEvent {
  final int index;
  RemoveQueueItemEvent(this.index);
}

class ReorderQueueEvent extends PlayerEvent {
  final int oldIndex;
  final int newIndex;
  ReorderQueueEvent(this.oldIndex, this.newIndex);
}

class SetShuffleEvent extends PlayerEvent {
  final bool enabled;
  SetShuffleEvent(this.enabled);
}

class SetRepeatEvent extends PlayerEvent {
  final RepeatMode mode;
  SetRepeatEvent(this.mode);
}

class InternalStatusUpdateEvent extends PlayerEvent {
  final PlaybackStatus status;
  InternalStatusUpdateEvent(this.status);
}

class InternalPositionUpdateEvent extends PlayerEvent {
  final Duration position;
  InternalPositionUpdateEvent(this.position);
}

class InternalBufferedUpdateEvent extends PlayerEvent {
  final Duration bufferedPosition;
  InternalBufferedUpdateEvent(this.bufferedPosition);
}

// --- State ---
class PlayerState {
  final PlaybackStatus status;
  final Track? currentTrack;
  final Duration position;
  final Duration bufferedPosition;
  final Duration? duration;
  final List<Track> queue;
  final int currentIndex;
  final bool isShuffle;
  final RepeatMode repeatMode;
  final String? errorMessage;

  const PlayerState({
    this.status = PlaybackStatus.idle,
    this.currentTrack,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.duration,
    this.queue = const [],
    this.currentIndex = 0,
    this.isShuffle = false,
    this.repeatMode = RepeatMode.off,
    this.errorMessage,
  });

  PlayerState copyWith({
    PlaybackStatus? status,
    Track? currentTrack,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    List<Track>? queue,
    int? currentIndex,
    bool? isShuffle,
    RepeatMode? repeatMode,
    String? errorMessage,
  }) {
    return PlayerState(
      status: status ?? this.status,
      currentTrack: currentTrack ?? this.currentTrack,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// --- Bloc ---
class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  PlayerBloc() : super(const PlayerState()) {
    on<PlayTrackEvent>(_onPlayTrack);
    on<PauseEvent>(_onPause);
    on<ResumeEvent>(_onResume);
    on<StopEvent>(_onStop);
    on<SeekEvent>(_onSeek);
    on<SetQueueEvent>(_onSetQueue);
    on<AppendQueueEvent>(_onAppendQueue);
    on<PlayNextEvent>(_onPlayNext);
    on<SkipNextEvent>(_onSkipNext);
    on<SkipPreviousEvent>(_onSkipPrevious);
    on<RemoveQueueItemEvent>(_onRemoveQueueItem);
    on<ReorderQueueEvent>(_onReorderQueue);
    on<SetShuffleEvent>(_onSetShuffle);
    on<SetRepeatEvent>(_onSetRepeat);
    on<InternalStatusUpdateEvent>(_onInternalStatusUpdate);
    on<InternalPositionUpdateEvent>(_onInternalPositionUpdate);
    on<InternalBufferedUpdateEvent>(_onInternalBufferedUpdate);
  }

  void _onPlayTrack(PlayTrackEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(
      status: PlaybackStatus.playing,
      currentTrack: event.track,
      position: Duration.zero,
      duration: Duration(seconds: event.track.durationSeconds),
    ));
  }

  void _onPause(PauseEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(status: PlaybackStatus.paused));
  }

  void _onResume(ResumeEvent event, Emitter<PlayerState> emit) {
    if (state.currentTrack != null) {
      emit(state.copyWith(status: PlaybackStatus.playing));
    }
  }

  void _onStop(StopEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(status: PlaybackStatus.idle, position: Duration.zero));
  }

  void _onSeek(SeekEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(position: event.position));
  }

  void _onSetQueue(SetQueueEvent event, Emitter<PlayerState> emit) {
    final track = event.queue.isNotEmpty && event.initialIndex < event.queue.length
        ? event.queue[event.initialIndex]
        : null;

    emit(state.copyWith(
      queue: List.unmodifiable(event.queue),
      currentIndex: event.initialIndex,
      currentTrack: track,
      status: track != null ? PlaybackStatus.playing : PlaybackStatus.idle,
      position: Duration.zero,
      duration: track != null ? Duration(seconds: track.durationSeconds) : null,
    ));
  }

  void _onAppendQueue(AppendQueueEvent event, Emitter<PlayerState> emit) {
    final newQueue = List<Track>.from(state.queue)..add(event.track);
    emit(state.copyWith(queue: List.unmodifiable(newQueue)));
  }

  void _onPlayNext(PlayNextEvent event, Emitter<PlayerState> emit) {
    final newQueue = List<Track>.from(state.queue);
    final nextIndex = state.currentIndex + 1;
    if (nextIndex <= newQueue.length) {
      newQueue.insert(nextIndex, event.track);
    } else {
      newQueue.add(event.track);
    }
    emit(state.copyWith(queue: List.unmodifiable(newQueue)));
  }

  void _onSkipNext(SkipNextEvent event, Emitter<PlayerState> emit) {
    if (state.queue.isEmpty) return;
    final nextIndex = state.currentIndex + 1;
    if (nextIndex < state.queue.length) {
      final track = state.queue[nextIndex];
      emit(state.copyWith(
        currentIndex: nextIndex,
        currentTrack: track,
        status: PlaybackStatus.playing,
        position: Duration.zero,
        duration: Duration(seconds: track.durationSeconds),
      ));
    } else if (state.repeatMode == RepeatMode.all) {
      final track = state.queue.first;
      emit(state.copyWith(
        currentIndex: 0,
        currentTrack: track,
        status: PlaybackStatus.playing,
        position: Duration.zero,
        duration: Duration(seconds: track.durationSeconds),
      ));
    } else {
      emit(state.copyWith(status: PlaybackStatus.completed));
    }
  }

  void _onSkipPrevious(SkipPreviousEvent event, Emitter<PlayerState> emit) {
    if (state.queue.isEmpty) return;
    final prevIndex = state.currentIndex - 1;
    if (prevIndex >= 0) {
      final track = state.queue[prevIndex];
      emit(state.copyWith(
        currentIndex: prevIndex,
        currentTrack: track,
        status: PlaybackStatus.playing,
        position: Duration.zero,
        duration: Duration(seconds: track.durationSeconds),
      ));
    } else {
      emit(state.copyWith(position: Duration.zero));
    }
  }

  void _onRemoveQueueItem(RemoveQueueItemEvent event, Emitter<PlayerState> emit) {
    if (event.index < 0 || event.index >= state.queue.length) return;
    final newQueue = List<Track>.from(state.queue)..removeAt(event.index);
    int newIndex = state.currentIndex;
    if (event.index < state.currentIndex) {
      newIndex--;
    }
    emit(state.copyWith(
      queue: List.unmodifiable(newQueue),
      currentIndex: newIndex.clamp(0, newQueue.isEmpty ? 0 : newQueue.length - 1),
    ));
  }

  void _onReorderQueue(ReorderQueueEvent event, Emitter<PlayerState> emit) {
    final newQueue = List<Track>.from(state.queue);
    int oldIndex = event.oldIndex;
    int newIndex = event.newIndex;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, item);
    emit(state.copyWith(queue: List.unmodifiable(newQueue)));
  }

  void _onSetShuffle(SetShuffleEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(isShuffle: event.enabled));
  }

  void _onSetRepeat(SetRepeatEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(repeatMode: event.mode));
  }

  void _onInternalStatusUpdate(InternalStatusUpdateEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(status: event.status));
  }

  void _onInternalPositionUpdate(InternalPositionUpdateEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(position: event.position));
  }

  void _onInternalBufferedUpdate(InternalBufferedUpdateEvent event, Emitter<PlayerState> emit) {
    emit(state.copyWith(bufferedPosition: event.bufferedPosition));
  }
}
