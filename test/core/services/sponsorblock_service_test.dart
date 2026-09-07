import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloudbeat/core/services/sponsorblock_service.dart';

void main() {
  group('SponsorBlockService Tests', () {
    test('fetches and parses skip segments for video ID', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('skipSegments')) {
          return http.Response(
            jsonEncode([
              {
                'category': 'intro',
                'segment': [0.0, 14.5],
                'actionType': 'skip',
              },
              {
                'category': 'music_offtopic',
                'segment': [95.0, 110.0],
                'actionType': 'skip',
              },
              {
                'category': 'outro',
                'segment': [230.0, 245.0],
                'actionType': 'skip',
              },
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = SponsorBlockService(client: mockClient);
      final segments = await service.fetchSkipSegments('testVideoId123');

      expect(segments.length, 3);
      expect(segments[0].category, 'intro');
      expect(segments[0].start, 0.0);
      expect(segments[0].end, 14.5);
      expect(segments[1].category, 'music_offtopic');
    });

    test('getCleanStartPosition detects intro covering song beginning', () {
      final service = SponsorBlockService();
      final segments = [
        const SkipSegment(start: 0.0, end: 12.0, category: 'intro'),
        const SkipSegment(start: 120.0, end: 130.0, category: 'music_offtopic'),
      ];

      final cleanStart = service.getCleanStartPosition(segments);
      expect(cleanStart, 12.0);
    });

    test('checkSkip returns seek target when inside segment', () {
      final service = SponsorBlockService();
      final segments = [
        const SkipSegment(start: 50.0, end: 65.0, category: 'music_offtopic'),
      ];

      // Outside
      expect(service.checkSkip(40.0, segments), isNull);
      // Inside
      expect(service.checkSkip(55.0, segments), 65.0);
      // Past end
      expect(service.checkSkip(65.0, segments), isNull);
    });

    test('does nothing when disabled', () async {
      final service = SponsorBlockService(enabled: false);
      final segments = await service.fetchSkipSegments('testVideoId123');
      expect(segments, isEmpty);
      expect(service.getCleanStartPosition([const SkipSegment(start: 0.0, end: 10.0, category: 'intro')]), 0.0);
    });
  });
}
