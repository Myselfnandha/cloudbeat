import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloudbeat/core/contracts/lyrics_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/lyrics/unified_lyrics_service.dart';

class MockLyricsProvider extends Mock implements LyricsProviderContract {}

void main() {
  late MockLyricsProvider mockAppleMusic;
  late MockLyricsProvider mockLrclib;
  late MockLyricsProvider mockNetease;
  late UnifiedLyricsService unifiedService;

  final testTrack = Track(
    id: 'test_1',
    title: 'Blinding Lights',
    artists: ['The Weeknd'],
    album: 'After Hours',
    durationSeconds: 200,
    quality: AudioQuality.flac16Bit,
    isOfflinePinned: false,
    addedAt: DateTime.now(),
  );

  setUp(() {
    mockAppleMusic = MockLyricsProvider();
    mockLrclib = MockLyricsProvider();
    mockNetease = MockLyricsProvider();

    when(() => mockAppleMusic.source).thenReturn(LyricsSource.appleMusic);
    when(() => mockLrclib.source).thenReturn(LyricsSource.lrclib);
    when(() => mockNetease.source).thenReturn(LyricsSource.netease);

    unifiedService = UnifiedLyricsService(
      providers: [mockAppleMusic, mockLrclib, mockNetease],
    );
  });

  group('Lyrics Quality-First Scoring Hierarchy', () {
    test('picks Apple Music TTML (Score 1000) when all providers return valid lyrics', () async {
      final appleResult = LyricsResult(
        trackTitle: 'Blinding Lights',
        artist: 'The Weeknd',
        format: LyricsFormat.ttml,
        source: LyricsSource.appleMusic,
        rawLyrics: '<tt>...</tt>',
        qualityScore: LyricsResult.calculateScore(LyricsFormat.ttml, LyricsSource.appleMusic),
      );

      final lrclibResult = LyricsResult(
        trackTitle: 'Blinding Lights',
        artist: 'The Weeknd',
        format: LyricsFormat.syncedLrc,
        source: LyricsSource.lrclib,
        rawLyrics: '[00:10.00]Yeah',
        qualityScore: LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.lrclib),
      );

      final neteaseResult = LyricsResult(
        trackTitle: 'Blinding Lights',
        artist: 'The Weeknd',
        format: LyricsFormat.syncedLrc,
        source: LyricsSource.netease,
        rawLyrics: '[00:10.00]Yeah',
        qualityScore: LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.netease),
      );

      when(() => mockAppleMusic.fetchLyrics(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => appleResult);

      when(() => mockLrclib.fetchLyrics(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => lrclibResult);

      when(() => mockNetease.fetchLyrics(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => neteaseResult);

      final result = await unifiedService.fetchLyrics(testTrack);

      expect(result, isNotNull);
      expect(result!.source, LyricsSource.appleMusic);
      expect(result.format, LyricsFormat.ttml);
      expect(result.qualityScore, 1000);
    });
  });
}
