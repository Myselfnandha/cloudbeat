import '../../../core/contracts/lyrics_contract.dart';

class TtmlParser {
  static final RegExp _pTagRegex = RegExp(
    r'<p\b([^>]*)>(.*?)</p>',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _spanTagRegex = RegExp(
    r'<span\b([^>]*)>(.*?)</span>',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _attrBeginRegex = RegExp(r'begin="([^"]+)"', caseSensitive: false);
  static final RegExp _attrEndRegex = RegExp(r'end="([^"]+)"', caseSensitive: false);

  /// Parses TTML XML lyrics into structured [LyricsLine] list with word-level spans.
  static List<LyricsLine> parse(String ttmlContent) {
    final lines = <LyricsLine>[];
    final pMatches = _pTagRegex.allMatches(ttmlContent);

    for (final pMatch in pMatches) {
      final pAttrs = pMatch.group(1) ?? '';
      final pInner = pMatch.group(2) ?? '';

      final beginStr = _attrBeginRegex.firstMatch(pAttrs)?.group(1);
      final endStr = _attrEndRegex.firstMatch(pAttrs)?.group(1);

      final lineStartTime = _parseTimestamp(beginStr);
      final lineEndTime = _parseTimestamp(endStr);

      if (lineStartTime == null) continue;

      final words = <LyricsWord>[];
      final spanMatches = _spanTagRegex.allMatches(pInner);
      final textBuffer = StringBuffer();

      if (spanMatches.isNotEmpty) {
        for (final sMatch in spanMatches) {
          final sAttrs = sMatch.group(1) ?? '';
          final sText = _stripHtml(sMatch.group(2) ?? '');

          final sBegin = _parseTimestamp(_attrBeginRegex.firstMatch(sAttrs)?.group(1)) ?? lineStartTime;
          final sEnd = _parseTimestamp(_attrEndRegex.firstMatch(sAttrs)?.group(1)) ?? (lineEndTime ?? sBegin);

          if (sText.isNotEmpty) {
            words.add(LyricsWord(
              text: sText,
              startTime: sBegin,
              endTime: sEnd,
            ));
            textBuffer.write(sText);
          }
        }
      }

      var fullText = textBuffer.toString();
      if (fullText.trim().isEmpty) {
        fullText = _stripHtml(pInner);
      }

      if (fullText.trim().isEmpty) continue;

      lines.add(LyricsLine(
        startTime: lineStartTime,
        endTime: lineEndTime,
        text: fullText.trim(),
        words: words.isNotEmpty ? words : null,
      ));
    }

    lines.sort((a, b) => a.startTime.compareTo(b.startTime));
    return lines;
  }

  static Duration? _parseTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.trim().isEmpty) return null;
    final clean = timestamp.trim();

    // Format: 1234ms or 12.34s
    if (clean.endsWith('ms')) {
      final ms = int.tryParse(clean.replaceAll('ms', ''));
      return ms != null ? Duration(milliseconds: ms) : null;
    }
    if (clean.endsWith('s')) {
      final s = double.tryParse(clean.replaceAll('s', ''));
      return s != null ? Duration(milliseconds: (s * 1000).round()) : null;
    }

    // Format: [hh:]mm:ss.xxx or ss.xxx
    final parts = clean.split(':');
    try {
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final seconds = double.parse(parts[2]);
        return Duration(
          hours: hours,
          minutes: minutes,
          milliseconds: (seconds * 1000).round(),
        );
      } else if (parts.length == 2) {
        final minutes = int.parse(parts[0]);
        final seconds = double.parse(parts[1]);
        return Duration(
          minutes: minutes,
          milliseconds: (seconds * 1000).round(),
        );
      } else if (parts.length == 1) {
        final seconds = double.parse(parts[0]);
        return Duration(
          milliseconds: (seconds * 1000).round(),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>');
  }
}
