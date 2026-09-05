import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../discovery/discovery_service.dart';
import 'search/deduplication_matcher.dart';
import 'search/search_history_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _historyService = SearchHistoryService();
  Timer? _debounceTimer;

  List<Track> _libraryResults = [];
  List<ExternalTrackResult> _onlineResults = [];
  List<String> _recentQueries = [];
  bool _isSearching = false;
  String _selectedFilter = 'All';
  final Set<String> _downloadingIds = {};

  static const List<String> _trendingSuggestions = [
    'Tamil Hits',
    '24-bit Hi-Res',
    'Night Drive',
    'Chill Acoustic',
    'Global Viral',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecentQueries();
  }

  Future<void> _loadRecentQueries() async {
    final history = await _historyService.getRecentQueries();
    if (mounted) {
      setState(() => _recentQueries = history);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _libraryResults = [];
        _onlineResults = [];
        _isSearching = false;
      });
      return;
    }

    await _historyService.addQuery(trimmed);
    _loadRecentQueries();

    setState(() => _isSearching = true);

    final catalog = ref.read(catalogContractProvider);
    final acquisition = ref.read(acquisitionContractProvider);

    try {
      final results = await Future.wait([
        catalog.searchLocalTracks(trimmed),
        acquisition.searchAllBackends(trimmed, limit: 30),
      ]);

      if (mounted) {
        setState(() {
          _libraryResults = results[0] as List<Track>;
          final allOnline = results[1] as List<ExternalTrackResult>;
          // Exclude YouTube results strictly
          _onlineResults = allOnline.where((t) => t.backend != 'ytmusic' && t.backend != 'youtube').toList();
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _selectQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _debounceTimer?.cancel();
    _executeSearch(query);
  }

  Future<void> _onOnlineRowTapped(ExternalTrackResult extTrack, Track? libraryMatch) async {
    final audioEngine = ref.read(audioEngineProvider);

    if (libraryMatch != null) {
      await audioEngine.playTrack(libraryMatch);
      return;
    }

    final tempTrack = Track(
      id: '${extTrack.backend}:${extTrack.id}',
      title: extTrack.title,
      artists: extTrack.artists,
      album: extTrack.album,
      albumArtUrl: extTrack.albumArtUrl,
      durationSeconds: extTrack.durationSeconds,
      isrc: extTrack.isrc,
      quality: extTrack.availableQualities.isNotEmpty
          ? extTrack.availableQualities.first
          : AudioQuality.flac16Bit,
      addedAt: DateTime.now(),
    );
    await audioEngine.playTrack(tempTrack);
  }

  Future<void> _triggerDownload(ExternalTrackResult extTrack) async {
    final downloadManager = ref.read(downloadManagerProvider);
    final track = Track(
      id: '${extTrack.backend}:${extTrack.id}',
      title: extTrack.title,
      artists: extTrack.artists,
      album: extTrack.album,
      albumArtUrl: extTrack.albumArtUrl,
      durationSeconds: extTrack.durationSeconds,
      isrc: extTrack.isrc,
      quality: extTrack.availableQualities.isNotEmpty
          ? extTrack.availableQualities.first
          : AudioQuality.flac16Bit,
      addedAt: DateTime.now(),
    );

    setState(() => _downloadingIds.add(track.id));
    try {
      await downloadManager.downloadTrack(track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded "${track.title}" offline!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloadingIds.remove(track.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioEngine = ref.watch(audioEngineProvider);

    final filteredOnline = _selectedFilter == 'All'
        ? _onlineResults
        : _onlineResults.where((t) => t.backend.toLowerCase() == _selectedFilter.toLowerCase()).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              _executeSearch('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),

            // Provider Filter Chips
            if (_searchController.text.trim().isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    _buildFilterChip('All'),
                    _buildFilterChip('Spotify'),
                    _buildFilterChip('Qobuz'),
                    _buildFilterChip('Tidal'),
                    _buildFilterChip('Deezer'),
                    _buildFilterChip('Apple'),
                    _buildFilterChip('Amazon'),
                  ],
                ),
              ),

            // Body: Empty State or Results
            Expanded(
              child: _searchController.text.trim().isEmpty
                  ? _buildEmptyState()
                  : _isSearching
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          children: [
                            // Library Results Section
                            if (_libraryResults.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'IN YOUR LIBRARY',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                              ..._libraryResults.map((track) {
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
                                      if (track.isDownloaded)
                                        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                                      IconButton(
                                        icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.primary, size: 30),
                                        onPressed: () => audioEngine.playTrack(track),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 16),
                            ],

                            // Multi-Provider Online Results
                            if (filteredOnline.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'ONLINE RESULTS',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                              ...filteredOnline.map((extTrack) {
                                final libraryMatch = DeduplicationMatcher.findMatch(extTrack, _libraryResults);
                                final isTrackDownloading = _downloadingIds.contains('${extTrack.backend}:${extTrack.id}');

                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  onTap: () => _onOnlineRowTapped(extTrack, libraryMatch),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      color: AppTheme.card,
                                      child: extTrack.albumArtUrl != null
                                          ? Image.network(extTrack.albumArtUrl!, fit: BoxFit.cover)
                                          : const Icon(Icons.music_note, color: AppTheme.primary),
                                    ),
                                  ),
                                  title: Text(
                                    extTrack.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${extTrack.artists.join(', ')} • ${extTrack.album}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Library / Provider Badge
                                      if (libraryMatch != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'IN LIBRARY',
                                            style: TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            extTrack.backend.toUpperCase(),
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),

                                      // Download Button
                                      if (isTrackDownloading)
                                        const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                                        )
                                      else if (libraryMatch == null)
                                        IconButton(
                                          icon: const Icon(Icons.download_rounded, color: AppTheme.textMuted, size: 22),
                                          tooltip: 'Download Offline',
                                          onPressed: () => _triggerDownload(extTrack),
                                        ),

                                      // Instant Play
                                      IconButton(
                                        icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.textPrimary, size: 28),
                                        onPressed: () => _onOnlineRowTapped(extTrack, libraryMatch),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final discoveryService = ref.watch(discoveryServiceProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent Searches
          if (_recentQueries.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RECENT SEARCHES',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await _historyService.clearHistory();
                    _loadRecentQueries();
                  },
                  child: const Text('Clear All', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recentQueries.map((query) {
                return InputChip(
                  label: Text(query, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  backgroundColor: AppTheme.card,
                  deleteIcon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                  onDeleted: () async {
                    await _historyService.removeQuery(query);
                    _loadRecentQueries();
                  },
                  onPressed: () => _selectQuery(query),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Trending Chips
          const Text(
            'TRENDING DISCOVERY',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _trendingSuggestions.map((trend) {
              return ActionChip(
                label: Text(trend, style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onPressed: () => _selectQuery(trend),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // Top 50 Chart Preview from Discovery Cache
          const Text(
            'TOP CHARTS PREVIEW',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<DailyMix>>(
            future: discoveryService.getLiveTrendingMixes(),
            builder: (context, snapshot) {
              final mixes = snapshot.data ?? [];
              if (mixes.isEmpty) {
                return const SizedBox.shrink();
              }
              final topTracks = mixes.first.tracks.take(6).toList();
              final audioEngine = ref.read(audioEngineProvider);

              return Column(
                children: topTracks.map((track) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 44,
                        height: 44,
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
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      track.artists.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.primary, size: 24),
                      onPressed: () => audioEngine.playTrack(track),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.card,
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
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
