import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/services/app_logger.dart';
import '../parsers/lrc_parser.dart';

class LrclibLyricsService implements LyricsProviderContract {
  final http.Client _httpClient;
  static const String _baseUrl = 'https://lrclib.net/api';

  LrclibLyricsService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  LyricsSource get source => LyricsSource.lrclib;

  @override
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    AppLogger.trace('LrclibLyricsService', 'fetchLyrics', {'title': title, 'artist': artist});
    try {
      // Clean title and extract primary artist for higher match rate
      final cleanTitle = _cleanSongTitle(title);
      final primaryArtist = artist.split(',').first.split('&').first.trim();

      // 1. Try exact match via /api/get with primary artist
      final queryParams = <String, String>{
        'track_name': cleanTitle,
        'artist_name': primaryArtist,
      };
      if (album != null && album.isNotEmpty && !album.contains('(')) {
        queryParams['album_name'] = album;
      }
      if (duration != null && duration.inSeconds > 0) {
        queryParams['duration'] = duration.inSeconds.toString();
      }

      final getUri = Uri.parse('$_baseUrl/get').replace(queryParameters: queryParams);
      try {
        final response = await _httpClient.get(getUri, headers: {
          'User-Agent': 'CloudBeat/1.0.0 (https://github.com/Myselfnandha/cloudbeat)',
        }).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final res = _buildResult(data, title, artist);
          if (res != null) return res;
        }
      } catch (_) {}

      // 2. Fallback to /api/search?q=
      final searchQueries = [
        '$cleanTitle $primaryArtist',
        cleanTitle,
      ];

      for (final query in searchQueries) {
        try {
          final searchUri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
            'q': query,
          });
          final searchResp = await _httpClient.get(searchUri, headers: {
            'User-Agent': 'CloudBeat/1.0.0 (https://github.com/Myselfnandha/cloudbeat)',
          }).timeout(const Duration(seconds: 6));

          if (searchResp.statusCode == 200) {
            final list = jsonDecode(searchResp.body) as List<dynamic>;
            if (list.isNotEmpty) {
              // Prefer candidate with synchronized lyrics
              final bestMatch = list.firstWhere(
                (item) => item['syncedLyrics'] != null && (item['syncedLyrics'] as String).isNotEmpty,
                orElse: () => list.first,
              ) as Map<String, dynamic>;

              final res = _buildResult(bestMatch, title, artist);
              if (res != null) return res;
            }
          }
        } catch (_) {}
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  String _cleanSongTitle(String rawTitle) {
    var cleaned = rawTitle;
    // Remove (feat. ...), (Live), (Remaster...), [192kHz], (Hi-Res...), etc.
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*-\s*.*$'), ''); // Remove subtitle after hyphen
    return cleaned.trim();
  }

  LyricsResult? _buildResult(Map<String, dynamic> data, String fallbackTitle, String fallbackArtist) {
    AppLogger.trace('LrclibLyricsService', '_buildResult', {'fallbackTitle': fallbackTitle});
    final trackName = data['trackName'] as String? ?? fallbackTitle;
    final artistName = data['artistName'] as String? ?? fallbackArtist;
    final isInstrumental = data['instrumental'] as bool? ?? false;
    final syncedLyrics = data['syncedLyrics'] as String?;
    final plainLyrics = data['plainLyrics'] as String?;

    if (isInstrumental) {
      return LyricsResult(
        trackTitle: trackName,
        artist: artistName,
        format: LyricsFormat.plainText,
        source: LyricsSource.lrclib,
        rawLyrics: '[Instrumental]',
        isInstrumental: true,
        qualityScore: LyricsResult.calculateScore(LyricsFormat.plainText, LyricsSource.lrclib, isInstrumental: true),
      );
    }

    if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
      final lines = LrcParser.parse(syncedLyrics);
      return LyricsResult(
        trackTitle: trackName,
        artist: artistName,
        format: LyricsFormat.syncedLrc,
        source: LyricsSource.lrclib,
        rawLyrics: syncedLyrics,
        lines: lines,
        qualityScore: LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.lrclib),
      );
    }

    if (plainLyrics != null && plainLyrics.trim().isNotEmpty) {
      return LyricsResult(
        trackTitle: trackName,
        artist: artistName,
        format: LyricsFormat.plainText,
        source: LyricsSource.lrclib,
        rawLyrics: plainLyrics,
        qualityScore: LyricsResult.calculateScore(LyricsFormat.plainText, LyricsSource.lrclib),
      );
    }

    return null;
  }
}
