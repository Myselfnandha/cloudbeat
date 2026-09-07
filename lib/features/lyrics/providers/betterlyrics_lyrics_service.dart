import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/services/app_logger.dart';
import '../parsers/lrc_parser.dart';
import '../parsers/ttml_parser.dart';

/// BetterLyrics Service querying https://lyrics-api.boidu.dev for word-by-word TTML
class BetterLyricsService implements LyricsProviderContract {
  final http.Client _httpClient;

  BetterLyricsService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  @override
  LyricsSource get source => LyricsSource.betterLyrics;

  static const String _apiBase = 'https://lyrics-api.boidu.dev/getLyrics';

  @override
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    AppLogger.trace('BetterLyricsService', 'fetchLyrics', {'title': title, 'artist': artist});
    try {
      final queryParams = {
        's': title,
        'a': artist,
        if (album != null && album.isNotEmpty) 'al': album,
        if (duration != null && duration.inSeconds > 0) 'd': duration.inSeconds.toString(),
      };

      final uri = Uri.parse(_apiBase).replace(queryParameters: queryParams);
      final resp = await _httpClient.get(
        uri,
        headers: {'User-Agent': 'CloudBeat/1.3.2'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final bodyStr = resp.body.trim();
      if (bodyStr.isEmpty) return null;

      // Handle both raw TTML XML or JSON wrapper
      String content = bodyStr;
      if (bodyStr.startsWith('{')) {
        final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
        content = (decoded['ttml'] ?? decoded['lyrics'] ?? decoded['content'] ?? '') as String;
      }

      if (content.isEmpty) return null;

      if (content.contains('<tt') || content.contains('<p') || content.contains('http://www.w3.org/ns/ttml')) {
        final lines = TtmlParser.parse(content);
        if (lines.isNotEmpty) {
          return LyricsResult(
            trackTitle: title,
            artist: artist,
            format: LyricsFormat.ttml,
            source: LyricsSource.betterLyrics,
            rawLyrics: content,
            lines: lines,
            qualityScore: LyricsResult.calculateScore(LyricsFormat.ttml, LyricsSource.betterLyrics),
          );
        }
      }

      // Fallback LRC parsing
      final lrcLines = LrcParser.parse(content);
      if (lrcLines.isNotEmpty) {
        final hasWords = lrcLines.any((l) => l.hasWordTiming);
        return LyricsResult(
          trackTitle: title,
          artist: artist,
          format: hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc,
          source: LyricsSource.betterLyrics,
          rawLyrics: content,
          lines: lrcLines,
          qualityScore: LyricsResult.calculateScore(hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc, LyricsSource.betterLyrics),
        );
      }
    } catch (e) {
      AppLogger.trace('BetterLyricsService', 'fetchError', {'error': e.toString()});
    }
    return null;
  }
}
