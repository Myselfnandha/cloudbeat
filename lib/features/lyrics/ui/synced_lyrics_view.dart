import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/contracts/models.dart';
import '../../../core/services/app_logger.dart';
import 'lyric_image_card_sheet.dart';

/// Module 7 Exported Real-time Synchronized Lyrics Component with Word-by-Word Glow,
/// Vocal Separation, Live Provider Switcher, and Lyric Card Exporter
class SyncedLyricsView extends StatefulWidget {
  final LyricsResult? lyrics;
  final Track? track;
  final Stream<Duration> positionStream;
  final Duration initialPosition;
  final void Function(Duration position) onSeek;
  final VoidCallback? onRetry;
  final void Function(LyricsSource source)? onProviderChanged;
  final bool isLoading;

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    this.track,
    required this.positionStream,
    this.initialPosition = Duration.zero,
    required this.onSeek,
    this.onRetry,
    this.onProviderChanged,
    this.isLoading = false,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Duration>? _positionSub;
  Duration _currentPosition = Duration.zero;
  int _activeIndex = -1;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    AppLogger.trace('[SyncedLyricsView.initState]', 'lines: ${widget.lyrics?.lines.length ?? 0}, instrumental: ${widget.lyrics?.isInstrumental}');
    _currentPosition = widget.initialPosition;
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    final isEmpty = widget.lyrics == null || (widget.lyrics?.isInstrumental ?? false) || (widget.lyrics?.lines.isEmpty ?? true);
    if (isEmpty) {
      _waveController.repeat(reverse: true);
    }

    _positionSub = widget.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _updateActiveIndex();
      });
    });
  }

  @override
  void didUpdateWidget(SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lyrics != oldWidget.lyrics) {
      AppLogger.trace('[SyncedLyricsView.didUpdateWidget]', 'lyrics updated: lines: ${widget.lyrics?.lines.length ?? 0}');
      final isEmpty = widget.lyrics == null ||
          (widget.lyrics?.isInstrumental ?? false) ||
          (widget.lyrics?.lines.isEmpty ?? true);
      if (isEmpty && !_waveController.isAnimating) {
        _waveController.repeat(reverse: true);
      } else if (!isEmpty && _waveController.isAnimating) {
        _waveController.stop();
      }
      _updateActiveIndex();
    }
  }

  void _updateActiveIndex() {
    final lines = widget.lyrics?.lines;
    if (lines == null || lines.isEmpty) {
      _activeIndex = -1;
      return;
    }

    int newIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startTime <= _currentPosition) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _activeIndex) {
      _activeIndex = newIndex;
      _scrollToActiveIndex();
    }
  }

  void _scrollToActiveIndex() {
    if (_activeIndex < 0 || !_scrollController.hasClients) return;
    AppLogger.trace('[SyncedLyricsView._scrollToActiveIndex]', 'activeIndex: $_activeIndex');
    const itemEstimateHeight = 56.0;
    final targetOffset = (_activeIndex * itemEstimateHeight) - 150.0;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    AppLogger.trace('[SyncedLyricsView.dispose]');
    _positionSub?.cancel();
    _scrollController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _showProviderSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentSource = widget.lyrics?.source;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Lyrics Source',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...LyricsSource.values.map((src) {
                final isSelected = src == currentSource;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    src.displayName,
                    style: TextStyle(
                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Active',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (widget.onProviderChanged != null) {
                      widget.onProviderChanged!(src);
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    final lyrics = widget.lyrics;
    final lines = lyrics?.lines ?? [];

    if (lyrics == null || lyrics.isInstrumental || lines.isEmpty) {
      return _buildEmptyState(context, isInstrumental: lyrics?.isInstrumental ?? false);
    }

    return Column(
      children: [
        // Lyrics Controls Header: Source Pill & Lyric Card Exporter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Provider pill
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showProviderSelector(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lyrics_rounded, size: 14, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        lyrics.source.displayName,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),

              // Lyric Card generator button
              if (widget.track != null)
                IconButton.filledTonal(
                  icon: const Icon(Icons.style_rounded, size: 18),
                  tooltip: 'Share as Lyric Card',
                  onPressed: () => LyricImageCardSheet.show(
                    context,
                    track: widget.track!,
                    lyrics: lyrics,
                  ),
                ),
            ],
          ),
        ),

        // Synchronized scrolling list
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final isActive = index == _activeIndex;

              return GestureDetector(
                onTap: () => widget.onSeek(line.startTime),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vocal separation badge (v1, v2)
                      if (line.singerAgent != null)
                        Container(
                          margin: const EdgeInsets.only(right: 8, top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: line.singerAgent == 'v2'
                                ? colorScheme.tertiaryContainer
                                : colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            line.singerAgent!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: line.singerAgent == 'v2'
                                  ? colorScheme.onTertiaryContainer
                                  : colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),

                      Expanded(
                        child: line.hasWordTiming
                            ? _buildTtmlWordLine(context, line, isActive)
                            : _buildLrcStandardLine(context, line, isActive),
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
  }

  /// TTML / Syllable Word-by-Word Progressive Glow Mode
  Widget _buildTtmlWordLine(BuildContext context, LyricsLine line, bool isActive) {
    final colorScheme = Theme.of(context).colorScheme;
    final words = line.words!;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: words.map((word) {
        final isWordReached = _currentPosition >= word.startTime;
        final isWordActive = isWordReached && (_currentPosition < word.endTime);

        Color wordColor;
        FontWeight weight;
        List<Shadow>? shadows;

        if (isWordActive) {
          wordColor = Colors.white;
          weight = FontWeight.w900;
          shadows = [
            Shadow(
              color: colorScheme.primary.withValues(alpha: 0.9),
              blurRadius: 14,
            ),
          ];
        } else if (isWordReached) {
          wordColor = Colors.white;
          weight = FontWeight.w700;
          shadows = null;
        } else {
          wordColor = Colors.white.withValues(alpha: isActive ? 0.45 : 0.25);
          weight = FontWeight.w600;
          shadows = null;
        }

        return Text(
          word.text,
          style: TextStyle(
            fontSize: isActive ? 22 : 18,
            color: wordColor,
            fontWeight: weight,
            fontStyle: line.isBackground ? FontStyle.italic : FontStyle.normal,
            shadows: shadows,
            height: 1.4,
          ),
        );
      }).toList(),
    );
  }

  /// Standard LRC Line-Level Glow Mode
  Widget _buildLrcStandardLine(BuildContext context, LyricsLine line, bool isActive) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 250),
      style: TextStyle(
        fontSize: isActive ? 22 : 18,
        fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
        fontStyle: line.isBackground ? FontStyle.italic : FontStyle.normal,
        color: isActive
            ? Colors.white
            : (line.isBackground
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.3)),
        shadows: isActive
            ? [
                Shadow(
                  color: colorScheme.primary.withValues(alpha: 0.7),
                  blurRadius: 14,
                ),
              ]
            : null,
        height: 1.4,
      ),
      child: Text(line.text),
    );
  }

  /// Empty or Instrumental State with Animated Waveform
  Widget _buildEmptyState(BuildContext context, {required bool isInstrumental}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _waveController,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final phase = (i * 0.2);
                  final scale = ((_waveController.value + phase) % 1.0);
                  final height = 16.0 + (scale * 32.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 5,
                    height: height,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.6 + (scale * 0.4)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            isInstrumental ? 'Instrumental' : 'No Lyrics Available',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isInstrumental
                ? 'This track contains no spoken lyrics'
                : 'Could not synchronize lyrics for this track',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry Lyrics'),
              onPressed: widget.onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
