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

  final tamilTrack = Track(
    id: 'tamil_track_1',
    title: 'Naan Pizhai',
    artists: ['Anirudh Ravichander', 'Ravi G'],
    album: 'Kaathuvaakula Rendu Kaadhal',
    durationSeconds: 245,
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

  group('Coverage Fallback (Regional Coverage)', () {
    test('falls back to Netease when Apple Music and LRCLIB have no lyrics', () async {
      // Apple Music returns null
      when(() => mockAppleMusic.fetchLyrics(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => null);

      // LRCLIB returns null (miss on regional Tamil song)
      when(() => mockLrclib.fetchLyrics(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => null);

      // Netease returns SyncedLrc (Score 700)
      final neteaseResult = LyricsResult(
        trackTitle: 'Naan Pizhai',
        artist: 'Anirudh Ravichander',
        format: LyricsFormat.syncedLrc,
        source: LyricsSource.netease,
        rawLyrics: '[00:15.00]Naan pizhai nee mazhalai',
        qualityScore: LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.netease),
      );

      when(() => mockNetease.fetchLyrics(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => neteaseResult);

      final result = await unifiedService.fetchLyrics(tamilTrack);

      expect(result, isNotNull);
      expect(result!.source, LyricsSource.netease);
      expect(result.format, LyricsFormat.syncedLrc);
      expect(result.qualityScore, 700);
      expect(result.rawLyrics, contains('Naan pizhai'));
    });
  });
}
