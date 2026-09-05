import 'models.dart';

/// Sync fidelity and format of lyrics
enum LyricsFormat {
  ttml,       // Word-by-word karaoke sync (Apple Music TTML / YRC)
  syncedLrc,  // Line-by-line synced LRC
  plainText,  // Unsynced static lyrics
}

/// Provider sources for lyrics retrieval
enum LyricsSource {
  appleMusic,
  lrclib,
  netease,
}

/// Represents an individual timed word within a karaoke/TTML line
class LyricsWord {
  final String text;
  final Duration startTime;
  final Duration endTime;

  const LyricsWord({
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'startTimeMs': startTime.inMilliseconds,
    'endTimeMs': endTime.inMilliseconds,
  };

  factory LyricsWord.fromJson(Map<String, dynamic> json) => LyricsWord(
    text: json['text'] as String,
    startTime: Duration(milliseconds: json['startTimeMs'] as int),
    endTime: Duration(milliseconds: json['endTimeMs'] as int),
  );
}

/// Represents a line of lyrics with start time, optional end time, and words
class LyricsLine {
  final Duration startTime;
  final Duration? endTime;
  final String text;
  final List<LyricsWord>? words;
  final String? translation;

  const LyricsLine({
    required this.startTime,
    this.endTime,
    required this.text,
    this.words,
    this.translation,
  });

  bool get hasWordTiming => words != null && words!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'startTimeMs': startTime.inMilliseconds,
    'endTimeMs': endTime?.inMilliseconds,
    'text': text,
    'words': words?.map((w) => w.toJson()).toList(),
    'translation': translation,
  };

  factory LyricsLine.fromJson(Map<String, dynamic> json) => LyricsLine(
    startTime: Duration(milliseconds: json['startTimeMs'] as int),
    endTime: json['endTimeMs'] != null ? Duration(milliseconds: json['endTimeMs'] as int) : null,
    text: json['text'] as String,
    words: (json['words'] as List<dynamic>?)
        ?.map((w) => LyricsWord.fromJson(w as Map<String, dynamic>))
        .toList(),
    translation: json['translation'] as String?,
  );
}

/// Standardized lyrics payload returned by providers and the unified engine
class LyricsResult {
  final String trackTitle;
  final String artist;
  final LyricsFormat format;
  final LyricsSource source;
  final String rawLyrics;
  final List<LyricsLine> lines;
  final bool isInstrumental;
  final int qualityScore;

  const LyricsResult({
    required this.trackTitle,
    required this.artist,
    required this.format,
    required this.source,
    required this.rawLyrics,
    this.lines = const [],
    this.isInstrumental = false,
    required this.qualityScore,
  });

  /// Calculates the quality ranking score:
  /// 1. TTML (Apple Music) = 1000
  /// 2. SyncedLrc (LRCLIB) = 800 (Primary line-by-line, cleaner English)
  /// 3. SyncedLrc (Netease) = 700 (Secondary line-by-line, regional gaps)
  /// 4. PlainText (LRCLIB) = 400
  /// 5. PlainText (Netease) = 300
  /// 6. PlainText (Apple Music) = 200
  static int calculateScore(LyricsFormat format, LyricsSource source, {bool isInstrumental = false}) {
    if (isInstrumental) {
      return 900; // Instrumental metadata is high value
    }
    switch (format) {
      case LyricsFormat.ttml:
        return 1000;
      case LyricsFormat.syncedLrc:
        if (source == LyricsSource.lrclib) return 800;
        if (source == LyricsSource.netease) return 700;
        return 600;
      case LyricsFormat.plainText:
        if (source == LyricsSource.lrclib) return 400;
        if (source == LyricsSource.netease) return 300;
        return 200;
    }
  }
}

/// Base contract for individual lyrics source providers
abstract class LyricsProviderContract {
  LyricsSource get source;
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  });
}

/// Unified lyrics aggregation contract consumed by UI Shell (Module 5)
abstract class LyricsContract {
  Future<LyricsResult?> fetchLyrics(Track track);
}
