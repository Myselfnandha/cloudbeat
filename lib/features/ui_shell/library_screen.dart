import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final Set<String> _downloadingIds = {};
  String _selectedSection = 'All';

  @override
  void initState() {
    super.initState();
    AppLogger.trace('[LibraryScreen.initState]');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(downloadManagerProvider).reconcile();
    });
  }

  Future<void> _startDownload(Track track, dynamic downloadManager) async {
    AppLogger.trace('[LibraryScreen._startDownload]', 'track: ${track.title}');
    setState(() => _downloadingIds.add(track.id));
    try {
      await downloadManager.downloadTrack(track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded "${track.title}" for offline playback!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, st) {
      AppLogger.e('LibraryScreen', 'download failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingIds.remove(track.id));
      }
    }
  }

  Future<void> _confirmDeleteDownload(Track track, dynamic downloadManager) async {
    AppLogger.trace('[LibraryScreen._confirmDeleteDownload]', 'track: ${track.title}');
    final colorScheme = Theme.of(context).colorScheme;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: Text('Delete Download?', style: TextStyle(color: colorScheme.onSurface)),
        content: Text(
          'Remove "${track.title}" from offline downloads?',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      AppLogger.trace('[LibraryScreen.deleteDownload.confirmed]', 'track: ${track.title}');
      await downloadManager.deleteDownload(track.id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final catalog = ref.watch(catalogContractProvider);
    final audioEngine = ref.watch(audioEngineProvider);

    // 3 Categorized Library Sections with 2-column cards
    final categorizedItems = [
      {
        'category': 'Personal Library',
        'items': [
          {
            'title': 'Favorite Tracks',
            'subtitle': 'Starred lossless',
            'icon': Icons.favorite_rounded,
            'color': Colors.pinkAccent,
            'type': 'favorites',
          },
          {
            'title': 'Playlists',
            'subtitle': 'Mixes & collections',
            'icon': Icons.queue_music_rounded,
            'color': Colors.lightBlueAccent,
            'type': 'playlists',
          },
          {
            'title': 'Artists',
            'subtitle': 'Composers & singers',
            'icon': Icons.people_rounded,
            'color': Colors.purpleAccent,
            'type': 'artists',
          },
          {
            'title': 'Recently Played',
            'subtitle': 'Session history',
            'icon': Icons.history_rounded,
            'color': Colors.tealAccent,
            'type': 'recent',
          },
        ],
      },
      {
        'category': 'Lossless & Vault',
        'items': [
          {
            'title': 'Hi-Res Studio Vault',
            'subtitle': '192kHz master files',
            'icon': Icons.album_rounded,
            'color': Colors.amberAccent,
            'type': 'hires',
          },
          {
            'title': 'Downloaded Offline',
            'subtitle': 'FLAC stored on disk',
            'icon': Icons.download_done_rounded,
            'color': Colors.greenAccent,
            'type': 'downloads',
          },
        ],
      },
      {
        'category': 'Device & Cache',
        'items': [
          {
            'title': 'Lossless Cache',
            'subtitle': 'Temp audio chunks',
            'icon': Icons.storage_rounded,
            'color': Colors.orangeAccent,
            'type': 'cache',
          },
          {
            'title': 'Device Storage',
            'subtitle': 'Internal & SD files',
            'icon': Icons.folder_rounded,
            'color': Colors.indigoAccent,
            'type': 'device',
          },
        ],
      },
    ];

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top-Left aligned "Library" heading (M3 Large Title)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 12),
                child: Text(
                  'Library',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ),

              // 2. Categorized 2-Column Icon Grids
              ...categorizedItems.map((cat) {
                final catName = cat['category'] as String;
                final items = cat['items'] as List<Map<String, dynamic>>;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          catName,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 2.2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, idx) {
                          final item = items[idx];
                          final isSelected = _selectedSection == item['type'];

                          return Material(
                            color: isSelected
                                ? colorScheme.secondaryContainer.withValues(alpha: 0.8)
                                : colorScheme.surfaceContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.outline.withValues(alpha: 0.08),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                AppLogger.trace('[LibraryScreen.selectSection]', 'type: ${item['type']}');
                                setState(() {
                                  _selectedSection = _selectedSection == item['type'] ? 'All' : item['type'] as String;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: (item['color'] as Color).withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        item['icon'] as IconData,
                                        color: item['color'] as Color,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            item['title'] as String,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: colorScheme.onSurface,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            item['subtitle'] as String,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: colorScheme.onSurfaceVariant,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 24),

              // Active Section Tracks View (Favorites, Downloads, Recent, etc.)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _selectedSection == 'downloads'
                      ? 'Downloaded Tracks'
                      : _selectedSection == 'recent'
                          ? 'Recently Played'
                          : 'Saved & Starred Songs',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              FutureBuilder<List<Track>>(
                future: _selectedSection == 'downloads'
                    ? catalog.getDownloadedTracks()
                    : _selectedSection == 'recent'
                        ? catalog.getRecentTracks(limit: 20)
                        : catalog.getFavorites(),
                builder: (context, snapshot) {
                  final tracks = snapshot.data ?? [];
                  if (tracks.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          _selectedSection == 'downloads'
                              ? 'No tracks downloaded yet. Tap download on any song to listen offline!'
                              : 'No tracks saved here yet. Star songs to view them in your library.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tracks.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final isDownloading = _downloadingIds.contains(track.id);

                      return Material(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            AppLogger.trace('[LibraryScreen.playTrack]', 'title: ${track.title}');
                            audioEngine.playTrack(track);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    color: colorScheme.surfaceContainerHighest,
                                    child: track.albumArtUrl != null
                                        ? Image.network(track.albumArtUrl!, fit: BoxFit.cover)
                                        : Icon(Icons.music_note, color: colorScheme.primary),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colorScheme.onSurface,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${track.artists.join(', ')} • ${track.album}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    color: track.isFavorite ? Colors.pinkAccent : colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    AppLogger.trace('[LibraryScreen.toggleFavorite]', 'track: ${track.title}');
                                    await catalog.toggleFavorite(track.id, !track.isFavorite);
                                    setState(() {});
                                  },
                                ),
                                if (isDownloading)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                                  )
                                else if (track.isDownloaded)
                                  IconButton(
                                    icon: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                                    onPressed: () => _confirmDeleteDownload(track, ref.read(downloadManagerProvider)),
                                  )
                                else
                                  IconButton(
                                    icon: Icon(Icons.download_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                                    onPressed: () => _startDownload(track, ref.read(downloadManagerProvider)),
                                  ),
                                IconButton(
                                  icon: Icon(Icons.play_circle_fill_rounded, color: colorScheme.primary, size: 28),
                                  onPressed: () {
                                    audioEngine.playTrack(track);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              // Bottom padding for 60dp MiniPlayer
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
