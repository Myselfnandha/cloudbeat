import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/services/app_logger.dart';
import '../parsers/lrc_parser.dart';

/// YouLyPlus / LyricsPlus KPoe API Client
/// Races community servers and decodes millisecond syllable timings
class YouLyPlusLyricsService implements LyricsProviderContract {
  final http.Client _httpClient;

  static const List<String> _baseServers = [
    'https://lyricsplus.prjktla.my.id',
    'https://lyricsplus.binimum.org',
  ];

  String? _lastWorkingServer;

  YouLyPlusLyricsService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  @override
  LyricsSource get source => LyricsSource.youlyPlus;

  List<String> get _servers {
    if (_lastWorkingServer != null) {
      return [_lastWorkingServer!, ..._baseServers.where((s) => s != _lastWorkingServer)];
    }
    return _baseServers;
  }

  @override
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    AppLogger.trace('YouLyPlusLyricsService', 'fetchLyrics', {'title': title, 'artist': artist});

    final completer = Completer<LyricsResult?>();
    int pending = _servers.length;

    for (final srv in _servers) {
      _fetchFromServer(srv, title, artist, duration).then((res) {
        if (!completer.isCompleted && res != null) {
          _lastWorkingServer = srv;
          completer.complete(res);
        } else {
          pending--;
          if (pending == 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((_) {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
  }

  Future<LyricsResult?> _fetchFromServer(
    String baseUrl,
    String title,
    String artist,
    Duration? duration,
  ) async {
    try {
      final url = baseUrl.endsWith('/') ? '${baseUrl}v2/lyrics/get' : '$baseUrl/v2/lyrics/get';
      final queryParams = {
        'title': title,
        'artist': artist,
        if (duration != null && duration.inSeconds > 0) 'duration': duration.inSeconds.toString(),
      };

      final uri = Uri.parse(url).replace(queryParameters: queryParams);
      final resp = await _httpClient.get(
        uri,
        headers: {'User-Agent': 'CloudBeat/1.3.2'},
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      // Priority 1: Structured syllable lines (LyricsItem with syllabus)
      final rawItems = body['lyrics'] as List<dynamic>?;
      if (rawItems != null && rawItems.isNotEmpty) {
        final lines = <LyricsLine>[];
        for (final item in rawItems) {
          if (item is! Map<String, dynamic>) continue;
          final timeMs = (item['time'] as num?)?.toInt() ?? 0;
          final lineStart = Duration(milliseconds: timeMs);
          final text = item['text'] as String? ?? '';
          final syllabus = item['syllabus'] as List<dynamic>?;

          final words = <LyricsWord>[];
          bool isBg = false;

          if (syllabus != null && syllabus.isNotEmpty) {
            for (int i = 0; i < syllabus.length; i++) {
              final syl = syllabus[i];
              if (syl is! Map<String, dynamic>) continue;
              final sTime = (syl['time'] as num?)?.toInt() ?? timeMs;
              final sText = syl['text'] as String? ?? '';
              if (syl['isBackground'] == true) isBg = true;

              int nextTime = sTime + 400;
              if (i + 1 < syllabus.length) {
                nextTime = (syllabus[i + 1]['time'] as num?)?.toInt() ?? (sTime + 400);
              }

              if (sText.isNotEmpty) {
                words.add(LyricsWord(
                  text: sText,
                  startTime: Duration(milliseconds: sTime),
                  endTime: Duration(milliseconds: nextTime),
                ));
              }
            }
          }

          if (text.isNotEmpty || words.isNotEmpty) {
            lines.add(LyricsLine(
              startTime: lineStart,
              text: text.isNotEmpty ? text : words.map((w) => w.text).join(' '),
              words: words.isNotEmpty ? words : null,
              isBackground: isBg,
            ));
          }
        }

        if (lines.isNotEmpty) {
          final hasWords = lines.any((l) => l.hasWordTiming);
          return LyricsResult(
            trackTitle: title,
            artist: artist,
            format: hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc,
            source: LyricsSource.youlyPlus,
            rawLyrics: resp.body,
            lines: lines,
            qualityScore: LyricsResult.calculateScore(hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc, LyricsSource.youlyPlus),
          );
        }
      }

      // Priority 2: syncedLyrics string
      final synced = body['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final lines = LrcParser.parse(synced);
        if (lines.isNotEmpty) {
          final hasWords = lines.any((l) => l.hasWordTiming);
          return LyricsResult(
            trackTitle: title,
            artist: artist,
            format: hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc,
            source: LyricsSource.youlyPlus,
            rawLyrics: synced,
            lines: lines,
            qualityScore: LyricsResult.calculateScore(hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc, LyricsSource.youlyPlus),
          );
        }
      }

      // Priority 3: plainLyrics
      final plain = body['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        final plainLines = plain.split('\n').map((l) => LyricsLine(startTime: Duration.zero, text: l.trim())).where((l) => l.text.isNotEmpty).toList();
        return LyricsResult(
          trackTitle: title,
          artist: artist,
          format: LyricsFormat.plainText,
          source: LyricsSource.youlyPlus,
          rawLyrics: plain,
          lines: plainLines,
          qualityScore: LyricsResult.calculateScore(LyricsFormat.plainText, LyricsSource.youlyPlus),
        );
      }
    } catch (_) {}
    return null;
  }
}
