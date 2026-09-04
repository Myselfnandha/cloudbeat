import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'now_playing_screen.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioEngine = ref.watch(audioEngineProvider);

    return StreamBuilder<Track?>(
      stream: audioEngine.currentTrackStream,
      initialData: audioEngine.currentTrack,
      builder: (context, trackSnapshot) {
        final track = trackSnapshot.data;
        if (track == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackStatus>(
          stream: audioEngine.statusStream,
          initialData: audioEngine.currentStatus,
          builder: (context, statusSnapshot) {
            final status = statusSnapshot.data ?? PlaybackStatus.idle;
            final isPlaying = status == PlaybackStatus.playing;

            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const NowPlayingScreen(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                      const begin = Offset(0.0, 1.0);
                      const end = Offset.zero;
                      const curve = Curves.easeOutCubic;
                      final tween = Tween(begin: begin, end: end).chain(
                        CurveTween(curve: curve),
                      );
                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Album Art Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 44,
                        height: 44,
                        color: AppTheme.card,
                        child: track.albumArtUrl != null
                            ? Image.network(
                                track.albumArtUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.music_note,
                                  color: AppTheme.primary,
                                ),
                              )
                            : const Icon(
                                Icons.music_note,
                                color: AppTheme.primary,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Track Title and Artist
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artists.join(', '),
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
                    // Quality Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        track.quality == AudioQuality.flac24Bit ? '24-BIT' : 'FLAC',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Play / Pause Button
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: AppTheme.textPrimary,
                        size: 28,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          audioEngine.pause();
                        } else {
                          audioEngine.resume();
                        }
                      },
                    ),
                    // Skip Next Button
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: AppTheme.textSecondary,
                        size: 24,
                      ),
                      onPressed: () => audioEngine.skipToNext(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
