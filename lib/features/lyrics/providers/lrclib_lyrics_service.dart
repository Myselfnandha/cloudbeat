import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
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
    try {
      // 1. Try exact match via /api/get
      final queryParams = <String, String>{
        'track_name': title,
        'artist_name': artist,
      };
      if (album != null && album.isNotEmpty) {
        queryParams['album_name'] = album;
      }
      if (duration != null && duration.inSeconds > 0) {
        queryParams['duration'] = duration.inSeconds.toString();
      }

      final getUri = Uri.parse('$_baseUrl/get').replace(queryParameters: queryParams);
      final response = await _httpClient.get(getUri, headers: {
        'User-Agent': 'CloudBeat/1.0.0 (https://github.com/Myselfnandha/cloudbeat)',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _buildResult(data, title, artist);
      }

      // 2. Fallback to /api/search?q=
      final searchUri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'q': '$title $artist',
      });
      final searchResp = await _httpClient.get(searchUri, headers: {
        'User-Agent': 'CloudBeat/1.0.0 (https://github.com/Myselfnandha/cloudbeat)',
      }).timeout(const Duration(seconds: 4));

      if (searchResp.statusCode == 200) {
        final list = jsonDecode(searchResp.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          return _buildResult(first, title, artist);
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  LyricsResult? _buildResult(Map<String, dynamic> data, String fallbackTitle, String fallbackArtist) {
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
      final lines = plainLyrics
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => LyricsLine(startTime: Duration.zero, text: l.trim()))
          .toList();

      return LyricsResult(
        trackTitle: trackName,
        artist: artistName,
        format: LyricsFormat.plainText,
        source: LyricsSource.lrclib,
        rawLyrics: plainLyrics,
        lines: lines,
        qualityScore: LyricsResult.calculateScore(LyricsFormat.plainText, LyricsSource.lrclib),
      );
    }

    return null;
  }
}
