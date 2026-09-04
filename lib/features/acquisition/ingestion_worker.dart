import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/contracts/vault_contract.dart';

class IngestionTask {
  final ExternalTrackResult trackResult;
  final Completer<Track> completer;

  IngestionTask({
    required this.trackResult,
    required this.completer,
  });
}

class IngestionWorker {
  final AcquisitionContract _acquisition;
  final VaultContract _vault;
  final CatalogContract _catalog;

  final _queue = <IngestionTask>[];
  bool _isProcessing = false;

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
  Future<Track> ingestTrack(ExternalTrackResult trackResult) {
    final completer = Completer<Track>();
    _queue.add(IngestionTask(trackResult: trackResult, completer: completer));
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
