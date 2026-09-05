import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/acquisition_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/ui_shell/search/deduplication_matcher.dart';

void main() {
  group('DeduplicationMatcher', () {
    final now = DateTime.now();

    final vaultTrack1 = Track(
      id: 'vault-1',
      title: 'Starboy',
      artists: ['The Weeknd', 'Daft Punk'],
      album: 'Starboy',
      durationSeconds: 230,
      addedAt: now,
      isrc: 'USUG11600854',
    );

    final vaultTrack2 = Track(
      id: 'vault-2',
      title: 'Blinding Lights (Remix)',
      artists: ['The Weeknd'],
      album: 'After Hours',
      durationSeconds: 200,
      addedAt: now,
      isrc: null,
    );

    final vaultTracks = [vaultTrack1, vaultTrack2];

    test('Path A: matches identical ISRC even if case or hyphens differ', () {
      final searchResult = ExternalTrackResult(
        id: 'deezer-1',
        title: 'Starboy (Official Video)',
        artists: ['The Weeknd'],
        album: 'Starboy',
        durationSeconds: 230,
        backend: 'deezer',
        availableQualities: [AudioQuality.flac16Bit],
        isrc: 'US-UG1-16-00854',
      );

      final match = DeduplicationMatcher.findMatch(searchResult, vaultTracks);
      expect(match, isNotNull);
      expect(match!.id, equals('vault-1'));
      expect(DeduplicationMatcher.isVaulted(searchResult, vaultTracks), isTrue);
    });

    test('Path B: matches normalized title and artist within duration proximity (<= 3s)', () {
      final searchResult = ExternalTrackResult(
        id: 'qobuz-2',
        title: '  Blinding Lights   (Remix) ',
        artists: ['the weeknd'],
        album: 'After Hours (Deluxe)',
        durationSeconds: 202, // delta = 2s <= 3s
        backend: 'qobuz',
        availableQualities: [AudioQuality.flac24Bit],
        isrc: null,
      );

      final match = DeduplicationMatcher.findMatch(searchResult, vaultTracks);
      expect(match, isNotNull);
      expect(match!.id, equals('vault-2'));
      expect(DeduplicationMatcher.isVaulted(searchResult, vaultTracks), isTrue);
    });

    test('Path C: rejects match when title/artist match but duration exceeds 3s threshold (e.g. extended mix/cover)', () {
      final extendedMix = ExternalTrackResult(
        id: 'tidal-3',
        title: 'Blinding Lights (Remix)',
        artists: ['The Weeknd'],
        album: 'After Hours',
        durationSeconds: 205, // delta = 5s > 3s
        backend: 'tidal',
        availableQualities: [AudioQuality.flac16Bit],
        isrc: null,
      );

      final match = DeduplicationMatcher.findMatch(extendedMix, vaultTracks);
      expect(match, isNull);
      expect(DeduplicationMatcher.isVaulted(extendedMix, vaultTracks), isFalse);
    });

    test('Returns null when no artist or title match exists', () {
      final unfamiliarTrack = ExternalTrackResult(
        id: 'deezer-99',
        title: 'Random Song',
        artists: ['Unknown Artist'],
        album: 'Unknown Album',
        durationSeconds: 180,
        backend: 'deezer',
        availableQualities: [AudioQuality.opus320k],
      );

      final match = DeduplicationMatcher.findMatch(unfamiliarTrack, vaultTracks);
      expect(match, isNull);
      expect(DeduplicationMatcher.isVaulted(unfamiliarTrack, vaultTracks), isFalse);
    });
  });
}
