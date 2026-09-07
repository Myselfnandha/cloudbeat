import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/matching/track_matcher.dart';

void main() {
  group('TrackMatcher Contamination & Purity Tests', () {
    test('isContaminatedCandidate flags movie dialogue, jukebox, karaoke, promos', () {
      expect(
        TrackMatcher.isContaminatedCandidate(
          candidateTitle: 'Naan Ready (Dialogue & BGM Extract)',
          candidateArtist: 'Vijay',
          targetTitle: 'Naan Ready',
          targetArtist: 'Anirudh Ravichander',
        ),
        isTrue,
      );

      expect(
        TrackMatcher.isContaminatedCandidate(
          candidateTitle: 'Master All Songs Audio Jukebox',
          candidateArtist: 'Anirudh Ravichander',
          targetTitle: 'Vaathi Coming',
          targetArtist: 'Anirudh Ravichander',
        ),
        isTrue,
      );

      expect(
        TrackMatcher.isContaminatedCandidate(
          candidateTitle: 'Arabic Kuthu - Karaoke Version',
          candidateArtist: 'Anirudh Ravichander',
          targetTitle: 'Arabic Kuthu',
          targetArtist: 'Anirudh Ravichander',
        ),
        isTrue,
      );

      expect(
        TrackMatcher.isContaminatedCandidate(
          candidateTitle: 'Hukum Ringtone Cut Song',
          candidateArtist: 'Anirudh Ravichander',
          targetTitle: 'Hukum',
          targetArtist: 'Anirudh Ravichander',
        ),
        isTrue,
      );
    });

    test('isContaminatedCandidate allows legitimate tracks matching user query', () {
      expect(
        TrackMatcher.isContaminatedCandidate(
          candidateTitle: 'Naan Ready',
          candidateArtist: 'Anirudh Ravichander',
          targetTitle: 'Naan Ready',
          targetArtist: 'Anirudh Ravichander',
        ),
        isFalse,
      );

      // If user specifically searched for remix, do not flag remix
      expect(
        TrackMatcher.isContaminatedCandidate(
          candidateTitle: 'Naan Ready (Club Remix)',
          candidateArtist: 'Anirudh Ravichander',
          targetTitle: 'Naan Ready Remix',
          targetArtist: 'Anirudh Ravichander',
        ),
        isFalse,
      );
    });

    test('isContaminatedCandidate flags movie uploader channels', () {
      expect(
        TrackMatcher.isContaminatedCandidate(
          candidateTitle: 'Badass Song',
          candidateArtist: 'Sun TV Movies Clips',
          targetTitle: 'Badass',
          targetArtist: 'Anirudh Ravichander',
        ),
        isTrue,
      );
    });

    test('isDurationSuspicious detects snippets and massive compilations', () {
      // Snippet: 35s candidate vs 210s target
      expect(TrackMatcher.isDurationSuspicious(210, 35), isTrue);

      // Jukebox: 1800s candidate vs 240s target
      expect(TrackMatcher.isDurationSuspicious(240, 1800), isTrue);

      // >30% variance
      expect(TrackMatcher.isDurationSuspicious(200, 270), isTrue);

      // Close duration: 210s vs 215s
      expect(TrackMatcher.isDurationSuspicious(210, 215), isFalse);
    });

    test('scoreTrackMatch heavily penalizes contaminated or suspicious candidates', () {
      final cleanScore = TrackMatcher.scoreTrackMatch(
        targetTitle: 'Vaathi Coming',
        targetArtist: 'Anirudh Ravichander',
        candidateTitle: 'Vaathi Coming',
        candidateArtist: 'Anirudh Ravichander',
        targetDuration: 230,
        candidateDuration: 230,
      );

      final contaminatedScore = TrackMatcher.scoreTrackMatch(
        targetTitle: 'Vaathi Coming',
        targetArtist: 'Anirudh Ravichander',
        candidateTitle: 'Vaathi Coming Movie Dialogue Scenes',
        candidateArtist: 'Anirudh Ravichander',
        targetDuration: 230,
        candidateDuration: 230,
      );

      final jukeboxScore = TrackMatcher.scoreTrackMatch(
        targetTitle: 'Vaathi Coming',
        targetArtist: 'Anirudh Ravichander',
        candidateTitle: 'Master Audio Jukebox All Songs',
        candidateArtist: 'Anirudh Ravichander',
        targetDuration: 230,
        candidateDuration: 2400,
      );

      expect(cleanScore, greaterThanOrEqualTo(90.0));
      expect(contaminatedScore, lessThan(cleanScore - 30.0));
      expect(jukeboxScore, lessThan(35.0));
    });
  });
}
