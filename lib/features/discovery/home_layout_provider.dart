import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final homeLayoutProvider = StateNotifierProvider<HomeLayoutNotifier, List<String>>((ref) {
  return HomeLayoutNotifier();
});

class HomeLayoutNotifier extends StateNotifier<List<String>> {
  static const _prefsKey = 'home_modular_layout';
  
  // Default shelves if user hasn't configured them
  static const _defaultLayout = [
    'recently_played',
    'spotify_top',
    'qobuz_new',
    'deezer_charts',
    'forgotten_gems'
  ];

  HomeLayoutNotifier() : super(_defaultLayout) {
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLayout = prefs.getStringList(_prefsKey);
    if (savedLayout != null && savedLayout.isNotEmpty) {
      state = savedLayout;
    }
  }

  Future<void> updateLayout(List<String> newLayout) async {
    state = newLayout;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, newLayout);
  }
}
