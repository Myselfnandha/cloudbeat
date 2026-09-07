import 'dart:math';

/// SongStore-compatible fuzzy track candidate matching and scoring utility.
class TrackMatcher {
  static final RegExp _cleanBracketRegex = RegExp(r'[\(\[\{].*?[\)\]\}]');
  static final RegExp _nonAlphaNumRegex = RegExp(r'[^a-z0-9\s]');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  /// Normalizes string by removing bracketed annotations, lowercasing, and stripping punctuation.
  static String normalizeString(String? s) {
    if (s == null || s.trim().isEmpty) return '';
    var clean = s.replaceAll(_cleanBracketRegex, ' ');
    clean = clean.toLowerCase();
    clean = clean.replaceAll(_nonAlphaNumRegex, ' ');
    return clean.replaceAll(_whitespaceRegex, ' ').trim();
  }

  /// Calculates token sort similarity ratio (0.0 to 100.0).
  static double compareStrings(String s1, String s2) {
    final n1 = normalizeString(s1);
    final n2 = normalizeString(s2);
    if (n1.isEmpty || n2.isEmpty) return 0.0;
    if (n1 == n2) return 100.0;

    final tokens1 = n1.split(' ')..sort();
    final tokens2 = n2.split(' ')..sort();

    final sorted1 = tokens1.join(' ');
    final sorted2 = tokens2.join(' ');

    return _levenshteinRatio(sorted1, sorted2) * 100.0;
  }

  /// Keywords indicating audio contamination (movie dialogue, jukeboxes, promos, karaoke, etc.)
  static const List<String> contaminationKeywords = [
    'dialogue',
    'dialogues',
    'bgm',
    'theme music',
    'ringtone',
    'ringtones',
    'karaoke',
    'instrumental',
    'jukebox',
    'audio jukebox',
    'video jukebox',
    'all songs',
    'best of',
    'top hits',
    'nonstop',
    'non stop',
    'mashup',
    'teaser',
    'trailer',
    'motion poster',
    'promo',
    'scenes',
    'scene',
    'cut songs',
    'full movie',
    'status video',
    'shorts',
  ];

  /// Checks if candidate title or artist contains contamination keywords not present in target.
  static bool isContaminatedCandidate({
    required String candidateTitle,
    required String candidateArtist,
    String targetTitle = '',
    String targetArtist = '',
  }) {
    final candTitleLower = candidateTitle.toLowerCase();
    final candArtistLower = candidateArtist.toLowerCase();
    final targetTitleLower = targetTitle.toLowerCase();
    final targetArtistLower = targetArtist.toLowerCase();

    for (final kw in contaminationKeywords) {
      // If target title itself sought karaoke/remix/bgm, don't flag as contamination
      if (targetTitleLower.contains(kw) || targetArtistLower.contains(kw)) {
        continue;
      }
      // Check candidate title
      if (candTitleLower.contains(kw)) {
        return true;
      }
    }

    // Check suspicious uploader/artist words like "movies", "film companion", "scene clips"
    // when target artist is a real music artist
    final suspiciousUploaders = ['movies', 'film factory', 'serial', 'tv', 'cinema hub', 'movie scenes'];
    for (final su in suspiciousUploaders) {
      if (!targetArtistLower.contains(su) && candArtistLower.contains(su)) {
        return true;
      }
    }

    return false;
  }

  /// Checks whether candidate duration deviates suspiciously from target (>30% variance or jukebox/snippet).
  static bool isDurationSuspicious(int targetDurationSec, int candidateDurationSec) {
    if (targetDurationSec <= 0 || candidateDurationSec <= 0) return false;

    // Reject short snippets (<60s when target is a full track >90s)
    if (candidateDurationSec < 60 && targetDurationSec >= 90) return true;

    // Reject giant compilations/jukeboxes (>10m when target is typical track <7m)
    if (candidateDurationSec > 600 && targetDurationSec < 420) return true;

    // General >30% variance threshold
    final diff = (targetDurationSec - candidateDurationSec).abs();
    final maxAllowedDiff = (targetDurationSec * 0.30).round();
    return diff > maxAllowedDiff;
  }

  /// Score duration difference (100 if <= toleranceSec, degrades with gap).
  static double compareDuration(int d1, int d2, {int toleranceSec = 5}) {
    if (d1 <= 0 || d2 <= 0) return 50.0; // neutral if unknown
    final diff = (d1 - d2).abs();
    if (diff <= toleranceSec) return 100.0;
    if (diff <= toleranceSec * 2) return 70.0;
    if (diff <= 20) return 30.0;
    return 0.0;
  }

  /// Calculate weighted similarity score between target and candidate track (0.0 to 100.0).
  static double scoreTrackMatch({
    required String targetTitle,
    required String targetArtist,
    required String candidateTitle,
    required String candidateArtist,
    int targetDuration = 0,
    int candidateDuration = 0,
    String? targetAlbum,
    String? candidateAlbum,
  }) {
    final titleScore = compareStrings(targetTitle, candidateTitle);
    final isGenericArtist = targetArtist.isEmpty || targetArtist.toLowerCase().contains('various');

    double rawScore = 0.0;

    if (isGenericArtist) {
      if (targetAlbum != null && candidateAlbum != null && targetAlbum.isNotEmpty && candidateAlbum.isNotEmpty) {
        final albumScore = compareStrings(targetAlbum, candidateAlbum);
        final durScore = compareDuration(targetDuration, candidateDuration);
        rawScore = (titleScore * 0.70) + (albumScore * 0.20) + (durScore * 0.10);
      } else {
        final durScore = compareDuration(targetDuration, candidateDuration);
        rawScore = (titleScore * 0.85) + (durScore * 0.15);
      }
    } else {
      final artistScore = compareStrings(targetArtist, candidateArtist);

      if (targetAlbum != null && candidateAlbum != null && targetAlbum.isNotEmpty && candidateAlbum.isNotEmpty) {
        final albumScore = compareStrings(targetAlbum, candidateAlbum);
        final durScore = compareDuration(targetDuration, candidateDuration);
        rawScore = (titleScore * 0.50) + (artistScore * 0.30) + (albumScore * 0.10) + (durScore * 0.10);
      } else {
        final durScore = compareDuration(targetDuration, candidateDuration);
        rawScore = (titleScore * 0.60) + (artistScore * 0.30) + (durScore * 0.10);
      }
    }

    // Apply Clean Stream penalties
    if (isContaminatedCandidate(
      candidateTitle: candidateTitle,
      candidateArtist: candidateArtist,
      targetTitle: targetTitle,
      targetArtist: targetArtist,
    )) {
      rawScore = max(0.0, rawScore - 40.0);
    }

    if (isDurationSuspicious(targetDuration, candidateDuration)) {
      rawScore = max(0.0, rawScore - 35.0);
    }

    return rawScore;
  }

  static double _levenshteinRatio(String s1, String s2) {
    if (s1 == s2) return 1.0;
    final len1 = s1.length;
    final len2 = s2.length;
    if (len1 == 0 || len2 == 0) return 0.0;

    final d = List.generate(len1 + 1, (i) => List<int>.filled(len2 + 1, 0));
    for (int i = 0; i <= len1; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        d[i][j] = min(d[i - 1][j] + 1, min(d[i][j - 1] + 1, d[i - 1][j - 1] + cost));
      }
    }

    final maxLen = max(len1, len2);
    return (maxLen - d[len1][len2]) / maxLen;
  }
}
