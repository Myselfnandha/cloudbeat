import '../../../core/contracts/lyrics_contract.dart';

class LrcParser {
  static final RegExp _timestampRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
  static final RegExp _yrcWordRegex = RegExp(r'\((\d+),(\d+),\d+\)([^(\n]+)');

  /// Parses a string containing LRC or YRC formatted lyrics into a list of [LyricsLine].
  static List<LyricsLine> parse(String content) {
    final lines = <LyricsLine>[];
    final rawLines = content.split('\n');

    for (final rawLine in rawLines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      // Check for YRC timestamp format: [start_ms, duration_ms]
      if (trimmed.startsWith('[') && trimmed.contains('](')) {
        final yrcParsed = _parseYrcLine(trimmed);
        if (yrcParsed != null) {
          lines.add(yrcParsed);
          continue;
        }
      }

      // Standard LRC parsing
      final matches = _timestampRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      final text = trimmed.replaceAll(_timestampRegex, '').trim();
      if (text.isEmpty && matches.length == 1) {
        // Empty text line (e.g. spacer timestamp)
        continue;
      }

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final millisStr = match.group(3) ?? '0';
        final millis = _parseMilliseconds(millisStr);

        final startTime = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        );

        lines.add(LyricsLine(
          startTime: startTime,
          text: text,
        ));
      }
    }

    // Sort chronologically
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Calculate end times for adjacent lines
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].endTime == null && i + 1 < lines.length) {
        final nextStart = lines[i + 1].startTime;
        lines[i] = LyricsLine(
          startTime: lines[i].startTime,
          endTime: nextStart,
          text: lines[i].text,
          words: lines[i].words,
          translation: lines[i].translation,
        );
      }
    }

    return lines;
  }

  static LyricsLine? _parseYrcLine(String line) {
    try {
      final headerEnd = line.indexOf(']');
      if (headerEnd == -1) return null;

      final header = line.substring(1, headerEnd);
      final parts = header.split(',');
      if (parts.length < 2) return null;

      final startMs = int.tryParse(parts[0].trim()) ?? 0;
      final spanMs = int.tryParse(parts[1].trim()) ?? 0;

      final rest = line.substring(headerEnd + 1);
      final words = <LyricsWord>[];
      final textBuffer = StringBuffer();

      final wordMatches = _yrcWordRegex.allMatches(rest);
      for (final match in wordMatches) {
        final atMs = int.tryParse(match.group(1) ?? '0') ?? 0;
        final durMs = int.tryParse(match.group(2) ?? '0') ?? 0;
        final wordText = match.group(3) ?? '';

        words.add(LyricsWord(
          text: wordText,
          startTime: Duration(milliseconds: atMs),
          endTime: Duration(milliseconds: atMs + durMs),
        ));
        textBuffer.write(wordText);
      }

      final fullText = textBuffer.toString().trim().isNotEmpty
          ? textBuffer.toString().trim()
          : rest.replaceAll(RegExp(r'\(\d+,\d+,\d+\)'), '').trim();

      if (fullText.isEmpty) return null;

      return LyricsLine(
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: startMs + spanMs),
        text: fullText,
        words: words.isNotEmpty ? words : null,
      );
    } catch (_) {
      return null;
    }
  }

  static int _parseMilliseconds(String raw) {
    if (raw.length == 1) return (int.tryParse(raw) ?? 0) * 100;
    if (raw.length == 2) return (int.tryParse(raw) ?? 0) * 10;
    if (raw.length >= 3) return int.tryParse(raw.substring(0, 3)) ?? 0;
    return 0;
  }
}
