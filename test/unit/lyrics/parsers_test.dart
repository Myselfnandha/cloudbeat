import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/features/lyrics/parsers/lrc_parser.dart';
import 'package:cloudbeat/features/lyrics/parsers/ttml_parser.dart';

void main() {
  group('LrcParser', () {
    test('parses standard LRC format line timestamps correctly', () {
      const lrc = '''
[00:12.34]First line of lyrics
[00:15.80]Second line of lyrics
[00:20.00]Third line of lyrics
''';
      final lines = LrcParser.parse(lrc);
      expect(lines.length, 3);
      expect(lines[0].text, 'First line of lyrics');
      expect(lines[0].startTime, const Duration(seconds: 12, milliseconds: 340));
      expect(lines[0].endTime, const Duration(seconds: 15, milliseconds: 800));

      expect(lines[1].text, 'Second line of lyrics');
      expect(lines[1].startTime, const Duration(seconds: 15, milliseconds: 800));
      expect(lines[1].endTime, const Duration(seconds: 20));

      expect(lines[2].text, 'Third line of lyrics');
      expect(lines[2].startTime, const Duration(seconds: 20));
    });

    test('parses YRC karaoke word-level format correctly', () {
      const yrc = '[27360,1290](27360,240,0)I\'ve (27600,90,0)been (27690,360,0)tryna (28050,600,0)call';
      final lines = LrcParser.parse(yrc);

      expect(lines.length, 1);
      expect(lines[0].startTime, const Duration(milliseconds: 27360));
      expect(lines[0].endTime, const Duration(milliseconds: 28650));
      expect(lines[0].text, 'I\'ve been tryna call');
      expect(lines[0].hasWordTiming, isTrue);
      expect(lines[0].words?.length, 4);
      expect(lines[0].words?[0].text, 'I\'ve ');
      expect(lines[0].words?[0].startTime, const Duration(milliseconds: 27360));
      expect(lines[0].words?[1].startTime, const Duration(milliseconds: 27600));
    });
  });

  group('TtmlParser', () {
    test('parses TTML XML with span tags into word-level lyrics lines', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:01.500" end="00:04.200">
        <span begin="00:01.500" end="00:02.000">Hello </span>
        <span begin="00:02.100" end="00:04.200">World</span>
      </p>
      <p begin="00:05.000" end="00:08.000">
        <span begin="00:05.000" end="00:06.500">Apple </span>
        <span begin="00:06.500" end="00:08.000">Music</span>
      </p>
    </div>
  </body>
</tt>
''';
      final lines = TtmlParser.parse(ttml);
      expect(lines.length, 2);
      expect(lines[0].startTime, const Duration(milliseconds: 1500));
      expect(lines[0].endTime, const Duration(milliseconds: 4200));
      expect(lines[0].text, 'Hello World');
      expect(lines[0].hasWordTiming, isTrue);
      expect(lines[0].words?.length, 2);
      expect(lines[0].words?[0].text, 'Hello ');
      expect(lines[0].words?[1].text, 'World');

      expect(lines[1].startTime, const Duration(seconds: 5));
      expect(lines[1].text, 'Apple Music');
    });
  });
}
