import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LRU Streaming Cache Manager for on-device offline playback acceleration.
class StreamingCacheManager {
  static StreamingCacheManager? _instance;
  final http.Client _client;
  Directory? _cacheDir;

  static const String _prefCacheLimitKey = 'streaming_cache_limit_mb';
  static const int defaultLimitMb = 2048; // 2 GB default

  StreamingCacheManager._({http.Client? client, Directory? cacheDir})
      : _client = client ?? http.Client(),
        _cacheDir = cacheDir;

  static StreamingCacheManager get instance => _instance ??= StreamingCacheManager._();

  factory StreamingCacheManager({http.Client? client, Directory? cacheDir}) {
    if (cacheDir != null) {
      return StreamingCacheManager._(client: client, cacheDir: cacheDir);
    }
    return _instance ??= StreamingCacheManager._(client: client);
  }

  Future<Directory> getCacheDirectory() async {
    if (_cacheDir != null && _cacheDir!.existsSync()) {
      return _cacheDir!;
    }
    final docDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(docDir.path, 'streaming_cache'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Configured cache size limit in bytes.
  Future<int> getCacheLimitBytes() async {
    final prefs = await SharedPreferences.getInstance();
    final limitMb = prefs.getInt(_prefCacheLimitKey) ?? defaultLimitMb;
    return limitMb * 1024 * 1024;
  }

  /// Sets the cache size limit in MB (e.g. from Settings screen slider).
  Future<void> setCacheLimitMb(int limitMb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefCacheLimitKey, limitMb);
    await enforceLruEviction();
  }

  /// Total current cache usage in bytes.
  Future<int> getCacheUsageBytes() async {
    try {
      final dir = await getCacheDirectory();
      int total = 0;
      final entities = dir.listSync(recursive: false);
      for (final e in entities) {
        if (e is File) {
          total += e.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Retrieves cached file for [trackId] if it exists and is non-empty.
  Future<File?> getCachedFile(String trackId) async {
    try {
      final dir = await getCacheDirectory();
      final sanitizedId = trackId.replaceAll(RegExp(r'[^\w\-]'), '_');
      const supportedExtensions = ['flac', 'opus', 'm4a', 'mp3', 'webm'];

      for (final ext in supportedExtensions) {
        final file = File(p.join(dir.path, '$sanitizedId.$ext'));
        if (file.existsSync() && file.lengthSync() > 0) {
          // Touch access timestamp for LRU
          try {
            file.setLastModifiedSync(DateTime.now());
          } catch (_) {}
          return file;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Downloads stream to local cache in the background.
  Future<File?> cacheStream({
    required String trackId,
    required String streamUrl,
    Map<String, String>? headers,
    String? preferredExtension,
  }) async {
    // If already cached, don't download again
    final existing = await getCachedFile(trackId);
    if (existing != null) return existing;

    try {
      final dir = await getCacheDirectory();
      final sanitizedId = trackId.replaceAll(RegExp(r'[^\w\-]'), '_');

      // Determine file extension
      String ext = preferredExtension ?? 'flac';
      if (preferredExtension == null) {
        final lowerUrl = streamUrl.toLowerCase();
        if (lowerUrl.contains('.opus')) {
          ext = 'opus';
        } else if (lowerUrl.contains('.m4a') || lowerUrl.contains('aac')) {
          ext = 'm4a';
        } else if (lowerUrl.contains('.mp3')) {
          ext = 'mp3';
        } else if (lowerUrl.contains('.webm')) {
          ext = 'webm';
        }
      }

      final tempFile = File(p.join(dir.path, '$sanitizedId.tmp'));
      final targetFile = File(p.join(dir.path, '$sanitizedId.$ext'));

      final request = http.Request('GET', Uri.parse(streamUrl));
      if (headers != null && headers.isNotEmpty) {
        request.headers.addAll(headers);
      }

      final response = await _client.send(request).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final sink = tempFile.openWrite();
      await response.stream.pipe(sink);
      await sink.flush();
      await sink.close();

      if (tempFile.existsSync() && tempFile.lengthSync() > 1000) {
        if (targetFile.existsSync()) {
          targetFile.deleteSync();
        }
        await tempFile.rename(targetFile.path);
        targetFile.setLastModifiedSync(DateTime.now());

        // Enforce cache limit in background
        enforceLruEviction().catchError((e) => debugPrint('LRU eviction error: $e'));
        return targetFile;
      } else {
        if (tempFile.existsSync()) tempFile.deleteSync();
      }
    } catch (e) {
      debugPrint('[StreamingCacheManager] Background cache download failed: $e');
    }
    return null;
  }

  /// Evicts oldest accessed files when cache exceeds configured limit.
  Future<void> enforceLruEviction() async {
    try {
      final dir = await getCacheDirectory();
      if (!dir.existsSync()) return;
      final limitBytes = await getCacheLimitBytes();
      final files = dir.listSync().whereType<File>().toList();

      int currentBytes = 0;
      for (final f in files) {
        currentBytes += f.lengthSync();
      }

      if (currentBytes <= limitBytes) return;

      // Sort files by last modified timestamp ascending (oldest first)
      files.sort((a, b) {
        final aTime = a.lastModifiedSync();
        final bTime = b.lastModifiedSync();
        return aTime.compareTo(bTime);
      });

      for (final file in files) {
        if (currentBytes <= limitBytes) {
          break;
        }
        final size = file.lengthSync();
        try {
          file.deleteSync();
          currentBytes -= size;
          debugPrint('[StreamingCacheManager] Evicted LRU file: ${file.path} ($size bytes)');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[StreamingCacheManager] enforceLruEviction error: $e');
    }
  }

  /// Purges all cached files.
  Future<void> clearCache() async {
    try {
      final dir = await getCacheDirectory();
      for (final entity in dir.listSync()) {
        if (entity is File) {
          entity.deleteSync();
        }
      }
    } catch (_) {}
  }
}
