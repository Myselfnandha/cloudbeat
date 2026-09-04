import 'dart:async';
import 'dart:io';
import '../../core/contracts/acquisition_contract.dart';

class CacheEntry {
  final String fileId;
  final String filePath;
  final int sizeBytes;
  DateTime lastAccessed;

  CacheEntry({
    required this.fileId,
    required this.filePath,
    required this.sizeBytes,
    required this.lastAccessed,
  });
}

class CacheManager {
  final AcquisitionContract _acquisition;
  final int maxCacheBytes;
  final Directory cacheDirectory;
  final Map<String, CacheEntry> _entries = {};
  Timer? _periodicSweepTimer;

  CacheManager({
    required AcquisitionContract acquisition,
    required this.cacheDirectory,
    this.maxCacheBytes = 2 * 1024 * 1024 * 1024, // 2 GB default
  }) : _acquisition = acquisition;

  int get totalCacheSizeBytes =>
      _entries.values.fold(0, (sum, entry) => sum + entry.sizeBytes);

  int get entryCount => _entries.length;

  /// Starts the periodic worker that runs every [sweepInterval] to purge
  /// orphaned temp files and maintain LRU cache size limits.
  void startPeriodicWorker({Duration sweepInterval = const Duration(hours: 1)}) {
    _periodicSweepTimer?.cancel();
    _periodicSweepTimer = Timer.periodic(sweepInterval, (_) async {
      await runPeriodicMaintenance();
    });
  }

  void stopPeriodicWorker() {
    _periodicSweepTimer?.cancel();
    _periodicSweepTimer = null;
  }

  /// Combined maintenance sweep:
  /// 1. Runs Module 2's AcquisitionContract.purgeTempDirectory() to sweep orphaned temp files.
  /// 2. Performs LRU cache eviction if cache size exceeds maxCacheBytes.
  Future<void> runPeriodicMaintenance() async {
    // 1. Purge orphaned temp files left over from aborted downloads/crashes
    try {
      await _acquisition.purgeTempDirectory();
    } catch (_) {}

    // 2. Perform LRU eviction on audio cache
    await evictLruIfNecessary();
  }

  void registerAccess(String fileId, String filePath, int sizeBytes) {
    if (_entries.containsKey(fileId)) {
      _entries[fileId]!.lastAccessed = DateTime.now();
    } else {
      _entries[fileId] = CacheEntry(
        fileId: fileId,
        filePath: filePath,
        sizeBytes: sizeBytes,
        lastAccessed: DateTime.now(),
      );
    }
  }

  Future<int> evictLruIfNecessary() async {
    int evictedCount = 0;
    if (totalCacheSizeBytes <= maxCacheBytes) {
      return evictedCount;
    }

    // Sort entries oldest accessed first
    final sorted = _entries.values.toList()
      ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));

    for (final entry in sorted) {
      if (totalCacheSizeBytes <= maxCacheBytes) break;

      final file = File(entry.filePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      _entries.remove(entry.fileId);
      evictedCount++;
    }

    return evictedCount;
  }
}
