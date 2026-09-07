import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';
import '../discovery/discovery_service.dart';
import '../discovery/home_layout_provider.dart';
import '../discovery/discovery_provider.dart';
import 'home_config_modal.dart';
import 'main_navigation_shell.dart';
import '../discovery/innertube_service.dart';

final selectedHomeProviderTab = StateProvider<String>((ref) => 'All');

final innerTubeChartsProvider = FutureProvider<List<Track>>((ref) async {
  final it = ref.watch(innerTubeServiceProvider);
  return it.getCharts();
});

final moodTracksProvider = FutureProvider.family<List<Track>, String>((ref, mood) async {
  final it = ref.watch(innerTubeServiceProvider);
  return it.getMoodTracks(mood);
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final layout = ref.watch(homeLayoutProvider);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                children: [
                  // Center 380×688dp (or dynamic height) M3 box with surfaceContainerHigh and 20dp corners
                  Container(
                    width: 380,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Top-Left Header: Tapping navigates to Home
                        _buildHeader(context, ref),

                        const SizedBox(height: 14),

                        // 2. Chip group: "All", "Spotify", "Qobuz", "Deezer", "Apple"
                        _buildChipGroup(ref),

                        const SizedBox(height: 12),

                        // 2b. M3-Play Moods & Genres Chip Group ("Chill", "Focus", "Workout", "Party", "Sleep", etc.)
                        _buildMoodChipsSection(ref),

                        const SizedBox(height: 18),

                        // 3. Single-row 176dp elevated cards (image + headline + body, no wrap)
                        _build176dpCardsSection(context, ref),

                        const SizedBox(height: 16),

                        // 4. Single-row 96dp elevated cards (image + headline, no wrap)
                        _build96dpCardsSection(context, ref),

                        const SizedBox(height: 18),

                        // 4b. M3-Play InnerTube Charts & Trending Shelf
                        _buildInnerTubeChartsSection(context, ref),

                        const SizedBox(height: 18),

                        // 5. Bold "Recommanded Songs" (14sp)
                        Text(
                          'Recommanded Songs',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // 6. 4 stacked items: leading icon in 40dp primaryContainer circle with 3dp gaps
                        _buildRecommended4StackedItems(context, ref),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Additional Dynamic shelves from layout provider
                  for (final shelfId in layout)
                    _buildShelf(context, ref, shelfId),

                  // Bottom padding for 60dp MiniPlayer
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Top Header: bold "CLOUDBEAT" (24sp) + "Loseless Audio Streaming" (12sp).
  /// Tapping navigates to Home.
  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            AppLogger.trace('[HomeScreen.tapHeaderLogo]');
            ref.read(mainNavigationTabProvider.notifier).state = 0;
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CLOUDBEAT',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Loseless Audio Streaming',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.dashboard_customize_rounded,
            color: colorScheme.primary,
          ),
          tooltip: 'Customize Shelves',
          onPressed: () {
            AppLogger.trace('[HomeScreen.openConfigModal]');
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (context) => const HomeConfigModal(),
            );
          },
        ),
      ],
    );
  }

  /// Chip group: "All", "Spotify", "Qobuz", "Deezer", "Apple"
  Widget _buildChipGroup(WidgetRef ref) {
    final activeTab = ref.watch(selectedHomeProviderTab);
    const providers = ['All', 'Spotify', 'Qobuz', 'Deezer', 'Apple'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: providers.map((p) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Consumer(
              builder: (context, ref, _) {
                final isSelected = activeTab == p;
                final colorScheme = Theme.of(context).colorScheme;

                return FilterChip(
                  label: Text(p),
                  selected: isSelected,
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                  backgroundColor: colorScheme.surfaceContainer,
                  selectedColor: colorScheme.secondaryContainer,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? colorScheme.secondary
                        : colorScheme.outline.withValues(alpha: 0.25),
                  ),
                  onSelected: (_) {
                    AppLogger.trace('[HomeScreen.selectProviderChip]', 'provider: $p');
                    ref.read(selectedHomeProviderTab.notifier).state = p;
                  },
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  /// M3-Play Moods & Genres Chip Bar
  Widget _buildMoodChipsSection(WidgetRef ref) {
    final selectedMood = ref.watch(selectedMoodFilterProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              avatar: const Icon(Icons.explore_rounded, size: 16),
              label: const Text('All Moods'),
              selected: selectedMood == null,
              shape: const StadiumBorder(),
              showCheckmark: false,
              onSelected: (_) => ref.read(selectedMoodFilterProvider.notifier).state = null,
            ),
          ),
          ...InnerTubeService.moodsAndGenres.map((mood) {
            final isSelected = selectedMood == mood;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(mood),
                selected: isSelected,
                shape: const StadiumBorder(),
                showCheckmark: false,
                onSelected: (val) {
                  ref.read(selectedMoodFilterProvider.notifier).state = val ? mood : null;
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  /// M3-Play InnerTube Charts & Trending Shelf
  Widget _buildInnerTubeChartsSection(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedMood = ref.watch(selectedMoodFilterProvider);
    final audioEngine = ref.watch(audioEngineProvider);

    final tracksAsync = selectedMood != null
        ? ref.watch(moodTracksProvider(selectedMood))
        : ref.watch(innerTubeChartsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, color: colorScheme.primary, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      selectedMood != null ? '$selectedMood Hits' : 'InnerTube Charts & Trending',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'InnerTube',
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        tracksAsync.when(
          data: (tracks) {
            if (tracks.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tracks.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      AppLogger.trace('[HomeScreen.playInnerTubeTrack]', 'title: ${track.title}');
                      audioEngine.playTrack(track);
                    },
                    child: SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: track.albumArtUrl != null
                                    ? Image.network(
                                        track.albumArtUrl!,
                                        width: 100,
                                        height: 95,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(
                                          width: 100,
                                          height: 95,
                                          color: colorScheme.surfaceContainerHighest,
                                          child: Icon(Icons.music_note, color: colorScheme.primary),
                                        ),
                                      )
                                    : Container(
                                        width: 100,
                                        height: 95,
                                        color: colorScheme.surfaceContainerHighest,
                                        child: Icon(Icons.music_note, color: colorScheme.primary),
                                      ),
                              ),
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '#${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            track.artists.join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => SizedBox(
            height: 140,
            child: Center(
              child: CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 2),
            ),
          ),
          error: (error, stack) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Single-row 176dp elevated cards (image + headline + body, no wrap)
  Widget _build176dpCardsSection(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final audioEngine = ref.watch(audioEngineProvider);

    // Curated high-res featured cards
    final featuredCards = [
      {
        'title': 'Studio Master 24-Bit',
        'subtitle': 'Bit-perfect Qobuz FLAC',
        'image': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=400&q=80',
        'track': Track(
          id: 'feat:studio_master',
          title: 'Hotel California (Live)',
          artists: ['Eagles'],
          album: 'Hell Freezes Over (24-bit 192kHz)',
          albumArtUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=400&q=80',
          durationSeconds: 432,
          quality: AudioQuality.flac24Bit,
          addedAt: DateTime.now(),
        ),
      },
      {
        'title': 'Audiophile Classics',
        'subtitle': 'Pure dynamic analog masters',
        'image': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400&q=80',
        'track': Track(
          id: 'feat:audiophile_classics',
          title: 'Time (2023 Remaster)',
          artists: ['Pink Floyd'],
          album: 'The Dark Side of the Moon',
          albumArtUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400&q=80',
          durationSeconds: 425,
          quality: AudioQuality.flac24Bit,
          addedAt: DateTime.now(),
        ),
      },
      {
        'title': 'A.R. Rahman FLAC Mix',
        'subtitle': 'Studio soundscape collection',
        'image': 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&q=80',
        'track': Track(
          id: 'feat:rahman_mix',
          title: 'Khwaja Mere Khwaja',
          artists: ['A.R. Rahman'],
          album: 'Jodhaa Akbar (Original Soundtrack)',
          albumArtUrl: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400&q=80',
          durationSeconds: 418,
          quality: AudioQuality.flac16Bit,
          addedAt: DateTime.now(),
        ),
      },
      {
        'title': 'Deezer HiFi Sessions',
        'subtitle': 'CD-Quality 16-bit 1411kbps',
        'image': 'https://images.unsplash.com/photo-1445985543470-41fdd6ce388d?w=400&q=80',
        'track': Track(
          id: 'feat:deezer_hifi',
          title: 'Get Lucky',
          artists: ['Daft Punk', 'Pharrell Williams'],
          album: 'Random Access Memories',
          albumArtUrl: 'https://images.unsplash.com/photo-1445985543470-41fdd6ce388d?w=400&q=80',
          durationSeconds: 369,
          quality: AudioQuality.flac24Bit,
          addedAt: DateTime.now(),
        ),
      },
    ];

    return SizedBox(
      height: 176,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: featuredCards.length,
        itemBuilder: (context, index) {
          final item = featuredCards[index];
          final track = item['track'] as Track;

          return Container(
            width: 138,
            margin: const EdgeInsets.only(right: 12),
            child: Card(
              elevation: 1,
              margin: EdgeInsets.zero,
              color: colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  AppLogger.trace('[HomeScreen.play176dpCard]', 'title: ${item['title']}');
                  audioEngine.playTrack(track);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image container: 100dp height
                    Container(
                      height: 100,
                      width: double.infinity,
                      color: colorScheme.surfaceContainerHighest,
                      child: Image.network(
                        item['image'] as String,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Icon(
                            Icons.album_rounded,
                            color: colorScheme.primary,
                            size: 38,
                          ),
                        ),
                      ),
                    ),
                    // Headline and body (no wrap, 1 line each)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['subtitle'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Single-row 96dp elevated cards (image + headline, no wrap)
  Widget _build96dpCardsSection(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final audioEngine = ref.watch(audioEngineProvider);

    final quickPicks = [
      {
        'headline': 'Anirudh Ravichander',
        'image': 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300&q=80',
        'track': Track(
          id: 'quick:anirudh',
          title: 'Hukum - Thalaivar Alappara',
          artists: ['Anirudh Ravichander'],
          album: 'Jailer (Original Motion Picture Soundtrack)',
          albumArtUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300&q=80',
          durationSeconds: 202,
          quality: AudioQuality.flac24Bit,
          addedAt: DateTime.now(),
        ),
      },
      {
        'headline': 'Daft Punk Lossless',
        'image': 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=300&q=80',
        'track': Track(
          id: 'quick:daftpunk',
          title: 'Instant Crush',
          artists: ['Daft Punk', 'Julian Casablancas'],
          album: 'Random Access Memories (10th Anniversary)',
          albumArtUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=300&q=80',
          durationSeconds: 337,
          quality: AudioQuality.flac24Bit,
          addedAt: DateTime.now(),
        ),
      },
      {
        'headline': 'The Weeknd Hi-Res',
        'image': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300&q=80',
        'track': Track(
          id: 'quick:weeknd',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          albumArtUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300&q=80',
          durationSeconds: 200,
          quality: AudioQuality.flac16Bit,
          addedAt: DateTime.now(),
        ),
      },
    ];

    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: quickPicks.length,
        itemBuilder: (context, index) {
          final item = quickPicks[index];
          final track = item['track'] as Track;

          return Container(
            width: 200,
            margin: const EdgeInsets.only(right: 12),
            child: Card(
              elevation: 1,
              margin: EdgeInsets.zero,
              color: colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  AppLogger.trace('[HomeScreen.play96dpCard]', 'headline: ${item['headline']}');
                  audioEngine.playTrack(track);
                },
                child: Row(
                  children: [
                    // Image on the left
                    Container(
                      width: 96,
                      height: 96,
                      color: colorScheme.surfaceContainerHighest,
                      child: Image.network(
                        item['image'] as String,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: colorScheme.primary,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Headline on the right (no wrap)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          item['headline'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 4 stacked items: leading icon in 40dp primaryContainer circle with 3dp gaps
  Widget _buildRecommended4StackedItems(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final audioEngine = ref.watch(audioEngineProvider);

    final recommendedSongs = [
      Track(
        id: 'rec:1',
        title: 'Starboy',
        artists: ['The Weeknd', 'Daft Punk'],
        album: 'Starboy',
        durationSeconds: 230,
        quality: AudioQuality.flac24Bit,
        addedAt: DateTime.now(),
      ),
      Track(
        id: 'rec:2',
        title: 'Badass (Leo)',
        artists: ['Anirudh Ravichander'],
        album: 'Leo (Original Soundtrack)',
        durationSeconds: 229,
        quality: AudioQuality.flac24Bit,
        addedAt: DateTime.now(),
      ),
      Track(
        id: 'rec:3',
        title: 'Tere Bina',
        artists: ['A.R. Rahman', 'Chinmayi'],
        album: 'Guru (Original Soundtrack)',
        durationSeconds: 309,
        quality: AudioQuality.flac16Bit,
        addedAt: DateTime.now(),
      ),
      Track(
        id: 'rec:4',
        title: 'Comfortably Numb',
        artists: ['Pink Floyd'],
        album: 'The Wall (Experience Edition)',
        durationSeconds: 382,
        quality: AudioQuality.flac24Bit,
        addedAt: DateTime.now(),
      ),
    ];

    String formatDuration(int totalSeconds) {
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }

    return Column(
      children: List.generate(recommendedSongs.length, (index) {
        final track = recommendedSongs[index];

        return Padding(
          padding: EdgeInsets.only(bottom: index < recommendedSongs.length - 1 ? 3.0 : 0.0),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                AppLogger.trace('[HomeScreen.playRecommendedTrack]', 'title: ${track.title}');
                audioEngine.playTrack(track);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    // Leading icon in 40dp primaryContainer circle
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.music_note_rounded,
                          color: colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title and artist
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
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  track.quality == AudioQuality.flac24Bit ? '24-BIT' : 'FLAC',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  track.artists.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Duration & play icon
                    Text(
                      formatDuration(track.durationSeconds),
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.play_arrow_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// Dynamic shelves (Made for you, Library, Discover)
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
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<Track>>(
      future: catalog.getRecentTracks(limit: 6),
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? [];
        if (tracks.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent from Library',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (final track in tracks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    AppLogger.trace('[HomeScreen.playRecentTrack]', 'track: ${track.title}');
                    audioEngine.playTrack(track);
                  },
                  leading: ClipRRect(
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
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    track.artists.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.play_circle_outline_rounded,
                    color: colorScheme.primary,
                    size: 26,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDailyMixesShelf(BuildContext context, WidgetRef ref) {
    final discoveryService = ref.watch(discoveryServiceProvider);
    final audioEngine = ref.watch(audioEngineProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<DailyMix>>(
      future: discoveryService.generateDailyMixes(),
      builder: (context, snapshot) {
        final mixes = snapshot.data ?? [];
        if (mixes.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Made For You',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: mixes.length,
                  itemBuilder: (context, index) {
                    final mix = mixes[index];
                    return GestureDetector(
                      onTap: () {
                        AppLogger.trace('[HomeScreen.playDailyMix]', 'mix: ${mix.title}');
                        if (mix.tracks.isNotEmpty) {
                          audioEngine.playTrack(mix.tracks.first);
                        }
                      },
                      child: Container(
                        width: 140,
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outline.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 70,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primary.withValues(alpha: 0.8),
                                    colorScheme.secondaryContainer,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.auto_awesome_rounded,
                                  color: colorScheme.onPrimary,
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              mix.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              mix.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
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
      },
    );
  }

  Widget _buildDiscoveryShelf(BuildContext context, WidgetRef ref, String shelfId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryProvider.notifier).fetchShelf(shelfId);
    });

    final externalTracks = ref.watch(discoveryProvider)[shelfId] ?? [];
    final audioEngine = ref.watch(audioEngineProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (externalTracks.isEmpty) {
      return const SizedBox.shrink();
    }

    String title = 'Trending';
    if (shelfId == 'spotify_top') {
      title = 'Spotify Top 50';
    } else if (shelfId == 'qobuz_new') {
      title = 'Qobuz Hi-Res New Releases';
    } else if (shelfId == 'deezer_charts') {
      title = 'Deezer Lossless Charts';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: externalTracks.length,
              itemBuilder: (context, index) {
                final track = externalTracks[index];
                return GestureDetector(
                  onTap: () {
                    AppLogger.trace('[HomeScreen.playDiscoveryTrack]', 'title: ${track.title}');
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
                    width: 120,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            height: 120,
                            width: 120,
                            color: colorScheme.surfaceContainerHighest,
                            child: track.albumArtUrl != null
                                ? Image.network(track.albumArtUrl!, fit: BoxFit.cover)
                                : Icon(Icons.music_note, color: colorScheme.primary, size: 36),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track.artists.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
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
