import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../lyrics/ui/synced_lyrics_view.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final audioEngine = ref.watch(audioEngineProvider);
    final lyricsAsync = ref.watch(currentTrackLyricsProvider);

    return StreamBuilder<Track?>(
      stream: audioEngine.currentTrackStream,
      initialData: audioEngine.currentTrack,
      builder: (context, trackSnapshot) {
        final track = trackSnapshot.data;
        if (track == null) {
          return const Scaffold(
            body: Center(child: Text('No song playing')),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Stack(
            children: [
              // Dynamic Blurred Background Glow
              Positioned.fill(
                child: track.albumArtUrl != null
                    ? Image.network(
                        track.albumArtUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      )
                    : Container(color: AppTheme.surface),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Container(
                    color: AppTheme.background.withValues(alpha: 0.85),
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Header: Dismiss & Menu
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Column(
                            children: [
                              Text(
                                _currentPage == 0 ? 'PLAYING FROM VAULT' : 'SYNCHRONIZED LYRICS',
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Text(
                                track.album,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert_rounded),
                            onPressed: () {},
                          ),
                        ],
                      ),

                      // Swipeable Center: Page 0 = Album Art Hero, Page 1 = Module 7 Synced Lyrics
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (page) {
                            setState(() => _currentPage = page);
                          },
                          children: [
                            // Page 0: Center Album Art
                            Center(
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.75,
                                height: MediaQuery.of(context).size.width * 0.75,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(alpha: 0.2),
                                      blurRadius: 40,
                                      spreadRadius: -10,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: track.albumArtUrl != null
                                      ? Image.network(
                                          track.albumArtUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Container(
                                            color: AppTheme.card,
                                            child: const Icon(Icons.music_note, size: 80, color: AppTheme.primary),
                                          ),
                                        )
                                      : Container(
                                          color: AppTheme.card,
                                          child: const Icon(Icons.music_note, size: 80, color: AppTheme.primary),
                                        ),
                                ),
                              ),
                            ),

                            // Page 1: Module 7 Real-time Synced Lyrics
                            lyricsAsync.when(
                              data: (lyrics) => SyncedLyricsView(
                                lyrics: lyrics,
                                positionStream: audioEngine.positionStream,
                                initialPosition: audioEngine.currentPosition,
                                onSeek: (pos) => audioEngine.seek(pos),
                                onRetry: () => ref.invalidate(currentTrackLyricsProvider),
                              ),
                              loading: () => const Center(
                                child: CircularProgressIndicator(color: AppTheme.primary),
                              ),
                              error: (err, stack) => SyncedLyricsView(
                                lyrics: null,
                                positionStream: audioEngine.positionStream,
                                initialPosition: audioEngine.currentPosition,
                                onSeek: (pos) => audioEngine.seek(pos),
                                onRetry: () => ref.invalidate(currentTrackLyricsProvider),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Page Indicator Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: _currentPage == 0 ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _currentPage == 0 ? AppTheme.primary : Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: _currentPage == 1 ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _currentPage == 1 ? AppTheme.primary : Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Track Metadata & Dynamic Audiophile Quality Badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.artists.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StreamBuilder<AudioQuality>(
                            stream: audioEngine.activeQualityStream,
                            initialData: audioEngine.currentActiveQuality,
                            builder: (context, qSnapshot) {
                              final quality = qSnapshot.data ?? audioEngine.currentActiveQuality;
                              String badgeText;
                              switch (quality) {
                                case AudioQuality.flac24Bit:
                                  badgeText = 'Hi-Res 24/192';
                                  break;
                                case AudioQuality.flac16Bit:
                                  badgeText = 'FLAC 16/44.1';
                                  break;
                                case AudioQuality.opus320k:
                                  badgeText = 'Opus 320k';
                                  break;
                                case AudioQuality.lossyFallback:
                                  badgeText = 'Standard';
                                  break;
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  badgeText,
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Seekbar & Timing
                      StreamBuilder<Duration>(
                        stream: audioEngine.positionStream,
                        initialData: audioEngine.currentPosition,
                        builder: (context, posSnapshot) {
                          final position = posSnapshot.data ?? Duration.zero;
                          final totalDuration = Duration(seconds: track.durationSeconds);
                          final double maxSec = totalDuration.inSeconds > 0 ? totalDuration.inSeconds.toDouble() : 1.0;
                          final double curSec = position.inSeconds.clamp(0, maxSec.toInt()).toDouble();

                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                  activeTrackColor: AppTheme.primary,
                                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                                  thumbColor: AppTheme.primary,
                                ),
                                child: Slider(
                                  value: curSec,
                                  max: maxSec,
                                  onChanged: (val) {
                                    audioEngine.seek(Duration(seconds: val.toInt()));
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(position), style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                    Text(_formatDuration(totalDuration), style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // Transport Playback Controls
                      StreamBuilder<PlaybackStatus>(
                        stream: audioEngine.statusStream,
                        initialData: audioEngine.currentStatus,
                        builder: (context, statusSnapshot) {
                          final status = statusSnapshot.data ?? PlaybackStatus.idle;
                          final isPlaying = status == PlaybackStatus.playing;

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Shuffle
                              IconButton(
                                icon: const Icon(Icons.shuffle_rounded, color: AppTheme.textSecondary),
                                onPressed: () => audioEngine.setShuffleMode(true),
                              ),
                              // Skip Previous
                              IconButton(
                                icon: const Icon(Icons.skip_previous_rounded, size: 36),
                                onPressed: () => audioEngine.skipToPrevious(),
                              ),
                              // Play / Pause Floating Hero
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 40,
                                    color: Colors.black,
                                  ),
                                  onPressed: () {
                                    if (isPlaying) {
                                      audioEngine.pause();
                                    } else {
                                      audioEngine.resume();
                                    }
                                  },
                                ),
                              ),
                              // Skip Next
                              IconButton(
                                icon: const Icon(Icons.skip_next_rounded, size: 36),
                                onPressed: () => audioEngine.skipToNext(),
                              ),
                              // Lyrics Toggle (Quick Jump to Page 1)
                              IconButton(
                                icon: Icon(
                                  Icons.lyrics_rounded,
                                  color: _currentPage == 1 ? AppTheme.primary : AppTheme.textSecondary,
                                ),
                                onPressed: () {
                                  _pageController.animateToPage(
                                    _currentPage == 0 ? 1 : 0,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
