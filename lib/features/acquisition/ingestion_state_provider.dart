import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/models.dart';
import 'ingestion_worker.dart';

enum IngestionStatus {
  idle,
  queued,
  inProgress,
  completed,
  error,
}

class IngestionStateNotifier extends StateNotifier<Map<String, IngestionStatus>> {
  final IngestionWorker _worker;

  IngestionStateNotifier(this._worker) : super({});

  IngestionStatus getStatus(String trackId) {
    return state[trackId] ?? IngestionStatus.idle;
  }

  bool isIngesting(String trackId) {
    final status = getStatus(trackId);
    return status == IngestionStatus.queued || status == IngestionStatus.inProgress;
  }

  bool isCompleted(String trackId) {
    return getStatus(trackId) == IngestionStatus.completed;
  }

  Future<Track?> triggerIngestion(
    ExternalTrackResult extTrack, {
    bool isAutoVault = false,
  }) async {
    // If already completed or currently in flight, don't re-trigger
    if (isCompleted(extTrack.id)) return null;

    state = {
      ...state,
      extTrack.id: IngestionStatus.inProgress,
    };

    try {
      final track = await _worker.ingestTrack(extTrack, isAutoVault: isAutoVault);
      state = {
        ...state,
        extTrack.id: IngestionStatus.completed,
      };
      return track;
    } catch (_) {
      state = {
        ...state,
        extTrack.id: IngestionStatus.error,
      };
      return null;
    }
  }
}
