import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/services/cobalt_stream_resolver.dart';

void main() {
  group('CobaltStreamResolver Tests', () {
    test('resolves direct audio stream URL from Cobalt instance', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'api.cobalt.tools') {
          return http.Response(
            jsonEncode({
              'status': 'stream',
              'url': 'https://stream.cobalt.tools/audio/stream123.opus',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final resolver = CobaltStreamResolver(client: mockClient);
      final res = await resolver.resolveMediaUrl('https://www.youtube.com/watch?v=abcdefghijk');

      expect(res, isNotNull);
      expect(res!.streamUrl, 'https://stream.cobalt.tools/audio/stream123.opus');
      expect(res.quality, AudioQuality.opus320k);
    });

    test('falls back to second instance when primary fails', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'api.cobalt.tools') {
          return http.Response('Error 500', 500);
        }
        if (request.url.host == 'cobalt-api.koyeb.app') {
          return http.Response(
            jsonEncode({
              'status': 'stream',
              'url': 'https://koyeb.cobalt/audio.opus',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final resolver = CobaltStreamResolver(client: mockClient);
      final res = await resolver.resolveMediaUrl('https://www.youtube.com/watch?v=abcdefghijk');

      expect(res, isNotNull);
      expect(res!.streamUrl, 'https://koyeb.cobalt/audio.opus');
    });

    test('supports custom instance URL update', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'my-private-cobalt.internal') {
          return http.Response(
            jsonEncode({
              'status': 'stream',
              'url': 'https://my-private-cobalt.internal/stream.opus',
            }),
            200,
          );
        }
        return http.Response('Error', 500);
      });

      final resolver = CobaltStreamResolver(client: mockClient);
      resolver.updateCustomInstance('https://my-private-cobalt.internal');

      final res = await resolver.resolveMediaUrl('https://www.youtube.com/watch?v=custom');
      expect(res, isNotNull);
      expect(res!.streamUrl, 'https://my-private-cobalt.internal/stream.opus');
    });
  });
}
