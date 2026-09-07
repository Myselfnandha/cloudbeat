import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/services/app_logger.dart';

class LrcParser {
  static final RegExp _timestampRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
  static final RegExp _yrcWordRegex = RegExp(r'\((\d+),(\d+),\d+\)([^(\n]+)');
  static final RegExp _bgLineRegex = RegExp(r'^\[bg:\s*(.*)\]$', caseSensitive: false);
  static final RegExp _agentTagRegex = RegExp(r'\{(agent:)?(v\d+)\}|\((v\d+)\):?', caseSensitive: false);
  static final RegExp _inlineWordRegex = RegExp(r'<(\d{1,2}):(\d{2})\.(\d{2,3})>([^<]+)');

  /// Parses a string containing LRC, ELRC, YRC, or syllable formatted lyrics into a list of [LyricsLine].
  static List<LyricsLine> parse(String content) {
    AppLogger.trace('LrcParser', 'parse', {'length': content.length});
    final lines = <LyricsLine>[];
    final rawLines = content.split('\n');

    LyricsLine? lastLine;

    for (int lineIdx = 0; lineIdx < rawLines.length; lineIdx++) {
      final trimmed = rawLines[lineIdx].trim();
      if (trimmed.isEmpty) continue;

      // 1. Check for standalone multiline words tag `<word:start:end|...>` following a lyric line
      if (trimmed.startsWith('<') && trimmed.endsWith('>') && trimmed.contains(':') && lastLine != null) {
        final parsedWords = _parseStandaloneWordsTag(trimmed, lastLine.startTime);
        if (parsedWords.isNotEmpty) {
          final updated = LyricsLine(
            startTime: lastLine.startTime,
            endTime: lastLine.endTime,
            text: lastLine.text,
            words: parsedWords,
            translation: lastLine.translation,
            isBackground: lastLine.isBackground,
            singerAgent: lastLine.singerAgent,
          );
          lines[lines.length - 1] = updated;
          lastLine = updated;
          continue;
        }
      }

      // 2. Check for [bg: ...] format
      final bgMatch = _bgLineRegex.firstMatch(trimmed);
      if (bgMatch != null) {
        final text = bgMatch.group(1)?.trim() ?? '';
        if (text.isNotEmpty) {
          final parsed = _parseStandardLrcLine(text, isBgOverride: true);
          if (parsed != null) {
            lines.add(parsed);
            lastLine = parsed;
            continue;
          }
        }
      }

      // 3. Check for YRC timestamp format: [start_ms, duration_ms]
      if (trimmed.startsWith('[') && trimmed.contains('](')) {
        final yrcParsed = _parseYrcLine(trimmed);
        if (yrcParsed != null) {
          lines.add(yrcParsed);
          lastLine = yrcParsed;
          continue;
        }
      }

      // 4. Standard LRC parsing with agent / {bg} detection
      final matches = _timestampRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      final parsed = _parseStandardLrcLine(trimmed);
      if (parsed != null) {
        lines.add(parsed);
        lastLine = parsed;
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
          isBackground: lines[i].isBackground,
          singerAgent: lines[i].singerAgent,
        );
      }
    }

    return lines;
  }

  static LyricsLine? _parseStandardLrcLine(String rawLine, {bool isBgOverride = false}) {
    final match = _timestampRegex.firstMatch(rawLine);
    if (match == null) return null;

    final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
    final millisStr = match.group(3) ?? '0';
    final millis = _parseMilliseconds(millisStr);
    final startTime = Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );

    var text = rawLine.replaceAll(_timestampRegex, '').trim();
    bool isBackground = isBgOverride;
    String? singerAgent;

    // Check {bg} prefix or [bg: ...] tag
    if (text.contains('{bg}') || text.startsWith('(bg)') || text.contains('[bg:') || text.startsWith('bg:')) {
      isBackground = true;
      text = text
          .replaceAll('{bg}', '')
          .replaceAll(RegExp(r'^\(bg\)\s*'), '')
          .replaceAll(RegExp(r'\[bg:\s*'), '')
          .replaceAll(RegExp(r'^bg:\s*'), '')
          .replaceAll(RegExp(r'\]$'), '')
          .trim();
    }

    // Check agent tags: {agent:v1}, {agent:v2}, {v1}, (v1):
    final agentMatch = _agentTagRegex.firstMatch(text);
    if (agentMatch != null) {
      singerAgent = (agentMatch.group(2) ?? agentMatch.group(3) ?? '').toLowerCase();
      text = text.replaceFirst(_agentTagRegex, '').trim();
    }

    // Check for inline syllable timestamps like <00:12.34>Word1 <00:13.10>Word2
    final words = <LyricsWord>[];
    if (text.contains('<') && text.contains('>')) {
      final inlineMatches = _inlineWordRegex.allMatches(text).toList();
      if (inlineMatches.isNotEmpty) {
        for (int i = 0; i < inlineMatches.length; i++) {
          final m = inlineMatches[i];
          final wMin = int.tryParse(m.group(1) ?? '0') ?? 0;
          final wSec = int.tryParse(m.group(2) ?? '0') ?? 0;
          final wMs = _parseMilliseconds(m.group(3) ?? '0');
          final wStart = Duration(minutes: wMin, seconds: wSec, milliseconds: wMs);
          final wText = m.group(4)?.trim() ?? '';

          Duration wEnd;
          if (i + 1 < inlineMatches.length) {
            final nextM = inlineMatches[i + 1];
            final nMin = int.tryParse(nextM.group(1) ?? '0') ?? 0;
            final nSec = int.tryParse(nextM.group(2) ?? '0') ?? 0;
            final nMs = _parseMilliseconds(nextM.group(3) ?? '0');
            wEnd = Duration(minutes: nMin, seconds: nSec, milliseconds: nMs);
          } else {
            wEnd = wStart + const Duration(milliseconds: 600);
          }

          if (wText.isNotEmpty) {
            words.add(LyricsWord(text: wText, startTime: wStart, endTime: wEnd));
          }
        }
        text = text.replaceAll(RegExp(r'<\d{1,2}:\d{2}\.\d{2,3}>'), '').trim();
      }
    }

    if (text.isEmpty && words.isEmpty) return null;

    return LyricsLine(
      startTime: startTime,
      text: text,
      words: words.isNotEmpty ? words : null,
      isBackground: isBackground,
      singerAgent: singerAgent,
    );
  }

  static List<LyricsWord> _parseStandaloneWordsTag(String tagContent, Duration lineStart) {
    final clean = tagContent.replaceAll(RegExp(r'^<|>$'), '');
    final segments = clean.split('|');
    final words = <LyricsWord>[];

    for (final seg in segments) {
      final parts = seg.split(':');
      if (parts.length >= 3) {
        final text = parts[0];
        final startSec = double.tryParse(parts[1]) ?? 0;
        final endSec = double.tryParse(parts[2]) ?? (startSec + 0.5);
        words.add(LyricsWord(
          text: text,
          startTime: Duration(milliseconds: (startSec * 1000).round()),
          endTime: Duration(milliseconds: (endSec * 1000).round()),
        ));
      }
    }
    return words;
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
