import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';

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
  final CatalogContract _catalog;

  static const int maxPendingAutoVault = 2;

  final _queue = <IngestionTask>[];
  bool _isProcessing = false;

  int get queueLength => _queue.length;
  bool get isProcessing => _isProcessing;
  List<IngestionTask> get queue => List.unmodifiable(_queue);

  IngestionWorker({
    required AcquisitionContract acquisition,
    required CatalogContract catalog,
  })  : _acquisition = acquisition,
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

  /// Queue a track for download and local catalog ingestion.
  /// Deduplicates against currently pending tasks, promotes auto-caching to explicit if requested,
  /// and caps unstarted auto-cache tasks to avoid disk churn.
  Future<Track> ingestTrack(ExternalTrackResult trackResult, {bool isAutoVault = false}) {
    // Check if task is already in unstarted queue
    final existingIndex = _queue.indexWhere((t) => t.trackResult.id == trackResult.id);
    if (existingIndex != -1) {
      final existingTask = _queue[existingIndex];
      if (existingTask.isAutoVault && !isAutoVault) {
        existingTask.isAutoVault = false;
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
      final autoTasks = _queue.where((t) => t.isAutoVault).toList();
      if (autoTasks.length >= maxPendingAutoVault) {
        final oldestAuto = autoTasks.first;
        _queue.remove(oldestAuto);
        if (!oldestAuto.completer.isCompleted) {
          oldestAuto.completer.completeError(
            Exception('Auto-cache task for ${oldestAuto.trackResult.id} evicted due to queue cap'),
          );
        }
      }
      _queue.add(task);
    } else {
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

      // Step 2: Save to local documents downloads directory
      String? localPath;
      try {
        Directory baseDir;
        try {
          baseDir = await getApplicationDocumentsDirectory();
        } catch (_) {
          baseDir = Directory.systemTemp;
        }
        final downloadsDir = Directory(p.join(baseDir.path, 'downloads'));
        if (!downloadsDir.existsSync()) downloadsDir.createSync(recursive: true);
        final sanitized = task.trackResult.id.replaceAll(RegExp(r'[^\w\-]'), '_');
        final dest = p.join(downloadsDir.path, '$sanitized.flac');
        await payload.flacFile.copy(dest);
        localPath = dest;
      } catch (_) {}

      final localTrack = payload.track.copyWith(
        isDownloaded: localPath != null,
        localFilePath: localPath,
      );

      // Step 3: Record into local SQLite catalog
      await _catalog.upsertTracks([localTrack]);

      // Step 4: Guaranteed cleanup of scratch files
      await payload.cleanup();
      task.completer.complete(localTrack);
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
