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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title: const Text('Your Library'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          tabs: const [
            Tab(text: 'All Songs'),
            Tab(text: 'Pinned Offline'),
            Tab(text: 'Albums'),
          ],
        ),
      ),
      body: FutureBuilder<List<Track>>(
        future: catalog.getRecentTracks(limit: 100),
        builder: (context, snapshot) {
          final allTracks = snapshot.data ?? [];

          return TabBarView(
            controller: _tabController,
            children: [
              // All Songs Tab
              _buildTrackList(allTracks, audioEngine, catalog),

              // Pinned Offline Tab
              _buildTrackList(
                allTracks.where((t) => t.isOfflinePinned).toList(),
                audioEngine,
                catalog,
                emptyMessage: 'No pinned tracks for offline listening yet',
              ),

              // Albums Tab
              _buildAlbumsGrid(allTracks, audioEngine),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTrackList(
    List<Track> tracks,
    dynamic audioEngine,
    dynamic catalog, {
    String emptyMessage = 'No tracks in library yet',
  }) {
    if (tracks.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: const TextStyle(color: AppTheme.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              color: AppTheme.card,
              child: const Icon(Icons.music_note, color: AppTheme.primary),
            ),
          ),
          title: Text(track.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${track.artists.join(', ')} • ${track.album}',
            maxLines: 1,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  track.isOfflinePinned ? Icons.download_done_rounded : Icons.download_rounded,
                  color: track.isOfflinePinned ? AppTheme.secondary : AppTheme.textMuted,
                  size: 20,
                ),
                onPressed: () async {
                  await catalog.markTrackOfflinePinned(track.id, !track.isOfflinePinned);
                  setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.primary, size: 30),
                onPressed: () => audioEngine.play(track),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumsGrid(List<Track> tracks, dynamic audioEngine) {
    final Map<String, List<Track>> albums = {};
    for (final track in tracks) {
      albums.putIfAbsent(track.album, () => []).add(track);
    }

    if (albums.isEmpty) {
      return const Center(child: Text('No albums found', style: TextStyle(color: AppTheme.textMuted)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final albumName = albums.keys.elementAt(index);
        final albumTracks = albums[albumName]!;

        return GestureDetector(
          onTap: () {
            if (albumTracks.isNotEmpty) {
              audioEngine.setQueue(albumTracks);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(Icons.album_rounded, size: 48, color: AppTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  albumName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  '${albumTracks.length} tracks',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
