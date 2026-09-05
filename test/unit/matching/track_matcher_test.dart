import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/matching/track_matcher.dart';

void main() {
  group('TrackMatcher Tests', () {
    test('normalizeString strips bracketed annotations, lowercases, and removes punctuation', () {
      expect(TrackMatcher.normalizeString('One More Time (12" Mix) [Remastered]'), 'one more time');
      expect(TrackMatcher.normalizeString('Out of My League (Deluxe Version)'), 'out of my league');
      expect(TrackMatcher.normalizeString('TVK Campaign Song - Single'), 'tvk campaign song single');
    });

    test('compareStrings calculates token sort ratio accurately', () {
      final scoreExact = TrackMatcher.compareStrings('One More Time', 'one more time');
      expect(scoreExact, 100.0);

      final scoreFuzzy = TrackMatcher.compareStrings('Fitz & The Tantrums', 'Fitz and The Tantrums');
      expect(scoreFuzzy, greaterThanOrEqualTo(80.0));
    });

    test('compareDuration awards 100 within tolerance and degrades gracefully', () {
      expect(TrackMatcher.compareDuration(210, 212, toleranceSec: 5), 100.0);
      expect(TrackMatcher.compareDuration(210, 218, toleranceSec: 5), 70.0);
      expect(TrackMatcher.compareDuration(210, 228, toleranceSec: 5), 30.0);
      expect(TrackMatcher.compareDuration(210, 250, toleranceSec: 5), 0.0);
      expect(TrackMatcher.compareDuration(0, 210), 50.0);
    });

    test('scoreTrackMatch returns high score on matching track and low score on mismatch', () {
      final matchScore = TrackMatcher.scoreTrackMatch(
        targetTitle: 'Out of My League',
        targetArtist: 'Fitz and The Tantrums',
        candidateTitle: 'Out of My League',
        candidateArtist: 'Fitz and The Tantrums',
        targetDuration: 211,
        candidateDuration: 211,
      );
      expect(matchScore, greaterThanOrEqualTo(90.0));

      final mismatchScore = TrackMatcher.scoreTrackMatch(
        targetTitle: 'Out of My League',
        targetArtist: 'Fitz and The Tantrums',
        candidateTitle: 'Completely Different Song',
        candidateArtist: 'Another Artist',
        targetDuration: 211,
        candidateDuration: 180,
      );
      expect(mismatchScore, lessThan(40.0));
    });
  });
}
