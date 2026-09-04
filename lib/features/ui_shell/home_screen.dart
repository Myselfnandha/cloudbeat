import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../discovery/discovery_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioEngine = ref.watch(audioEngineProvider);
    final discoveryService = ref.watch(discoveryServiceProvider);
    final catalog = ref.watch(catalogContractProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Sliver Header
            SliverToBoxAdapter(
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
                              'Good Evening 🌙',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'CloudBeat Vault',
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
                          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textSecondary),
                          onPressed: () {},
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

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
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  color: AppTheme.card,
                                  child: track?.albumArtUrl != null
                                      ? Image.network(track!.albumArtUrl!, fit: BoxFit.cover)
                                      : const Icon(Icons.music_note, color: AppTheme.primary),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'RESUME SESSION',
                                      style: TextStyle(
                                        color: AppTheme.primary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      track?.title ?? 'Ready to stream lossless audio',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      track?.artists.join(', ') ?? 'Select a track from your vault',
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
                                Container(
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                                    onPressed: () => audioEngine.play(track),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Contextual Mood Pills
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildMoodChip('⚡ Workout', isSelected: true),
                          _buildMoodChip('🌙 Night Drive'),
                          _buildMoodChip('☕ Chill'),
                          _buildMoodChip('🎯 Focus'),
                          _buildMoodChip('🎉 Party'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Daily Mixes Section
            SliverToBoxAdapter(
              child: FutureBuilder<List<DailyMix>>(
                future: discoveryService.generateDailyMixes(),
                builder: (context, snapshot) {
                  final mixes = snapshot.data ?? [];
                  if (mixes.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Text(
                          'Your Daily Mixes (On-Device ML)',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 190,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: mixes.length,
                          itemBuilder: (context, index) {
                            final mix = mixes[index];
                            return Container(
                              width: 150,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 100,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.primaries[index % Colors.primaries.length].shade700,
                                          Colors.primaries[(index + 3) % Colors.primaries.length].shade900,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.graphic_eq_rounded, size: 40, color: Colors.white),
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
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${mix.tracks.length} tracks',
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Recently Added to Vault Section
            SliverToBoxAdapter(
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
                          'Recently Added to Telegram Vault',
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
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 48,
                                height: 48,
                                color: AppTheme.card,
                                child: const Icon(Icons.music_note, color: AppTheme.primary),
                              ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              track.artists.join(', '),
                              maxLines: 1,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.primary, size: 32),
                              onPressed: () => audioEngine.play(track),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodChip(String label, {bool isSelected = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}
