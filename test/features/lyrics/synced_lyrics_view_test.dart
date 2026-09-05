import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/lyrics_contract.dart';
import 'package:cloudbeat/features/lyrics/ui/synced_lyrics_view.dart';

void main() {
  group('Module 7: SyncedLyricsView UI Component Tests', () {
    late StreamController<Duration> positionController;

    setUp(() {
      positionController = StreamController<Duration>.broadcast();
    });

    tearDown(() {
      positionController.close();
    });

    testWidgets('renders TTML word-by-word karaoke spans and updates on position change', (tester) async {
      final ttmlLyrics = LyricsResult(
        trackTitle: 'Song A',
        artist: 'Artist A',
        format: LyricsFormat.ttml,
        source: LyricsSource.appleMusic,
        qualityScore: 1000,
        rawLyrics: 'Hello world of music',
        lines: [
          LyricsLine(
            text: 'Hello world of music',
            startTime: const Duration(seconds: 0),
            endTime: const Duration(seconds: 4),
            words: [
              LyricsWord(text: 'Hello', startTime: const Duration(seconds: 0), endTime: const Duration(seconds: 1)),
              LyricsWord(text: 'world', startTime: const Duration(seconds: 1), endTime: const Duration(seconds: 2)),
              LyricsWord(text: 'of', startTime: const Duration(seconds: 2), endTime: const Duration(seconds: 3)),
              LyricsWord(text: 'music', startTime: const Duration(seconds: 3), endTime: const Duration(seconds: 4)),
            ],
          ),
          LyricsLine(
            text: 'Second line here',
            startTime: const Duration(seconds: 4),
            endTime: const Duration(seconds: 8),
            words: [
              LyricsWord(text: 'Second', startTime: const Duration(seconds: 4), endTime: const Duration(seconds: 6)),
              LyricsWord(text: 'line', startTime: const Duration(seconds: 6), endTime: const Duration(seconds: 7)),
              LyricsWord(text: 'here', startTime: const Duration(seconds: 7), endTime: const Duration(seconds: 8)),
            ],
          ),
        ],
      );

      Duration? seekTarget;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncedLyricsView(
              lyrics: ttmlLyrics,
              positionStream: positionController.stream,
              initialPosition: Duration.zero,
              onSeek: (pos) => seekTarget = pos,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Words rendered
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('world'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);

      // Verify tap on second line triggers seek to second line's startTime (4 seconds)
      await tester.tap(find.text('Second'));
      expect(seekTarget, const Duration(seconds: 4));

      // Advance position to 1.5 seconds (word 'world' is active)
      positionController.add(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 50));

      // Verify widget rebuilt with new position without crashing
      expect(find.text('world'), findsOneWidget);
    });

    testWidgets('renders standard LRC lines with uniform line highlighting and tap-to-seek', (tester) async {
      final lrcLyrics = LyricsResult(
        trackTitle: 'Song B',
        artist: 'Artist B',
        format: LyricsFormat.syncedLrc,
        source: LyricsSource.lrclib,
        qualityScore: 800,
        rawLyrics: 'First line text\nSecond line text\nThird line text',
        lines: [
          LyricsLine(
            text: 'First line text',
            startTime: const Duration(seconds: 2),
            endTime: const Duration(seconds: 5),
          ),
          LyricsLine(
            text: 'Second line text',
            startTime: const Duration(seconds: 5),
            endTime: const Duration(seconds: 10),
          ),
          LyricsLine(
            text: 'Third line text',
            startTime: const Duration(seconds: 10),
            endTime: const Duration(seconds: 15),
          ),
        ],
      );

      Duration? tappedPos;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncedLyricsView(
              lyrics: lrcLyrics,
              positionStream: positionController.stream,
              initialPosition: const Duration(seconds: 6),
              onSeek: (pos) => tappedPos = pos,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('First line text'), findsOneWidget);
      expect(find.text('Second line text'), findsOneWidget);
      expect(find.text('Third line text'), findsOneWidget);

      // Tap on third line
      await tester.tap(find.text('Third line text'));
      expect(tappedPos, const Duration(seconds: 10));
    });

    testWidgets('renders empty and instrumental states correctly and triggers retry callback', (tester) async {
      bool retryTriggered = false;

      // Case A: Instrumental track
      final instrumentalLyrics = LyricsResult(
        trackTitle: 'Instrumental Track',
        artist: 'Composer',
        format: LyricsFormat.plainText,
        source: LyricsSource.lrclib,
        qualityScore: 100,
        isInstrumental: true,
        rawLyrics: '',
        lines: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncedLyricsView(
              lyrics: instrumentalLyrics,
              positionStream: positionController.stream,
              onSeek: (_) {},
              onRetry: () => retryTriggered = true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Instrumental'), findsOneWidget);
      expect(find.text('This track contains no spoken lyrics'), findsOneWidget);
      expect(find.text('Retry Lyrics'), findsOneWidget);

      await tester.tap(find.text('Retry Lyrics'));
      expect(retryTriggered, isTrue);

      // Case B: Null lyrics (lyrics unavailable)
      retryTriggered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncedLyricsView(
              lyrics: null,
              positionStream: positionController.stream,
              onSeek: (_) {},
              onRetry: () => retryTriggered = true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No Lyrics Available'), findsOneWidget);
      expect(find.text('Could not synchronize lyrics for this track'), findsOneWidget);
      expect(find.text('Retry Lyrics'), findsOneWidget);

      await tester.tap(find.text('Retry Lyrics'));
      expect(retryTriggered, isTrue);
    });
  });
}
