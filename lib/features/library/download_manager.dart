import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/services/app_logger.dart';

class StorageLimitExceededException implements Exception {
  final String message;
  const StorageLimitExceededException([this.message = 'Storage limit reached. Delete some downloads or increase limit in settings.']);

  @override
  String toString() => message;
}

class DownloadManager {
  final CatalogContract _catalog;
  final AcquisitionContract _acquisition;

  DownloadManager({
    required CatalogContract catalog,
    required AcquisitionContract acquisition,
  })  : _catalog = catalog,
        _acquisition = acquisition;

  Future<Directory> _getDownloadsDir() async {
    AppLogger.trace('DownloadManager', '_getDownloadsDir');
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'downloads'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<int> getStorageLimitBytes() async {
    AppLogger.trace('DownloadManager', 'getStorageLimitBytes');
    final prefs = await SharedPreferences.getInstance();
    // 0 = unlimited. Otherwise stored in MB.
    final limitMb = prefs.getInt('downloads_storage_limit_mb') ?? 0;
    return limitMb * 1024 * 1024;
  }

  Future<void> setStorageLimitBytes(int bytes) async {
    AppLogger.trace('DownloadManager', 'setStorageLimitBytes', {'bytes': bytes});
    final prefs = await SharedPreferences.getInstance();
    final limitMb = bytes ~/ (1024 * 1024);
    await prefs.setInt('downloads_storage_limit_mb', limitMb);
  }

  Future<int> getStorageUsageBytes() async {
    AppLogger.trace('DownloadManager', 'getStorageUsageBytes');
    try {
      final dir = await _getDownloadsDir();
      if (!dir.existsSync()) return 0;
      int total = 0;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<String> downloadTrack(
    Track track, {
    void Function(double progress)? onProgress,
  }) async {
    AppLogger.trace('DownloadManager', 'downloadTrack', {'trackId': track.id});
    final limit = await getStorageLimitBytes();
    if (limit > 0) {
      final currentUsage = await getStorageUsageBytes();
      if (currentUsage >= limit) {
        throw const StorageLimitExceededException();
      }
    }

    final downloadsDir = await _getDownloadsDir();
    final sanitizedId = track.id.replaceAll(RegExp(r'[^\w\-]'), '_');
    final targetFile = File(p.join(downloadsDir.path, '$sanitizedId.flac'));

    String backend = 'qobuz';
    String realId = track.id;
    if (track.id.contains(':')) {
      final parts = track.id.split(':');
      backend = parts[0];
      realId = parts[1];
    }

    final resolution = await _acquisition.resolveStreamUrl(
      trackId: realId,
      backend: backend,
      requestedQuality: AudioQuality.flac24Bit,
      title: track.title,
      artist: track.artists.isNotEmpty ? track.artists.first : null,
      durationSeconds: track.durationSeconds,
    );

    onProgress?.call(0.2);

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(resolution.streamUrl));
      if (resolution.headers.isNotEmpty) {
        request.headers.addAll(resolution.headers);
      }
      final response = await client.send(request);
      if (response.statusCode >= 400) {
        throw Exception('Download failed with HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = targetFile.openWrite();

      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            onProgress?.call(0.2 + (0.75 * (receivedBytes / totalBytes)));
          }
        },
      ).asFuture();

      await sink.flush();
      await sink.close();
    } catch (e) {
      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
    }

    onProgress?.call(1.0);

    final updatedTrack = track.copyWith(
      isDownloaded: true,
      localFilePath: targetFile.path,
    );
    await _catalog.upsertTracks([updatedTrack]);
    await _catalog.setDownloadState(
      track.id,
      isDownloaded: true,
      localFilePath: targetFile.path,
    );

    return targetFile.path;
  }

  Future<void> deleteDownload(String trackId) async {
    AppLogger.trace('DownloadManager', 'deleteDownload', {'trackId': trackId});
    final downloadsDir = await _getDownloadsDir();
    final sanitizedId = trackId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final targetFile = File(p.join(downloadsDir.path, '$sanitizedId.flac'));

    if (targetFile.existsSync()) {
      try {
        targetFile.deleteSync();
      } catch (_) {}
    }

    await _catalog.setDownloadState(
      trackId,
      isDownloaded: false,
      localFilePath: null,
    );
  }

  Future<void> reconcile() async {
    AppLogger.trace('DownloadManager', 'reconcile');
    await _catalog.reconcileDownloads();
  }
}
