import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/theme/app_theme.dart';

/// Module 7 Exported Real-time Synchronized Lyrics Component
class SyncedLyricsView extends StatefulWidget {
  final LyricsResult? lyrics;
  final Stream<Duration> positionStream;
  final Duration initialPosition;
  final void Function(Duration position) onSeek;
  final VoidCallback? onRetry;
  final bool isLoading;

  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.positionStream,
    this.initialPosition = Duration.zero,
    required this.onSeek,
    this.onRetry,
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
    _positionSub?.cancel();
    _scrollController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    final lyrics = widget.lyrics;
    final lines = lyrics?.lines ?? [];

    if (lyrics == null || lyrics.isInstrumental || lines.isEmpty) {
      return _buildEmptyState(isInstrumental: lyrics?.isInstrumental ?? false);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final isActive = index == _activeIndex;

        return GestureDetector(
          onTap: () => widget.onSeek(line.startTime),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: line.hasWordTiming
                ? _buildTtmlWordLine(line, isActive)
                : _buildLrcStandardLine(line, isActive),
          ),
        );
      },
    );
  }

  /// TTML Word-by-Word Progressive Glow Mode (Score 1000)
  Widget _buildTtmlWordLine(LyricsLine line, bool isActive) {
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
          weight = FontWeight.w800;
          shadows = [
            Shadow(
              color: AppTheme.primary.withValues(alpha: 0.8),
              blurRadius: 12,
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
            shadows: shadows,
            height: 1.4,
          ),
        );
      }).toList(),
    );
  }

  /// Standard LRC Line-Level Glow Mode (Score 800/700)
  Widget _buildLrcStandardLine(LyricsLine line, bool isActive) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 250),
      style: TextStyle(
        fontSize: isActive ? 22 : 18,
        fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
        color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.3),
        shadows: isActive
            ? [
                Shadow(
                  color: AppTheme.primary.withValues(alpha: 0.7),
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
  Widget _buildEmptyState({required bool isInstrumental}) {
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
                      color: AppTheme.primary.withValues(alpha: 0.6 + (scale * 0.4)),
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
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isInstrumental
                ? 'This track contains no spoken lyrics'
                : 'Could not synchronize lyrics for this track',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 13,
            ),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
