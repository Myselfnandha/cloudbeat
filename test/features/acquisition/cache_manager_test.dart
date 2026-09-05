import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/acquisition_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/acquisition/cache_manager.dart';

class MockAcquisitionContract implements AcquisitionContract {
  bool purgeCalled = false;

  @override
  Future<void> purgeTempDirectory() async {
    purgeCalled = true;
  }

  @override
  Future<List<ExternalTrackResult>> searchAllBackends(
    String query, {
    List<String>? backends,
    int limit = 20,
  }) async => [];

  @override
  Future<List<ExternalTrackResult>> getTrending(String backend) async => [];

  @override
  Future<StreamResolution> resolveStreamUrl({
    required String trackId,
    required String backend,
    required AudioQuality requestedQuality,
  }) async => throw UnimplementedError();

  @override
  Future<AcquiredAudioFiles> acquireLosslessTrack({
    required ExternalTrackResult trackResult,
    void Function(double progress)? onProgress,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, bool>> checkBackendHealth() async => {'deezer': true};
}

void main() {
  group('Module 7: CacheManager & Periodic Maintenance Worker Tests', () {
    late Directory tempDir;
    late MockAcquisitionContract mockAcquisition;
    late CacheManager cacheManager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cloudbeat_cache_test_');
      mockAcquisition = MockAcquisitionContract();
      // Set limit to 200 bytes for deterministic LRU testing
      cacheManager = CacheManager(
        acquisition: mockAcquisition,
        cacheDirectory: tempDir,
        maxCacheBytes: 200,
      );
    });

    tearDown(() async {
      cacheManager.stopPeriodicWorker();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('runPeriodicMaintenance invokes purgeTempDirectory for orphaned temp cleanup', () async {
      expect(mockAcquisition.purgeCalled, false);
      await cacheManager.runPeriodicMaintenance();
      expect(mockAcquisition.purgeCalled, true);
    });

    test('evicts oldest accessed cache files when size exceeds maxCacheBytes', () async {
      final file1 = File('${tempDir.path}/track1.flac');
      final file2 = File('${tempDir.path}/track2.flac');
      final file3 = File('${tempDir.path}/track3.flac');

      await file1.writeAsBytes(List.filled(100, 1));
      await file2.writeAsBytes(List.filled(100, 2));
      await file3.writeAsBytes(List.filled(100, 3));

      // Register file 1 (older)
      cacheManager.registerAccess('t1', file1.path, 100);
      await Future.delayed(const Duration(milliseconds: 10));

      // Register file 2
      cacheManager.registerAccess('t2', file2.path, 100);
      await Future.delayed(const Duration(milliseconds: 10));

      // Register file 3 -> Total 300 bytes > 200 limit
      cacheManager.registerAccess('t3', file3.path, 100);

      expect(cacheManager.totalCacheSizeBytes, 300);

      final evicted = await cacheManager.evictLruIfNecessary();

      expect(evicted, 1);
      expect(cacheManager.totalCacheSizeBytes, 200);
      // File 1 was oldest, should be deleted
      expect(await file1.exists(), false);
      expect(await file2.exists(), true);
      expect(await file3.exists(), true);
    });
  });
}
