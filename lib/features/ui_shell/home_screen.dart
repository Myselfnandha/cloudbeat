import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../discovery/discovery_service.dart';
import '../discovery/home_layout_provider.dart';
import '../discovery/discovery_provider.dart';
import 'home_config_modal.dart';

final selectedHomeProviderTab = StateProvider<String>((ref) => 'All');

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioEngine = ref.watch(audioEngineProvider);
    final layout = ref.watch(homeLayoutProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildHeader(context, ref, audioEngine),
            
            // Dynamically render shelves based on layout order
            for (final shelfId in layout)
              _buildShelf(context, ref, shelfId),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, dynamic audioEngine) {
    final activeTab = ref.watch(selectedHomeProviderTab);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome to',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'CloudBeat Lossless',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.dashboard_customize_rounded, color: AppTheme.textSecondary),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (context) => const HomeConfigModal(),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Provider Filter Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildProviderChip(ref, 'All', activeTab),
                  _buildProviderChip(ref, 'Spotify', activeTab),
                  _buildProviderChip(ref, 'Qobuz', activeTab),
                  _buildProviderChip(ref, 'Tidal', activeTab),
                  _buildProviderChip(ref, 'Deezer', activeTab),
                  _buildProviderChip(ref, 'Apple', activeTab),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Quick Resume Hero Card
            StreamBuilder<Track?>(
              stream: audioEngine.currentTrackStream,
              initialData: audioEngine.currentTrack,
              builder: (context, snapshot) {
                final track = snapshot.data;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.25),
                        AppTheme.accentGradientEnd.withValues(alpha: 0.15),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 64,
                          height: 64,
                          color: AppTheme.card,
                          child: track?.albumArtUrl != null
                              ? Image.network(track!.albumArtUrl!, fit: BoxFit.cover)
                              : const Icon(Icons.graphic_eq_rounded, color: AppTheme.primary, size: 32),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track != null ? 'NOW STREAMING' : 'DISCOVER MUSIC',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track?.title ?? 'Browse High-Res Lossless Audio',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              track?.artists.join(', ') ?? 'Explore Spotify, Qobuz, Deezer, Tidal',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (track != null)
                        IconButton(
                          icon: const Icon(
                            Icons.play_circle_fill_rounded,
                            color: AppTheme.primary,
                            size: 40,
                          ),
                          onPressed: () => audioEngine.resume(),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderChip(WidgetRef ref, String label, String activeTab) {
    final isSelected = activeTab == label;
    return GestureDetector(
      onTap: () => ref.read(selectedHomeProviderTab.notifier).state = label,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.25) : AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildShelf(BuildContext context, WidgetRef ref, String shelfId) {
    if (shelfId == 'recently_played') {
      return _buildRecentLibraryShelf(context, ref);
    } else if (shelfId == 'forgotten_gems' || shelfId == 'daily_mixes') {
      return _buildDailyMixesShelf(context, ref);
    } else {
      return _buildDiscoveryShelf(context, ref, shelfId);
    }
  }

  Widget _buildRecentLibraryShelf(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogContractProvider);
    final audioEngine = ref.watch(audioEngineProvider);

    return SliverToBoxAdapter(
      child: FutureBuilder<List<Track>>(
        future: catalog.getRecentTracks(limit: 10),
        builder: (context, snapshot) {
          final tracks = snapshot.data ?? [];
          if (tracks.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Text(
                  'Recently Added to Library',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => audioEngine.playTrack(track),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 48,
                        height: 48,
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
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${track.artists.join(', ')} • ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.play_circle_outline_rounded,
                        color: AppTheme.primary,
                        size: 28,
                      ),
                      onPressed: () => audioEngine.playTrack(track),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDailyMixesShelf(BuildContext context, WidgetRef ref) {
    final discoveryService = ref.watch(discoveryServiceProvider);
    final audioEngine = ref.watch(audioEngineProvider);

    return SliverToBoxAdapter(
      child: FutureBuilder<List<DailyMix>>(
        future: discoveryService.generateDailyMixes(),
        builder: (context, snapshot) {
          final mixes = snapshot.data ?? [];
          if (mixes.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Text(
                  'Made For You',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: mixes.length,
                  itemBuilder: (context, index) {
                    final mix = mixes[index];
                    return GestureDetector(
                      onTap: () {
                        if (mix.tracks.isNotEmpty) {
                          audioEngine.playTrack(mix.tracks.first);
                        }
                      },
                      child: Container(
                        width: 140,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 80,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [
                                    index == 0 ? Colors.purpleAccent : (index == 1 ? Colors.blueAccent : Colors.tealAccent),
                                    AppTheme.accentGradientEnd,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              mix.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              mix.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDiscoveryShelf(BuildContext context, WidgetRef ref, String shelfId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryProvider.notifier).fetchShelf(shelfId);
    });

    final externalTracks = ref.watch(discoveryProvider)[shelfId] ?? [];
    final audioEngine = ref.watch(audioEngineProvider);

    if (externalTracks.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
        ),
      );
    }

    String title = 'Trending';
    if (shelfId == 'spotify_top') {
      title = 'Spotify Top 50';
    } else if (shelfId == 'qobuz_new') {
      title = 'Qobuz Hi-Res New Releases';
    } else if (shelfId == 'deezer_charts') {
      title = 'Deezer Lossless Charts';
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (externalTracks.isNotEmpty && externalTracks.first.backend == 'offline_seed')
                  GestureDetector(
                    onTap: () => ref.read(discoveryProvider.notifier).fetchShelf(shelfId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 12, color: Colors.orangeAccent),
                          SizedBox(width: 4),
                          Text(
                            'Offline — tap to retry',
                            style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: externalTracks.length,
              itemBuilder: (context, index) {
                final track = externalTracks[index];
                return GestureDetector(
                  onTap: () {
                    final playTrack = Track(
                      id: '${track.backend}:${track.id}',
                      title: track.title,
                      artists: track.artists,
                      album: track.album,
                      albumArtUrl: track.albumArtUrl,
                      durationSeconds: track.durationSeconds,
                      isrc: track.isrc,
                      quality: track.availableQualities.isNotEmpty
                          ? track.availableQualities.first
                          : AudioQuality.flac16Bit,
                      addedAt: DateTime.now(),
                    );
                    audioEngine.playTrack(playTrack);
                  },
                  child: Container(
                    width: 130,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 130,
                            width: 130,
                            color: AppTheme.card,
                            child: track.albumArtUrl != null
                                ? Image.network(track.albumArtUrl!, fit: BoxFit.cover)
                                : const Icon(Icons.music_note, color: AppTheme.primary, size: 40),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track.artists.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
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
