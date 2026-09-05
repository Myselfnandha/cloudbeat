import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/contracts/acquisition_contract.dart';

void main() {
  group('Contracts & Models Tests', () {
    test('Track model serialization & copyWith', () {
      final now = DateTime.now();
      final track = Track(
        id: 'track_123',
        title: 'Coolie Disco',
        artists: ['Anirudh Ravichander', 'Santhosh Narayanan'],
        album: 'Coolie',
        albumArtUrl: 'https://cdn.example.com/art.jpg',
        durationSeconds: 245,
        year: 2025,
        genre: 'Soundtrack',
        isrc: 'IN-A23-25-00123',
        isDownloaded: true,
        localFilePath: '/storage/music/track_123.flac',
        isFavorite: true,
        quality: AudioQuality.flac24Bit,
        isOfflinePinned: true,
        addedAt: now,
      );

      final map = track.toMap();
      expect(map['id'], 'track_123');
      expect(map['title'], 'Coolie Disco');
      expect(map['artists'], 'Anirudh Ravichander, Santhosh Narayanan');
      expect(map['is_downloaded'], 1);
      expect(map['local_file_path'], '/storage/music/track_123.flac');
      expect(map['is_favorite'], 1);
      expect(map['quality'], 'flac24Bit');
      expect(map['is_offline_pinned'], 1);

      final reconstructed = Track.fromMap(map);
      expect(reconstructed.id, track.id);
      expect(reconstructed.title, track.title);
      expect(reconstructed.artists, track.artists);
      expect(reconstructed.isDownloaded, true);
      expect(reconstructed.localFilePath, '/storage/music/track_123.flac');
      expect(reconstructed.isFavorite, true);
      expect(reconstructed.quality, AudioQuality.flac24Bit);
      expect(reconstructed.isOfflinePinned, true);

      final updated = reconstructed.copyWith(title: 'Coolie Title Track');
      expect(updated.title, 'Coolie Title Track');
      expect(updated.id, 'track_123');
      expect(updated.isDownloaded, true);
      expect(updated.isFavorite, true);
    });

    test('AcquiredAudioFiles cleanup deletes files safely', () async {
      final tempDir = await Directory.systemTemp.createTemp('cloudbeat_test_');
      final flacFile = File('${tempDir.path}/test.flac');
      final opusFile = File('${tempDir.path}/test.opus');

      await flacFile.writeAsString('mock flac bytes');
      await opusFile.writeAsString('mock opus bytes');

      expect(await flacFile.exists(), true);
      expect(await opusFile.exists(), true);

      final payload = AcquiredAudioFiles(
        track: Track(
          id: 'test_1',
          title: 'Test',
          artists: ['Artist'],
          album: 'Album',
          durationSeconds: 120,
          addedAt: DateTime.now(),
        ),
        flacFile: flacFile,
        opusFile: opusFile,
        acquiredQuality: AudioQuality.flac16Bit,
      );

      await payload.cleanup();

      expect(await flacFile.exists(), false);
      expect(await opusFile.exists(), false);

      // Subsequent cleanup should not throw even if files are already deleted
      await payload.cleanup();

      await tempDir.delete(recursive: true);
    });
  });
}
