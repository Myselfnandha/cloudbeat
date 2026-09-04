import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/features/lyrics/lyrics_service.dart';

void main() {
  group('LyricsService & LRC Parser Tests', () {
    late LyricsService lyricsService;

    setUp(() {
      lyricsService = LyricsService();
    });

    test('parseLrc correctly parses timestamps and text', () {
      const sampleLrc = '''
[00:12.50]Is this the real life?
[00:15.30]Is this just fantasy?
[00:19.85]Caught in a landslide
[00:23.10]No escape from reality
''';

      final lines = lyricsService.parseLrc(sampleLrc);

      expect(lines.length, 4);
      expect(lines[0].text, 'Is this the real life?');
      expect(lines[0].timestamp, const Duration(seconds: 12, milliseconds: 500));
      expect(lines[1].text, 'Is this just fantasy?');
      expect(lines[1].timestamp, const Duration(seconds: 15, milliseconds: 300));
    });

    test('getActiveIndex matches current playback position accurately', () {
      const sampleLrc = '''
[00:10.00]First line
[00:20.00]Second line
[00:30.00]Third line
''';
      final lines = lyricsService.parseLrc(sampleLrc);
      final synced = SyncedLyrics(lines: lines, isSynced: true);

      // Before first line -> 0
      expect(synced.getActiveIndex(const Duration(seconds: 5)), 0);
      // Exactly at first line -> 0
      expect(synced.getActiveIndex(const Duration(seconds: 10)), 0);
      // Between first and second line -> 0
      expect(synced.getActiveIndex(const Duration(seconds: 15)), 0);
      // Exactly at second line -> 1
      expect(synced.getActiveIndex(const Duration(seconds: 20)), 1);
      // Past third line -> 2
      expect(synced.getActiveIndex(const Duration(seconds: 45)), 2);
    });

    test('transliterateIndic accurately converts Devanagari and Tamil scripts', () {
      // Devanagari
      final hindi = lyricsService.transliterateIndic('नमस्ते दुनिया');
      expect(hindi.toLowerCase(), contains('namaste'));

      // Tamil
      final tamil = lyricsService.transliterateIndic('வணக்கம் உலகம்');
      expect(tamil.toLowerCase(), contains('vanakkam'));
    });

    test('parseLrc generates phonetic transliterations and toggles display text', () {
      const sampleIndicLrc = '''
[00:05.00]नमस्ते
[00:10.00]வணக்கம்
''';
      final lines = lyricsService.parseLrc(sampleIndicLrc, autoTransliterate: true);
      expect(lines.length, 2);

      // Original text
      expect(lines[0].getDisplayText(transliterate: false), 'नमस्ते');
      expect(lines[1].getDisplayText(transliterate: false), 'வணக்கம்');

      // Transliterated text
      expect(lines[0].getDisplayText(transliterate: true).toLowerCase(), contains('namaste'));
      expect(lines[1].getDisplayText(transliterate: true).toLowerCase(), contains('vanakkam'));
    });

    test('withTransliteration updates plainLyrics and lines', () {
      const synced = SyncedLyrics(
        plainLyrics: 'नमस्ते',
        lines: [
          LyricLine(
            timestamp: Duration(seconds: 1),
            text: 'வணக்கம்',
          ),
        ],
        isSynced: true,
      );

      final transliterated = synced.withTransliteration();
      expect(transliterated.transliteratedPlainLyrics?.toLowerCase(), contains('namaste'));
      expect(transliterated.lines.first.transliteratedText?.toLowerCase(), contains('vanakkam'));
    });
  });
}
