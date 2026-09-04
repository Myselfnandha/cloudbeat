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
  });
}
