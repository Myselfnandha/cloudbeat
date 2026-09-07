import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/services/deezer_stream_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeezerStreamResolver Tests', () {
    test('resolves preview stream URL when trackId is provided', () async {
      // Arrange
      final mockClient = MockClient((request) async {
        if (request.url.path == '/track/12345') {
          return http.Response(
            jsonEncode({
              'id': 12345,
              'title': 'Test Song',
              'preview': 'https://cdns-preview.dzcdn.net/stream/12345.mp3',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final resolver = DeezerStreamResolver(client: mockClient);

      // Act
      final result = await resolver.resolveAudioStream(trackId: '12345');

      // Assert
      expect(result, isNotNull);
      expect(result!.streamUrl, 'https://cdns-preview.dzcdn.net/stream/12345.mp3');
      expect(result.quality, AudioQuality.lossyFallback);
    });

    test('searches Deezer by title & artist when trackId is null', () async {
      // Arrange
      final mockClient = MockClient((request) async {
        if (request.url.path == '/search') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 99999,
                  'title': 'Save Your Tears',
                  'artist': {'name': 'The Weeknd'},
                  'duration': 215,
                }
              ]
            }),
            200,
          );
        } else if (request.url.path == '/track/99999') {
          return http.Response(
            jsonEncode({
              'id': 99999,
              'title': 'Save Your Tears',
              'preview': 'https://cdns-preview.dzcdn.net/stream/99999.mp3',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final resolver = DeezerStreamResolver(client: mockClient);

      // Act
      final result = await resolver.resolveAudioStream(
        title: 'Save Your Tears',
        artist: 'The Weeknd',
        durationSeconds: 215,
      );

      // Assert
      expect(result, isNotNull);
      expect(result!.streamUrl, 'https://cdns-preview.dzcdn.net/stream/99999.mp3');
    });

    test('returns null gracefully when Deezer API returns 404 or empty', () async {
      // Arrange
      final mockClient = MockClient((request) async => http.Response('Not Found', 404));
      final resolver = DeezerStreamResolver(client: mockClient);

      // Act
      final result = await resolver.resolveAudioStream(trackId: 'nonexistent');

      // Assert
      expect(result, isNull);
    });
  });
}
