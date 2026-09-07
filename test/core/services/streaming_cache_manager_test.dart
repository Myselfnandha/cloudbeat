import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudbeat/core/services/streaming_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StreamingCacheManager Tests', () {
    late Directory tempDir;
    late StreamingCacheManager cacheManager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('cloudbeat_test_cache_');
      cacheManager = StreamingCacheManager(cacheDir: tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getCacheDirectory returns provided cache directory', () async {
      // Arrange & Act
      final dir = await cacheManager.getCacheDirectory();

      // Assert
      expect(dir.existsSync(), isTrue);
      expect(dir.path, tempDir.path);
    });

    test('getCacheLimitBytes default is 2GB and updates via setCacheLimitMb', () async {
      // Arrange
      final initialLimit = await cacheManager.getCacheLimitBytes();
      expect(initialLimit, 2048 * 1024 * 1024);

      // Act
      await cacheManager.setCacheLimitMb(4096);
      final updatedLimit = await cacheManager.getCacheLimitBytes();

      // Assert
      expect(updatedLimit, 4096 * 1024 * 1024);
    });

    test('cacheStream downloads audio bytes and getCachedFile retrieves it', () async {
      // Arrange
      final fakeAudioData = List<int>.generate(2048, (i) => i % 256);
      final mockClient = MockClient((request) async {
        return http.Response.bytes(fakeAudioData, 200);
      });

      final testManager = StreamingCacheManager(
        client: mockClient,
        cacheDir: tempDir,
      );

      // Act
      final cached = await testManager.cacheStream(
        trackId: 'track_123',
        streamUrl: 'https://example.com/audio.flac',
      );

      // Assert
      expect(cached, isNotNull);
      expect(cached!.existsSync(), isTrue);
      expect(cached.lengthSync(), 2048);

      final retrieved = await testManager.getCachedFile('track_123');
      expect(retrieved, isNotNull);
      expect(retrieved!.path, cached.path);
    });

    test('enforceLruEviction evicts oldest files when exceeding cache limit', () async {
      // Arrange: create two files, one older and one newer
      final fileOld = File('${tempDir.path}/track_old.flac');
      final fileNew = File('${tempDir.path}/track_new.flac');

      final dummyBytes = List<int>.filled(1024 * 1024, 42); // 1 MB each
      fileOld.writeAsBytesSync(dummyBytes);
      fileOld.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));

      fileNew.writeAsBytesSync(dummyBytes);
      fileNew.setLastModifiedSync(DateTime.now());

      // Set limit to 1 MB so total 2 MB exceeds limit
      await cacheManager.setCacheLimitMb(1);

      // Act
      await cacheManager.enforceLruEviction();

      // Assert: Old file should be evicted, new file retained
      expect(fileOld.existsSync(), isFalse);
      expect(fileNew.existsSync(), isTrue);
    });

    test('clearCache purges all cached files', () async {
      // Arrange
      final file = File('${tempDir.path}/sample.flac');
      file.writeAsStringSync('sample data');
      expect(file.existsSync(), isTrue);

      // Act
      await cacheManager.clearCache();

      // Assert
      expect(file.existsSync(), isFalse);
      expect(await cacheManager.getCacheUsageBytes(), 0);
    });
  });
}
