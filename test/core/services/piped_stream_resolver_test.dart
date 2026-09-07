import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/services/piped_stream_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PipedStreamResolver Tests', () {
    test('resolves stream URL with highest bitrate audio stream from Piped instance', () async {
      // Arrange
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/search')) {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'url': '/watch?v=mock_video_123',
                  'title': 'Shape of You',
                  'uploaderName': 'Ed Sheeran',
                  'duration': 233,
                }
              ]
            }),
            200,
          );
        } else if (request.url.path.contains('/streams/mock_video_123')) {
          return http.Response(
            jsonEncode({
              'audioStreams': [
                {
                  'url': 'https://mock.stream.url/audio_low.opus',
                  'bitrate': 64000,
                  'format': 'opus',
                },
                {
                  'url': 'https://mock.stream.url/audio_high.opus',
                  'bitrate': 256000,
                  'format': 'opus',
                },
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final resolver = PipedStreamResolver(
        client: mockClient,
        pipedInstances: ['https://piped.test.instance'],
      );

      // Act
      final result = await resolver.resolveAudioStream(
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        durationSeconds: 233,
      );

      // Assert
      expect(result, isNotNull);
      expect(result!.streamUrl, 'https://mock.stream.url/audio_high.opus');
      expect(result.quality, AudioQuality.opus320k);
    });

    test('falls back to Invidious instance when Piped instance returns 500', () async {
      // Arrange
      final mockClient = MockClient((request) async {
        if (request.url.host == 'piped.failing.instance') {
          return http.Response('Server Error', 500);
        }
        if (request.url.host == 'invidious.working.instance') {
          if (request.url.path.contains('/search')) {
            return http.Response(
              jsonEncode([
                {
                  'videoId': 'inv_video_456',
                  'title': 'Blinding Lights',
                  'author': 'The Weeknd',
                  'lengthSeconds': 200,
                }
              ]),
              200,
            );
          } else if (request.url.path.contains('/videos/inv_video_456')) {
            return http.Response(
              jsonEncode({
                'adaptiveFormats': [
                  {
                    'type': 'audio/webm; codecs="opus"',
                    'url': 'https://mock.invidious.stream/audio.opus',
                    'bitrate': 160000,
                  }
                ]
              }),
              200,
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      final resolver = PipedStreamResolver(
        client: mockClient,
        pipedInstances: ['https://piped.failing.instance'],
        invidiousInstances: ['https://invidious.working.instance'],
      );

      // Act
      final result = await resolver.resolveAudioStream(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        durationSeconds: 200,
      );

      // Assert
      expect(result, isNotNull);
      expect(result!.streamUrl, 'https://mock.invidious.stream/audio.opus');
    });

    test('returns null gracefully when all instances fail', () async {
      // Arrange
      final mockClient = MockClient((request) async => http.Response('Error', 500));
      final resolver = PipedStreamResolver(
        client: mockClient,
        pipedInstances: ['https://piped.failing.instance'],
        invidiousInstances: ['https://invidious.failing.instance'],
      );

      // Act
      final result = await resolver.resolveAudioStream(
        title: 'Nonexistent Song',
        artist: 'Unknown Artist',
      );

      // Assert
      expect(result, isNull);
    });
  });
}
