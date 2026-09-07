import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';
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
                AppLogger.trace('[MiniPlayer.openNowPlaying]', 'track: ${track.title}');
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
              child: Center(
                child: Container(
                  width: 380,
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                      bottom: Radius.zero,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, -2),
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
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: track.albumArtUrl != null
                              ? Image.network(
                                  track.albumArtUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(
                                    Icons.music_note,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                )
                              : Icon(
                                  Icons.music_note,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artists.join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
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
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          track.quality == AudioQuality.flac24Bit ? '24-BIT' : 'FLAC',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
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
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          size: 28,
                        ),
                        onPressed: () {
                          AppLogger.trace('[MiniPlayer.togglePlayPause]', 'isPlaying: $isPlaying');
                          if (isPlaying) {
                            audioEngine.pause();
                          } else {
                            audioEngine.resume();
                          }
                        },
                      ),
                      // Skip Next Button
                      IconButton(
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
                          size: 24,
                        ),
                        onPressed: () {
                          AppLogger.trace('[MiniPlayer.skipNext]');
                          audioEngine.skipToNext();
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
    );
  }
}
