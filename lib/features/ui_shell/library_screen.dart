import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _downloadingIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(downloadManagerProvider).reconcile();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogContractProvider);
    final audioEngine = ref.watch(audioEngineProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Your Library',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          tabs: const [
            Tab(text: 'Favorites'),
            Tab(text: 'Downloaded Offline'),
            Tab(text: 'Recently Played'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Favorites
          FutureBuilder<List<Track>>(
            future: catalog.getFavorites(),
            builder: (context, snapshot) {
              return _buildTrackList(
                snapshot.data ?? [],
                audioEngine,
                emptyMessage: 'No favorite tracks saved yet. Tap the heart icon to save songs!',
              );
            },
          ),

          // Tab 2: Downloaded Offline
          FutureBuilder<List<Track>>(
            future: catalog.getDownloadedTracks(),
            builder: (context, snapshot) {
              return _buildTrackList(
                snapshot.data ?? [],
                audioEngine,
                emptyMessage: 'No tracks downloaded for offline listening yet.',
              );
            },
          ),

          // Tab 3: Recently Played
          FutureBuilder<List<Track>>(
            future: catalog.getRecentTracks(limit: 50),
            builder: (context, snapshot) {
              return _buildTrackList(
                snapshot.data ?? [],
                audioEngine,
                emptyMessage: 'No recently played tracks found.',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList(
    List<Track> tracks,
    dynamic audioEngine, {
    required String emptyMessage,
  }) {
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    final catalog = ref.read(catalogContractProvider);
    final downloadManager = ref.read(downloadManagerProvider);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isDownloading = _downloadingIds.contains(track.id);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 50,
              height: 50,
              color: AppTheme.card,
              child: track.albumArtUrl != null
                  ? Image.network(track.albumArtUrl!, fit: BoxFit.cover)
                  : const Icon(Icons.music_note, color: AppTheme.primary),
            ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${track.artists.join(', ')} • ${track.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Favorite Toggle
              IconButton(
                icon: Icon(
                  track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: track.isFavorite ? Colors.pinkAccent : AppTheme.textMuted,
                  size: 22,
                ),
                onPressed: () async {
                  await catalog.toggleFavorite(track.id, !track.isFavorite);
                  setState(() {});
                },
              ),

              // Download Button
              if (isDownloading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                )
              else if (track.isDownloaded)
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
                  tooltip: 'Downloaded Offline (Tap to remove)',
                  onPressed: () => _confirmDeleteDownload(track, downloadManager),
                )
              else
                IconButton(
                  icon: const Icon(Icons.download_rounded, color: AppTheme.textMuted, size: 22),
                  tooltip: 'Download Offline',
                  onPressed: () => _startDownload(track, downloadManager),
                ),

              // Play Button
              IconButton(
                icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.primary, size: 34),
                onPressed: () => audioEngine.playTrack(track),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startDownload(Track track, dynamic downloadManager) async {
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
    } catch (e) {
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
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Delete Download?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Remove "${track.title}" from offline downloads?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await downloadManager.deleteDownload(track.id);
      setState(() {});
    }
  }
}
