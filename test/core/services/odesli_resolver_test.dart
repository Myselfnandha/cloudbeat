import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloudbeat/core/services/odesli_resolver.dart';

void main() {
  group('OdesliResolver Tests', () {
    test('resolves cross-platform links and IDs from Spotify track URL', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/links')) {
          return http.Response(
            jsonEncode({
              'entityUniqueId': 'SPOTIFY_SONG::123456',
              'userCountry': 'US',
              'linksByPlatform': {
                'spotify': {'url': 'https://open.spotify.com/track/123456'},
                'deezer': {'url': 'https://www.deezer.com/track/7891011'},
                'youtube': {'url': 'https://www.youtube.com/watch?v=xyz123abcde'},
                'appleMusic': {'url': 'https://music.apple.com/us/album/song/999'},
                'tidal': {'url': 'https://tidal.com/browse/track/555'},
              },
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final resolver = OdesliResolver(client: mockClient);
      final links = await resolver.resolveLinks('https://open.spotify.com/track/123456');

      expect(links, isNotNull);
      expect(links!.deezerTrackId, '7891011');
      expect(links.youtubeVideoId, 'xyz123abcde');
      expect(links.appleMusicUrl, contains('music.apple.com'));
      expect(links.tidalUrl, contains('tidal.com'));
    });

    test('returns null when API returns error or empty', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final resolver = OdesliResolver(client: mockClient);
      final links = await resolver.resolveLinks('invalid-url');
      expect(links, isNull);
    });
  });
}
