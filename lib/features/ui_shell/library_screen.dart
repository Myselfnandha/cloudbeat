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

    // 8 persistent library items as specified
    final libraryItems = [
      {
        'title': 'Favorite Tracks',
        'subtitle': 'Starred lossless songs',
        'icon': Icons.favorite_rounded,
        'color': Colors.pinkAccent,
        'type': 'favorites',
      },
      {
        'title': 'Downloaded Offline',
        'subtitle': 'FLAC files stored on device',
        'icon': Icons.download_done_rounded,
        'color': Colors.greenAccent,
        'type': 'downloads',
      },
      {
        'title': 'Curated Playlists',
        'subtitle': 'Mixes and user collections',
        'icon': Icons.queue_music_rounded,
        'color': Colors.lightBlueAccent,
        'type': 'playlists',
      },
      {
        'title': 'Hi-Res 24-Bit Studio Vault',
        'subtitle': '192kHz master recordings',
        'icon': Icons.album_rounded,
        'color': Colors.amberAccent,
        'type': 'hires',
      },
      {
        'title': 'Artists & Performers',
        'subtitle': 'Followed musicians & composers',
        'icon': Icons.people_rounded,
        'color': Colors.purpleAccent,
        'type': 'artists',
      },
      {
        'title': 'Recently Played',
        'subtitle': 'Listening session history',
        'icon': Icons.history_rounded,
        'color': Colors.tealAccent,
        'type': 'recent',
      },
      {
        'title': 'Lossless Cache Manager',
        'subtitle': 'Temporary audio chunks',
        'icon': Icons.storage_rounded,
        'color': Colors.orangeAccent,
        'type': 'cache',
      },
      {
        'title': 'Device Local Storage',
        'subtitle': 'Scanned audio files on SD / Internal',
        'icon': Icons.folder_rounded,
        'color': Colors.indigoAccent,
        'type': 'device',
      },
    ];

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Centered "Library" (28sp bold)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
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
              ),

              const SizedBox(height: 16),

              // 2. 8 persistent list items
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: libraryItems.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = libraryItems[index];
                  final isSelected = _selectedSection == item['type'];

                  return Material(
                    color: isSelected
                        ? colorScheme.secondaryContainer.withValues(alpha: 0.6)
                        : colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        AppLogger.trace('[LibraryScreen.selectSection]', 'type: ${item['type']}');
                        setState(() {
                          _selectedSection = _selectedSection == item['type'] ? 'All' : item['type'] as String;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            // Icon in 40dp container
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                item['icon'] as IconData,
                                color: colorScheme.onPrimaryContainer,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Title and Subtitle
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title'] as String,
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item['subtitle'] as String,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isSelected ? Icons.expand_less_rounded : Icons.chevron_right_rounded,
                              color: colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

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
