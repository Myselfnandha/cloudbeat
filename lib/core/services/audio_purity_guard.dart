import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_logger.dart';

/// Guard service to detect and bypass leading silence, dead outros, and audio padding.
class AudioPurityGuard {
  final http.Client _client;

  AudioPurityGuard({http.Client? client}) : _client = client ?? http.Client();

  /// Calculates Root Mean Square (RMS) normalized energy of 16-bit PCM byte data (0.0 to 1.0).
  static double calculatePcm16Rms(List<int> bytes) {
    if (bytes.length < 2) return 0.0;
    
    double sumSquares = 0.0;
    final sampleCount = bytes.length ~/ 2;

    for (int i = 0; i < sampleCount; i++) {
      // 16-bit signed integer (little-endian)
      int sample = bytes[i * 2] | (bytes[i * 2 + 1] << 8);
      if (sample >= 32768) sample -= 65536;
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
    }

    return sqrt(sumSquares / sampleCount);
  }

  /// Evaluates whether a chunk of audio PCM samples constitutes silence (< silenceThreshold).
  static bool isPcmSilence(List<int> bytes, {double threshold = 0.005}) {
    final rms = calculatePcm16Rms(bytes);
    return rms < threshold;
  }

  /// Scans byte stream chunk to determine leading silence duration.
  /// Assumes standard 44.1kHz 16-bit stereo PCM (176,400 bytes/sec).
  static Duration detectLeadingPcmSilence(
    List<int> pcmBytes, {
    int sampleRate = 44100,
    int channels = 2,
    double silenceThreshold = 0.005,
    Duration maxScan = const Duration(seconds: 10),
  }) {
    AppLogger.trace('AudioPurityGuard', 'detectLeadingPcmSilence', {
      'byteLength': pcmBytes.length,
      'sampleRate': sampleRate,
      'channels': channels,
    });
    final bytesPerSec = sampleRate * channels * 2;
    final maxBytes = min(pcmBytes.length, maxScan.inSeconds * bytesPerSec);
    final chunkBytes = (bytesPerSec * 0.1).round(); // 100ms chunks

    int silenceBytes = 0;
    for (int offset = 0; offset + chunkBytes <= maxBytes; offset += chunkBytes) {
      final chunk = pcmBytes.sublist(offset, offset + chunkBytes);
      if (isPcmSilence(chunk, threshold: silenceThreshold)) {
        silenceBytes += chunkBytes;
      } else {
        break;
      }
    }

    final silenceSec = silenceBytes / bytesPerSec;
    return Duration(milliseconds: (silenceSec * 1000).round());
  }

  /// Inspects HTTP audio stream head using Range request to check for leading padding or offset.
  Future<Duration> sampleStreamLeadingSilence(String streamUrl) async {
    AppLogger.trace('AudioPurityGuard', 'sampleStreamLeadingSilence', {'streamUrl': streamUrl});
    try {
      final uri = Uri.parse(streamUrl);
      final res = await _client.get(uri, headers: {
        'Range': 'bytes=0-65535',
        'User-Agent': 'CloudBeat/1.1 (AudioPurity)',
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 || res.statusCode == 206) {
        final bytes = res.bodyBytes;
        // Count continuous zero/near-zero bytes at the very start of raw audio data
        int zeroCount = 0;
        for (int i = 0; i < min(bytes.length, 16384); i++) {
          if (bytes[i] == 0) {
            zeroCount++;
          } else {
            break;
          }
        }

        // If significant zero padding exists before audio frames (approx > 4096 bytes)
        if (zeroCount > 4096) {
          // Approx 0.5s - 1.5s padding
          return const Duration(milliseconds: 800);
        }
      }
    } catch (e) {
      debugPrint('[AudioPurityGuard] Stream sample error: $e');
    }

    return Duration.zero;
  }
}
