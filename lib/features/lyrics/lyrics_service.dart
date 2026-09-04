import 'dart:convert';
import 'package:http/http.dart' as http;
import 'indic_transliteration.dart';

class LyricLine {
  final Duration timestamp;
  final String text;
  final String? transliteratedText;

  const LyricLine({
    required this.timestamp,
    required this.text,
    this.transliteratedText,
  });

  /// Returns the transliterated line if [transliterate] is true and transliteration exists,
  /// otherwise returns the original script text.
  String getDisplayText({bool transliterate = false}) {
    if (transliterate && transliteratedText != null && transliteratedText!.isNotEmpty) {
      return transliteratedText!;
    }
    return text;
  }

  @override
  String toString() => '[${timestamp.inMilliseconds}ms]: $text';
}

class SyncedLyrics {
  final String? plainLyrics;
  final String? transliteratedPlainLyrics;
  final List<LyricLine> lines;
  final bool isSynced;

  const SyncedLyrics({
    this.plainLyrics,
    this.transliteratedPlainLyrics,
    this.lines = const [],
    this.isSynced = false,
  });

  int getActiveIndex(Duration currentPosition) {
    if (lines.isEmpty) return -1;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (currentPosition >= lines[i].timestamp) {
        return i;
      }
    }
    return 0;
  }

  /// Creates a copy with transliteration applied to all lines and plain lyrics
  SyncedLyrics withTransliteration() {
    final transliteratedLines = lines.map((l) {
      final trans = IndicTransliterator.containsIndic(l.text)
          ? IndicTransliterator.transliterate(l.text)
          : l.transliteratedText;
      return LyricLine(
        timestamp: l.timestamp,
        text: l.text,
        transliteratedText: trans,
      );
    }).toList();

    final transPlain = (plainLyrics != null && IndicTransliterator.containsIndic(plainLyrics!))
        ? IndicTransliterator.transliterate(plainLyrics!)
        : transliteratedPlainLyrics;

    return SyncedLyrics(
      plainLyrics: plainLyrics,
      transliteratedPlainLyrics: transPlain,
      lines: transliteratedLines,
      isSynced: isSynced,
    );
  }
}

class LyricsService {
  final http.Client _httpClient;

  LyricsService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  /// Transliterates text containing Indic scripts to phonetic Roman script
  String transliterateIndic(String text) {
    return IndicTransliterator.transliterate(text);
  }

  /// Parse LRC text format: [mm:ss.xx] Lyric text
  List<LyricLine> parseLrc(String lrcContent, {bool autoTransliterate = true}) {
    final lines = <LyricLine>[];
    final regExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

    for (final rawLine in const LineSplitter().convert(lrcContent)) {
      final match = regExp.firstMatch(rawLine.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final msString = match.group(3)!;
        final ms = msString.length == 2 ? int.parse(msString) * 10 : int.parse(msString);
        final text = match.group(4)!.trim();

        String? transliterated;
        if (autoTransliterate && IndicTransliterator.containsIndic(text)) {
          transliterated = IndicTransliterator.transliterate(text);
        }

        lines.add(LyricLine(
          timestamp: Duration(minutes: minutes, seconds: seconds, milliseconds: ms),
          text: text,
          transliteratedText: transliterated,
        ));
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  /// Query LRCLIB public API for synchronized lyrics
  Future<SyncedLyrics?> fetchLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
    bool enableTransliteration = true,
  }) async {
    final queryParams = <String, String>{
      'track_name': trackName,
      'artist_name': artistName,
    };
    if (albumName != null) queryParams['album_name'] = albumName;
    if (durationSeconds != null) queryParams['duration'] = durationSeconds.toString();

    final uri = Uri.https('lrclib.net', '/api/get', queryParams);

    try {
      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final syncedLyricsText = data['syncedLyrics'] as String?;
        final plainLyricsText = data['plainLyrics'] as String?;

        if (syncedLyricsText != null && syncedLyricsText.isNotEmpty) {
          final parsedLines = parseLrc(syncedLyricsText, autoTransliterate: enableTransliteration);
          final transPlain = (enableTransliteration && plainLyricsText != null && IndicTransliterator.containsIndic(plainLyricsText))
              ? IndicTransliterator.transliterate(plainLyricsText)
              : null;

          return SyncedLyrics(
            plainLyrics: plainLyricsText,
            transliteratedPlainLyrics: transPlain,
            lines: parsedLines,
            isSynced: true,
          );
        } else if (plainLyricsText != null && plainLyricsText.isNotEmpty) {
          final transPlain = (enableTransliteration && IndicTransliterator.containsIndic(plainLyricsText))
              ? IndicTransliterator.transliterate(plainLyricsText)
              : null;

          return SyncedLyrics(
            plainLyrics: plainLyricsText,
            transliteratedPlainLyrics: transPlain,
            lines: const [],
            isSynced: false,
          );
        }
      }
    } catch (_) {}

    return null;
  }
}
