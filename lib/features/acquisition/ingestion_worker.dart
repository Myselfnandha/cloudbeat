import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/contracts/vault_contract.dart';

class IngestionTask {
  final ExternalTrackResult trackResult;
  final Completer<Track> completer;
  bool isAutoVault;

  IngestionTask({
    required this.trackResult,
    required this.completer,
    this.isAutoVault = false,
  });
}

class IngestionWorker {
  final AcquisitionContract _acquisition;
  final VaultContract _vault;
  final CatalogContract _catalog;

  static const int maxPendingAutoVault = 2;

  final _queue = <IngestionTask>[];
  bool _isProcessing = false;

  int get queueLength => _queue.length;
  bool get isProcessing => _isProcessing;
  List<IngestionTask> get queue => List.unmodifiable(_queue);

  IngestionWorker({
    required AcquisitionContract acquisition,
    required VaultContract vault,
    required CatalogContract catalog,
  })  : _acquisition = acquisition,
        _vault = vault,
        _catalog = catalog {
    // Startup sweep: clean any orphaned temp files left by previous app crashes
    startupPurge();
  }

  Future<void> startupPurge() async {
    try {
      await _acquisition.purgeTempDirectory();
    } catch (e) {
      debugPrint('[IngestionWorker] Startup purge warning: $e');
    }
  }

  /// Queue a track for download, Telegram upload, and catalog ingestion.
  /// Deduplicates against currently pending tasks, promotes auto-vault to explicit if requested,
  /// and caps unstarted auto-vault tasks to avoid OOM / FloodWait.
  Future<Track> ingestTrack(ExternalTrackResult trackResult, {bool isAutoVault = false}) {
    // Check if task is already in unstarted queue
    final existingIndex = _queue.indexWhere((t) => t.trackResult.id == trackResult.id);
    if (existingIndex != -1) {
      final existingTask = _queue[existingIndex];
      // If previously queued as auto-vault and now explicitly requested by user:
      if (existingTask.isAutoVault && !isAutoVault) {
        existingTask.isAutoVault = false;
        // Promote to front of queue (or immediately after any other explicit tasks)
        _queue.removeAt(existingIndex);
        final insertIdx = _queue.lastIndexWhere((t) => !t.isAutoVault);
        _queue.insert(insertIdx == -1 ? 0 : insertIdx + 1, existingTask);
      }
      return existingTask.completer.future;
    }

    final completer = Completer<Track>();
    final task = IngestionTask(
      trackResult: trackResult,
      completer: completer,
      isAutoVault: isAutoVault,
    );

    if (isAutoVault) {
      // Throttle auto-vault tasks: cap at maxPendingAutoVault
      final autoTasks = _queue.where((t) => t.isAutoVault).toList();
      if (autoTasks.length >= maxPendingAutoVault) {
        // Evict oldest unstarted auto-vault task
        final oldestAuto = autoTasks.first;
        _queue.remove(oldestAuto);
        if (!oldestAuto.completer.isCompleted) {
          oldestAuto.completer.completeError(
            Exception('Auto-vault task for ${oldestAuto.trackResult.id} evicted due to queue cap'),
          );
        }
      }
      _queue.add(task);
    } else {
      // Prioritize explicit user tasks ahead of pending auto-vault tasks
      final insertIdx = _queue.lastIndexWhere((t) => !t.isAutoVault);
      if (insertIdx == -1) {
        _queue.insert(0, task);
      } else {
        _queue.insert(insertIdx + 1, task);
      }
    }

    _processNext();
    return completer.future;
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    final task = _queue.removeAt(0);
    AcquiredAudioFiles? payload;

    try {
      // Step 1: Download track to local temp files
      payload = await _acquisition.acquireLosslessTrack(
        trackResult: task.trackResult,
      );

      // Step 2: Upload to Telegram decade supergroup
      final uploadedTrack = await _vault.uploadTrackFiles(
        track: payload.track,
        flacFile: payload.flacFile,
        opusFile: payload.opusFile,
      );

      // Step 3: Record into local SQLite catalog
      await _catalog.upsertTracks([uploadedTrack]);

      // Step 4: Guaranteed cleanup before resolving
      await payload.cleanup();
      task.completer.complete(uploadedTrack);
    } catch (e, st) {
      debugPrint('[IngestionWorker] Ingestion failed for ${task.trackResult.id}: $e');
      if (payload != null) {
        await payload.cleanup();
      }
      task.completer.completeError(e, st);
    } finally {
      _isProcessing = false;
      _processNext();
    }
  }
}
