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

  final westernTrack = Track(
    id: 'western_track_1',
    title: 'Starboy',
    artists: ['The Weeknd', 'Daft Punk'],
    album: 'Starboy',
    durationSeconds: 230,
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

  group('Tiebreak Rules (LRCLIB > Netease)', () {
    test('prefers LRCLIB SyncedLrc (Score 800) over Netease SyncedLrc (Score 700) to avoid unwanted translations', () async {
      when(() => mockAppleMusic.fetchLyrics(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => null);

      final lrclibResult = LyricsResult(
        trackTitle: 'Starboy',
        artist: 'The Weeknd',
        format: LyricsFormat.syncedLrc,
        source: LyricsSource.lrclib,
        rawLyrics: '[00:10.00]I\'m tryna put you in the worst mood, ah',
        qualityScore: LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.lrclib),
      );

      final neteaseResult = LyricsResult(
        trackTitle: 'Starboy',
        artist: 'The Weeknd',
        format: LyricsFormat.syncedLrc,
        source: LyricsSource.netease,
        rawLyrics: '[00:10.00]I\'m tryna put you in the worst mood, ah (我想让你心情变得糟糕)',
        qualityScore: LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.netease),
      );

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

      final result = await unifiedService.fetchLyrics(westernTrack);

      expect(result, isNotNull);
      expect(result!.source, LyricsSource.lrclib);
      expect(result.qualityScore, 800);
      expect(result.rawLyrics, isNot(contains('我想让你心情变得糟糕')));
    });
  });
}
