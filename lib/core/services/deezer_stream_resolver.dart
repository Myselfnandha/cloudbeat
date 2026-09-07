import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../contracts/acquisition_contract.dart';
import '../contracts/models.dart';
import '../matching/track_matcher.dart';
import '../session/zarz_session_manager.dart';
import 'app_logger.dart';

/// Direct Deezer stream resolver supporting public preview streams and Zarz FLAC upgrades.
class DeezerStreamResolver {
  final http.Client _client;
  final ZarzSessionManager? _zarzSession;

  DeezerStreamResolver({
    http.Client? client,
    ZarzSessionManager? zarzSession,
  })  : _client = client ?? http.Client(),
        _zarzSession = zarzSession;

  /// Resolves an audio stream for track [title] and [artist] or [trackId]
  Future<StreamResolution?> resolveAudioStream({
    String? trackId,
    String? title,
    String? artist,
    int durationSeconds = 0,
    AudioQuality requestedQuality = AudioQuality.flac16Bit,
  }) async {
    AppLogger.trace('DeezerStreamResolver', 'resolveAudioStream', {
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'duration': durationSeconds,
      'quality': requestedQuality.name,
    });
    String? effectiveTrackId = trackId;

    // 1. If no trackId provided or it's non-numeric, search Deezer
    if (effectiveTrackId == null || int.tryParse(effectiveTrackId) == null) {
      if (title != null && title.isNotEmpty) {
        effectiveTrackId = await _findDeezerTrackId(title, artist ?? '', durationSeconds);
      }
    }

    if (effectiveTrackId == null) return null;

    // 2. If Zarz session is valid, attempt lossless FLAC resolution first
    if (_zarzSession != null && _zarzSession.hasValidSession) {
      try {
        final desc = await _zarzSession.resolveStreamDescriptor(
          provider: 'deezer',
          trackId: effectiveTrackId,
          format: requestedQuality == AudioQuality.flac24Bit ? 'FLAC_24' : 'FLAC',
        );
        final directUrl = desc['direct_download_url']?.toString() ?? desc['url']?.toString();
        if (directUrl != null && directUrl.isNotEmpty) {
          return StreamResolution(
            streamUrl: directUrl,
            quality: requestedQuality,
          );
        }
      } catch (e) {
        debugPrint('[DeezerStreamResolver] Zarz descriptor failed: $e');
      }
    }

    // 3. Fall back to Deezer CDN preview URL
    try {
      final trackUri = Uri.parse('https://api.deezer.com/track/$effectiveTrackId');
      final res = await _client.get(trackUri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final previewUrl = data['preview']?.toString();
        if (previewUrl != null && previewUrl.isNotEmpty) {
          return StreamResolution(
            streamUrl: previewUrl,
            quality: AudioQuality.lossyFallback,
          );
        }
      }
    } catch (e) {
      debugPrint('[DeezerStreamResolver] Deezer track info failed: $e');
    }

    return null;
  }

  Future<String?> _findDeezerTrackId(String title, String artist, int durationSeconds) async {
    AppLogger.trace('DeezerStreamResolver', '_findDeezerTrackId', {
      'title': title,
      'artist': artist,
      'duration': durationSeconds,
    });
    try {
      final query = Uri.encodeComponent('$title $artist'.trim());
      final searchUri = Uri.parse('https://api.deezer.com/search?q=$query&limit=10');
      final res = await _client.get(searchUri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>?;
      if (list == null || list.isEmpty) return null;

      String? bestId;
      double bestScore = 0.0;

      for (final item in list) {
        final m = item as Map<String, dynamic>;
        // Ensure item is a song track, not a podcast or talk episode
        if (m['type'] != null && m['type'] != 'track') continue;

        final candId = m['id']?.toString();
        final candTitle = m['title']?.toString() ?? '';
        final candArtist = (m['artist'] as Map<String, dynamic>?)?['name']?.toString() ?? '';
        final candDuration = m['duration'] as int? ?? 0;

        if (candId == null || candId.isEmpty) continue;

        final score = TrackMatcher.scoreTrackMatch(
          targetTitle: title,
          targetArtist: artist,
          candidateTitle: candTitle,
          candidateArtist: candArtist,
          targetDuration: durationSeconds,
          candidateDuration: candDuration,
        );

        if (score > bestScore && score >= 40.0) {
          bestScore = score;
          bestId = candId;
        }
      }

      // Do not fall back to list.first if all items were contaminated or scored below threshold
      return bestId;
    } catch (_) {
      return null;
    }
  }
}
