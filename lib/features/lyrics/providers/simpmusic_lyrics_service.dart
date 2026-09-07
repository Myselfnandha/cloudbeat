import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/services/app_logger.dart';
import '../parsers/lrc_parser.dart';

/// SimpMusic Lyrics Service querying https://api-lyrics.simpmusic.org/v1/
class SimpMusicLyricsService implements LyricsProviderContract {
  final http.Client _httpClient;

  SimpMusicLyricsService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  @override
  LyricsSource get source => LyricsSource.simpmusic;

  static const String _apiBase = 'https://api-lyrics.simpmusic.org/v1/';

  @override
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    AppLogger.trace('SimpMusicLyricsService', 'fetchLyrics', {'title': title, 'artist': artist});
    try {
      final query = Uri.encodeComponent('$title $artist');
      final uri = Uri.parse('$_apiBase$query');

      final resp = await _httpClient.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'CloudBeat/1.3.2',
        },
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;

      final data = body['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) return null;

      final targetDurSec = duration?.inSeconds ?? 0;
      Map<String, dynamic>? bestMatch;
      int minDiff = 999999;

      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final itemDur = (item['duration'] as num?)?.toInt() ?? 0;
        final diff = (itemDur - targetDurSec).abs();
        if (targetDurSec > 0 && diff <= 10 && diff < minDiff) {
          minDiff = diff;
          bestMatch = item;
        } else {
          bestMatch ??= item;
        }
      }

      if (bestMatch == null) return null;

      final synced = bestMatch['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final lines = LrcParser.parse(synced);
        if (lines.isNotEmpty) {
          final hasWords = lines.any((l) => l.hasWordTiming);
          return LyricsResult(
            trackTitle: title,
            artist: artist,
            format: hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc,
            source: LyricsSource.simpmusic,
            rawLyrics: synced,
            lines: lines,
            qualityScore: LyricsResult.calculateScore(hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc, LyricsSource.simpmusic),
          );
        }
      }

      final plain = bestMatch['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        final plainLines = plain.split('\n').map((l) => LyricsLine(startTime: Duration.zero, text: l.trim())).where((l) => l.text.isNotEmpty).toList();
        return LyricsResult(
          trackTitle: title,
          artist: artist,
          format: LyricsFormat.plainText,
          source: LyricsSource.simpmusic,
          rawLyrics: plain,
          lines: plainLines,
          qualityScore: LyricsResult.calculateScore(LyricsFormat.plainText, LyricsSource.simpmusic),
        );
      }
    } catch (e) {
      AppLogger.trace('SimpMusicLyricsService', 'fetchError', {'error': e.toString()});
    }
    return null;
  }
}
