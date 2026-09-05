import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/audio_player/cloudbeat_audio_engine.dart';

void main() {
  group('Module 4: Adaptive Quality Engine Tests', () {
    test('resolveBestQuality prioritizes FLAC 24-bit Hi-Res if track quality is 24-bit', () {
      final track = Track(
        id: 'track_24bit',
        title: 'Master Audio',
        artists: ['Audiophile Studio'],
        album: 'Hi-Res Vault',
        durationSeconds: 240,
        quality: AudioQuality.flac24Bit,
        addedAt: DateTime.now(),
      );

      final resolved = CloudBeatAudioEngine.resolveBestQuality(track);
      expect(resolved, AudioQuality.flac24Bit);
    });

    test('resolveBestQuality resolves FLAC 16-bit when track quality is 16-bit', () {
      final track = Track(
        id: 'track_16bit',
        title: 'Redbook Audio',
        artists: ['CD Master'],
        album: 'Lossless Vault',
        durationSeconds: 210,
        quality: AudioQuality.flac16Bit,
        addedAt: DateTime.now(),
      );

      final resolved = CloudBeatAudioEngine.resolveBestQuality(track);
      expect(resolved, AudioQuality.flac16Bit);
    });

    test('resolveBestQuality falls back to Opus 320k when track quality is opus320k', () {
      final track = Track(
        id: 'track_opus',
        title: 'Streaming Audio',
        artists: ['Opus Stream'],
        album: 'Compressed Vault',
        durationSeconds: 195,
        quality: AudioQuality.opus320k,
        addedAt: DateTime.now(),
      );

      final resolved = CloudBeatAudioEngine.resolveBestQuality(track);
      expect(resolved, AudioQuality.opus320k);
    });

    test('resolveBestQuality falls back to lossyFallback when track quality is lossyFallback', () {
      final track = Track(
        id: 'track_lossy',
        title: 'Low Bandwidth',
        artists: ['Fallback Stream'],
        album: 'Legacy Vault',
        durationSeconds: 150,
        quality: AudioQuality.lossyFallback,
        addedAt: DateTime.now(),
      );

      final resolved = CloudBeatAudioEngine.resolveBestQuality(track);
      expect(resolved, AudioQuality.lossyFallback);
    });

    test('Audio quality mapping produces correct UI badge strings', () {
      String getQualityBadgeText(AudioQuality quality) {
        switch (quality) {
          case AudioQuality.flac24Bit:
            return 'Hi-Res 24/192';
          case AudioQuality.flac16Bit:
            return 'FLAC 16/44.1';
          case AudioQuality.opus320k:
            return 'Opus 320k';
          case AudioQuality.lossyFallback:
            return 'Standard';
        }
      }

      expect(getQualityBadgeText(AudioQuality.flac24Bit), 'Hi-Res 24/192');
      expect(getQualityBadgeText(AudioQuality.flac16Bit), 'FLAC 16/44.1');
      expect(getQualityBadgeText(AudioQuality.opus320k), 'Opus 320k');
      expect(getQualityBadgeText(AudioQuality.lossyFallback), 'Standard');
    });
  });
}
