import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloudbeat/core/services/audio_purity_guard.dart';

void main() {
  group('AudioPurityGuard Tests', () {
    test('calculatePcm16Rms calculates zero for flat line and positive for sound', () {
      // 100 samples of zero (silence)
      final silence = List<int>.filled(200, 0);
      final silenceRms = AudioPurityGuard.calculatePcm16Rms(silence);
      expect(silenceRms, 0.0);

      // High amplitude square wave
      final sound = <int>[];
      for (int i = 0; i < 100; i++) {
        sound.add(0x00);
        sound.add(0x40); // amplitude ~ 16384 (0.5 normalized)
      }
      final soundRms = AudioPurityGuard.calculatePcm16Rms(sound);
      expect(soundRms, greaterThan(0.4));
    });

    test('isPcmSilence correctly flags silent byte blocks', () {
      final silence = List<int>.filled(200, 0);
      expect(AudioPurityGuard.isPcmSilence(silence), isTrue);

      final noisy = <int>[];
      for (int i = 0; i < 100; i++) {
        noisy.add(0xFF);
        noisy.add(0x3F);
      }
      expect(AudioPurityGuard.isPcmSilence(noisy), isFalse);
    });

    test('detectLeadingPcmSilence calculates duration of leading silence', () {
      const sampleRate = 44100;
      const channels = 2;
      final bytesPerSec = sampleRate * channels * 2; // 176400 bytes

      // 1.5 seconds of silence followed by sound
      final buffer = List<int>.filled((bytesPerSec * 1.5).round(), 0, growable: true);
      // Add sound
      for (int i = 0; i < 5000; i++) {
        buffer.add(0x00);
        buffer.add(0x50);
      }

      final silenceDuration = AudioPurityGuard.detectLeadingPcmSilence(
        buffer,
        sampleRate: sampleRate,
        channels: channels,
      );

      expect(silenceDuration.inMilliseconds, greaterThanOrEqualTo(1400));
      expect(silenceDuration.inMilliseconds, lessThanOrEqualTo(1600));
    });

    test('sampleStreamLeadingSilence detects zero padding from Range header request', () async {
      final mockClient = MockClient((request) async {
        // Return 64KB with 8KB of zeros at start
        final bytes = List<int>.filled(8192, 0, growable: true);
        bytes.addAll(List<int>.filled(8192, 0x55));
        return http.Response.bytes(bytes, 206);
      });

      final guard = AudioPurityGuard(client: mockClient);
      final offset = await guard.sampleStreamLeadingSilence('https://audio.cdn/track.mp3');

      expect(offset.inMilliseconds, greaterThan(0));
    });
  });
}
