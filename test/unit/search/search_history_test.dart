import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudbeat/features/ui_shell/search/search_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SearchHistoryService historyService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    historyService = SearchHistoryService();
  });

  group('SearchHistoryService', () {
    test('Starts with empty history', () async {
      final history = await historyService.getHistory();
      expect(history, isEmpty);
    });

    test('Adds query to history', () async {
      await historyService.addQuery('The Weeknd');
      final history = await historyService.getHistory();
      expect(history, equals(['The Weeknd']));
    });

    test('Deduplicates query by moving it to the top', () async {
      await historyService.addQuery('Artist A');
      await historyService.addQuery('Artist B');
      await historyService.addQuery('Artist A');

      final history = await historyService.getHistory();
      expect(history, equals(['Artist A', 'Artist B']));
    });

    test('Enforces 10-item FIFO cap by evicting oldest item', () async {
      for (int i = 1; i <= 12; i++) {
        await historyService.addQuery('Query $i');
      }

      final history = await historyService.getHistory();
      expect(history.length, equals(10));
      // Latest item should be Query 12 at index 0
      expect(history.first, equals('Query 12'));
      // Oldest remaining item should be Query 3 at the end
      expect(history.last, equals('Query 3'));
      // Query 1 and Query 2 should have been evicted
      expect(history.contains('Query 1'), isFalse);
      expect(history.contains('Query 2'), isFalse);
    });

    test('Removes specific query from history', () async {
      await historyService.addQuery('Song 1');
      await historyService.addQuery('Song 2');
      await historyService.removeQuery('Song 1');

      final history = await historyService.getHistory();
      expect(history, equals(['Song 2']));
    });

    test('Clears all history', () async {
      await historyService.addQuery('Song 1');
      await historyService.addQuery('Song 2');
      await historyService.clearHistory();

      final history = await historyService.getHistory();
      expect(history, isEmpty);
    });
  });
}
