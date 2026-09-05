import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryService {
  static const String _key = 'recent_search_queries';
  static const int maxHistory = 10;

  final SharedPreferences? _prefs;

  SearchHistoryService({SharedPreferences? prefs}) : _prefs = prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  Future<List<String>> getRecentQueries() async {
    final prefs = await _getPrefs();
    return prefs.getStringList(_key) ?? [];
  }

  Future<List<String>> getHistory() => getRecentQueries();

  Future<void> addQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    final prefs = await _getPrefs();
    final current = prefs.getStringList(_key) ?? [];

    // Remove duplicates (case-insensitive)
    current.removeWhere((q) => q.toLowerCase() == clean.toLowerCase());

    // Insert at front (most recent first)
    current.insert(0, clean);

    // Enforce max 10 entries
    if (current.length > maxHistory) {
      current.removeRange(maxHistory, current.length);
    }

    await prefs.setStringList(_key, current);
  }

  Future<void> removeQuery(String query) async {
    final prefs = await _getPrefs();
    final current = prefs.getStringList(_key) ?? [];
    current.removeWhere((q) => q.toLowerCase() == query.trim().toLowerCase());
    await prefs.setStringList(_key, current);
  }

  Future<void> clearHistory() async {
    final prefs = await _getPrefs();
    await prefs.remove(_key);
  }
}
