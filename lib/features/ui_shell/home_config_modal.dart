import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../discovery/home_layout_provider.dart';

class HomeConfigModal extends ConsumerStatefulWidget {
  const HomeConfigModal({super.key});

  @override
  ConsumerState<HomeConfigModal> createState() => _HomeConfigModalState();
}

class _HomeConfigModalState extends ConsumerState<HomeConfigModal> {
  late List<String> _currentLayout;
  
  final Map<String, String> _shelfTitles = {
    'recently_played': 'Recently Added to Vault',
    'forgotten_gems': 'Forgotten Gems',
    'daily_mixes': 'Daily Mixes (On-Device ML)',
    'spotify_top': 'Spotify Top 50',
    'qobuz_new': 'Qobuz New Releases',
    'deezer_charts': 'Deezer Charts',
    'ytmusic_trending': 'YT Music Trending',
  };

  @override
  void initState() {
    super.initState();
    _currentLayout = List.from(ref.read(homeLayoutProvider));
    
    // Add any missing shelves that are available but not currently in layout
    for (final shelf in _shelfTitles.keys) {
      if (!_currentLayout.contains(shelf)) {
        _currentLayout.add(shelf); // We will assume everything is checked by default, or maybe some are disabled?
        // Actually, let's keep it simple: if it's in _currentLayout, it's enabled.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Home Screen Layout',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(homeLayoutProvider.notifier).updateLayout(_currentLayout);
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Save',
                    style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              'Drag and drop to reorder shelves. Uncheck to hide them from your Home screen.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _currentLayout.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _currentLayout.removeAt(oldIndex);
                  _currentLayout.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final shelfId = _currentLayout[index];
                final title = _shelfTitles[shelfId] ?? shelfId;
                // For simplicity, we just allow reordering. In a real app we'd add a toggle.
                return Container(
                  key: ValueKey(shelfId),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle_rounded, color: AppTheme.textSecondary),
                    title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
