import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_logger.dart';

class SkipSegment {
  final double start;
  final double end;
  final String category;

  const SkipSegment({
    required this.start,
    required this.end,
    required this.category,
  });

  bool contains(double positionSec) {
    return positionSec >= start && positionSec < end;
  }
}

/// Fetches and manages non-music / sponsor / intro / outro segments via the SponsorBlock API.
class SponsorBlockService {
  final http.Client _client;
  final String _baseUrl;
  bool isEnabled;

  SponsorBlockService({
    http.Client? client,
    String baseUrl = 'https://sponsor.ajay.app/api',
    bool enabled = true,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl,
        isEnabled = enabled;

  /// Fetches skip segments for a given video ID.
  Future<List<SkipSegment>> fetchSkipSegments(String videoId) async {
    AppLogger.trace('SponsorBlockService', 'fetchSkipSegments', {'videoId': videoId, 'isEnabled': isEnabled});
    if (!isEnabled || videoId.trim().isEmpty) return [];

    try {
      final uri = Uri.parse(
        '$_baseUrl/skipSegments?videoID=${Uri.encodeComponent(videoId)}&categories=%5B%22music_offtopic%22%2C%22sponsor%22%2C%22intro%22%2C%22outro%22%2C%22preview%22%5D',
      );

      final res = await _client.get(uri, headers: {
        'User-Agent': 'CloudBeat/1.1 (AudioStream)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode != 200) return [];

      final data = jsonDecode(res.body);
      if (data is! List) return [];

      final segments = <SkipSegment>[];
      for (final item in data) {
        if (item is! Map) continue;
        final segList = item['segment'] as List<dynamic>?;
        if (segList == null || segList.length < 2) continue;
        final start = (segList[0] as num).toDouble();
        final end = (segList[1] as num).toDouble();
        final category = item['category']?.toString() ?? 'music_offtopic';

        if (end > start) {
          segments.add(SkipSegment(start: start, end: end, category: category));
        }
      }

      // Sort segments by start time
      segments.sort((a, b) => a.start.compareTo(b.start));
      return segments;
    } catch (e) {
      debugPrint('[SponsorBlock] Fetch error for $videoId: $e');
      return [];
    }
  }

  /// Returns the adjusted start position if an intro/music_offtopic segment covers the beginning.
  double getCleanStartPosition(List<SkipSegment> segments) {
    AppLogger.trace('SponsorBlockService', 'getCleanStartPosition', {'segmentsCount': segments.length});
    if (!isEnabled || segments.isEmpty) return 0.0;
    double startPos = 0.0;
    for (final seg in segments) {
      // If segment starts at or near beginning (within first 2s)
      if (seg.start <= 2.0 && seg.end > startPos) {
        startPos = seg.end;
      }
    }
    return startPos;
  }

  /// Returns target seek position if current position falls within a skip segment, or null if clean.
  double? checkSkip(double currentPositionSec, List<SkipSegment> segments) {
    if (!isEnabled || segments.isEmpty) return null;
    for (final seg in segments) {
      if (seg.contains(currentPositionSec)) {
        AppLogger.trace('SponsorBlockService', 'checkSkip', {
          'position': currentPositionSec,
          'skipTo': seg.end,
          'category': seg.category,
        });
        return seg.end;
      }
    }
    return null;
  }
}
