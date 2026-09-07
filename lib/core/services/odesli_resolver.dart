import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_logger.dart';

class OdesliLinks {
  final String? spotifyUrl;
  final String? deezerUrl;
  final String? deezerTrackId;
  final String? youtubeUrl;
  final String? youtubeVideoId;
  final String? appleMusicUrl;
  final String? tidalUrl;

  const OdesliLinks({
    this.spotifyUrl,
    this.deezerUrl,
    this.deezerTrackId,
    this.youtubeUrl,
    this.youtubeVideoId,
    this.appleMusicUrl,
    this.tidalUrl,
  });
}

/// Cross-platform link and ID resolver using Odesli / song.link API.
class OdesliResolver {
  final http.Client _client;
  final String _baseUrl;

  OdesliResolver({
    http.Client? client,
    String baseUrl = 'https://api.song.link/v1-alpha.1',
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl;

  /// Resolves cross-platform streaming links from a known platform URL or ID.
  Future<OdesliLinks?> resolveLinks(String inputUrl) async {
    AppLogger.trace('OdesliResolver', 'resolveLinks', {'inputUrl': inputUrl});
    if (inputUrl.trim().isEmpty) return null;

    try {
      final uri = Uri.parse('$_baseUrl/links?url=${Uri.encodeComponent(inputUrl)}&userCountry=US');
      final res = await _client.get(uri, headers: {
        'User-Agent': 'CloudBeat/1.1 (SongLink)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final linksByPlatform = data['linksByPlatform'] as Map<String, dynamic>?;
      if (linksByPlatform == null) return null;

      String? spotifyUrl = linksByPlatform['spotify']?['url']?.toString();
      String? deezerUrl = linksByPlatform['deezer']?['url']?.toString();
      String? youtubeUrl = linksByPlatform['youtube']?['url']?.toString() ?? linksByPlatform['youtubeMusic']?['url']?.toString();
      String? appleMusicUrl = linksByPlatform['appleMusic']?['url']?.toString();
      String? tidalUrl = linksByPlatform['tidal']?['url']?.toString();

      String? deezerTrackId;
      if (deezerUrl != null) {
        final match = RegExp(r'track\/(\d+)').firstMatch(deezerUrl);
        deezerTrackId = match?.group(1);
      }

      String? youtubeVideoId;
      if (youtubeUrl != null) {
        final match = RegExp(r'(?:v=|\/)([0-9A-Za-z_-]{11})').firstMatch(youtubeUrl);
        youtubeVideoId = match?.group(1);
      }

      return OdesliLinks(
        spotifyUrl: spotifyUrl,
        deezerUrl: deezerUrl,
        deezerTrackId: deezerTrackId,
        youtubeUrl: youtubeUrl,
        youtubeVideoId: youtubeVideoId,
        appleMusicUrl: appleMusicUrl,
        tidalUrl: tidalUrl,
      );
    } catch (e) {
      debugPrint('[OdesliResolver] Error resolving $inputUrl: $e');
      return null;
    }
  }
}
