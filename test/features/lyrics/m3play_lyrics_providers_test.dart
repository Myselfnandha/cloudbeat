import 'package:cloudbeat/core/contracts/lyrics_contract.dart';
import 'package:cloudbeat/features/discovery/innertube_service.dart';
import 'package:cloudbeat/features/lyrics/parsers/lrc_parser.dart';
import 'package:cloudbeat/features/lyrics/parsers/ttml_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M3-Play Enhanced Lyric Parsers', () {
    test('LrcParser parses vocal separation agents and background vocals', () {
      const lrcContent = '''
[00:10.50]{agent:v1} Lead vocalist singing here
[00:14.20](v2): Second singer responds
[00:18.00]{bg} Soft background harmonies
[00:22.00][bg: Standalone background vocal line]
''';

      final lines = LrcParser.parse(lrcContent);
      expect(lines.length, 4);

      expect(lines[0].singerAgent, 'v1');
      expect(lines[0].isBackground, false);
      expect(lines[0].text, 'Lead vocalist singing here');

      expect(lines[1].singerAgent, 'v2');
      expect(lines[1].isBackground, false);
      expect(lines[1].text, 'Second singer responds');

      expect(lines[2].isBackground, true);
      expect(lines[2].text, 'Soft background harmonies');

      expect(lines[3].isBackground, true);
      expect(lines[3].text, 'Standalone background vocal line');
    });

    test('LrcParser parses inline syllable timestamps', () {
      const elrcContent = '''
[00:05.00]<00:05.00>Hello <00:05.50>world <00:06.20>again
''';

      final lines = LrcParser.parse(elrcContent);
      expect(lines.isNotEmpty, true);
      final line = lines.first;
      expect(line.hasWordTiming, true);
      expect(line.words?.length, 3);
      expect(line.words?[0].text, 'Hello');
      expect(line.words?[1].text, 'world');
    });

    test('LrcParser parses multiline word tags (<word:s:e|...>)', () {
      const multilineLrc = '''
[00:08.00]Never gonna give you up
<Never:8.0:8.4|gonna:8.4:8.7|give:8.7:9.0|you:9.0:9.2|up:9.2:9.6>
''';

      final lines = LrcParser.parse(multilineLrc);
      expect(lines.length, 1);
      final line = lines.first;
      expect(line.hasWordTiming, true);
      expect(line.words?.length, 5);
      expect(line.words?[0].text, 'Never');
      expect(line.words?[4].text, 'up');
    });

    test('TtmlParser parses TTML spans and agent roles', () {
      const ttmlSample = '''
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
  <body>
    <div>
      <p begin="00:00:10.000" end="00:00:14.000" ttm:agent="v1">
        <span begin="00:00:10.000" end="00:00:11.500">First</span>
        <span begin="00:00:11.500" end="00:00:14.000">phrase</span>
      </p>
      <p begin="00:00:15.000" end="00:00:18.000" role="background">
        <span>Backing harmony</span>
      </p>
    </div>
  </body>
</tt>
''';

      final lines = TtmlParser.parse(ttmlSample);
      expect(lines.length, 2);

      expect(lines[0].singerAgent, 'v1');
      expect(lines[0].isBackground, false);
      expect(lines[0].hasWordTiming, true);
      expect(lines[0].words?.length, 2);
      expect(lines[0].words?[0].text, 'First');

      expect(lines[1].isBackground, true);
      expect(lines[1].text, 'Backing harmony');
    });
  });

  group('InnerTube Discovery Service', () {
    test('Provides curated seed charts on network failure', () async {
      final service = InnerTubeService();
      final charts = await service.getCharts();
      expect(charts.isNotEmpty, true);
      expect(charts.first.title.isNotEmpty, true);
    });

    test('Provides curated mood tracks', () async {
      final service = InnerTubeService();
      final moodTracks = await service.getMoodTracks('Chill');
      expect(moodTracks.isNotEmpty, true);
      expect(moodTracks.first.title.contains('Chill'), true);
    });
  });

  group('Lyrics Contract & Ranking', () {
    test('TTML has higher priority ranking score than SyncedLrc', () {
      final ttmlScore = LyricsResult.calculateScore(LyricsFormat.ttml, LyricsSource.paxsenix);
      final lrclibScore = LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.lrclib);
      final neteaseScore = LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.netease);

      expect(ttmlScore, 1000);
      expect(lrclibScore, 800);
      expect(neteaseScore, 700);
      expect(ttmlScore > lrclibScore, true);
      expect(lrclibScore > neteaseScore, true);
    });
  });
}
