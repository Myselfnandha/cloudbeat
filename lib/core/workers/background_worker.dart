import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../database/app_database.dart';
import '../contracts/models.dart';
import '../ffi/acquisition_ffi.dart';
import '../../features/acquisition/native_acquisition_service.dart';

const String uploadTaskName = "com.cloudbeat.worker.uploadTask";
const String maintenanceTaskName = "com.cloudbeat.worker.maintenanceTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      AppDatabase.initializeForTesting();
      final db = AppDatabase.instance;

      if (task == maintenanceTaskName) {
        debugPrint("[MaintenanceWorker] Running periodic cleanup & reconciliation...");
        final acquisitionService = NativeAcquisitionService(AcquisitionFfiBridge.instance());
        await acquisitionService.purgeTempDirectory();
        await db.reconcileDownloads();
        debugPrint("[MaintenanceWorker] Cleanup complete.");
        return true;
      } 
      
      if (task == uploadTaskName) {
        debugPrint("[DownloadSyncWorker] Checking queue...");
        final job = await db.dequeueNextUploadJob();
        if (job == null) {
          debugPrint("[DownloadSyncWorker] No pending jobs.");
          return true;
        }

        debugPrint("[DownloadSyncWorker] Processing job: ${job.id}");
        await db.updateUploadJobStatus(job.id, 'processing');

        try {
          final trackMap = jsonDecode(job.metadataJson) as Map<String, dynamic>;
          final track = Track.fromMap(trackMap);

          final flacFile = File(job.localFilePath);
          final exists = await flacFile.exists();

          await db.setDownloadState(
            track.id,
            isDownloaded: exists,
            localFilePath: exists ? job.localFilePath : null,
          );
          await db.updateUploadJobStatus(job.id, 'completed');
          debugPrint("[DownloadSyncWorker] Job ${job.id} completed successfully.");
          return true;
        } catch (e) {
          debugPrint("[DownloadSyncWorker] Job ${job.id} failed: $e");
          await db.updateUploadJobStatus(job.id, 'failed', incrementAttempts: true);
          return false;
        }
      }

      return true;
    } catch (e, stack) {
      debugPrint('[BackgroundWorker] Fatal error: $e\n$stack');
      return false;
    }
  });
}

class BackgroundWorkerManager {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  static Future<void> registerDailyMaintenance() async {
    await Workmanager().registerPeriodicTask(
      "maintenance_task_id",
      maintenanceTaskName,
      frequency: const Duration(days: 1),
      constraints: Constraints(
        requiresBatteryNotLow: true,
      ),
    );
  }

  static Future<void> enqueueUpload(UploadJob job) async {
    final db = AppDatabase.instance;
    await db.enqueueUploadJob(job);
    
    await Workmanager().registerOneOffTask(
      "upload_\${job.id}",
      uploadTaskName,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 10),
    );
  }
}
