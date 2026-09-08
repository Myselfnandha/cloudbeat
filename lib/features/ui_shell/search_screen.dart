import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';
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
  List<String> _suggestions = [];
  bool _isSearching = false;
  String _selectedFilter = 'All';
  final Set<String> _downloadingIds = {};



  @override
  void initState() {
    super.initState();
    AppLogger.trace('[SearchScreen.initState]');
    _loadRecentQueries();
  }

  Future<void> _loadRecentQueries() async {
    AppLogger.trace('[SearchScreen._loadRecentQueries]');
    final history = await _historyService.getRecentQueries();
    if (mounted) {
      setState(() => _recentQueries = history);
    }
  }

  @override
  void dispose() {
    AppLogger.trace('[SearchScreen.dispose]');
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.isNotEmpty) {
      ref.read(innerTubeServiceProvider).getSearchSuggestions(trimmed).then((suggs) {
        if (mounted) {
          setState(() => _suggestions = suggs);
        }
      });
    } else {
      setState(() => _suggestions = []);
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    AppLogger.trace('[SearchScreen._executeSearch]', 'query: "$query"');
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
        acquisition.searchAllBackends(trimmed, limit: 20),
      ]);

      if (mounted) {
        setState(() {
          _libraryResults = results[0] as List<Track>;
          final allOnline = results[1] as List<ExternalTrackResult>;
          _onlineResults = allOnline.where((t) => t.backend != 'ytmusic' && t.backend != 'youtube').toList();
          _isSearching = false;
        });
        AppLogger.trace('[SearchScreen._executeSearch.complete]', 'lib: ${_libraryResults.length}, online: ${_onlineResults.length}');
      }
    } catch (e, st) {
      AppLogger.e('SearchScreen', 'search failed', e, st);
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _selectQuery(String query) {
    AppLogger.trace('[SearchScreen._selectQuery]', 'query: "$query"');
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _debounceTimer?.cancel();
    _executeSearch(query);
  }

  Future<void> _triggerDownload(Track track) async {
    AppLogger.trace('[SearchScreen._triggerDownload]', 'track: "${track.title}"');
    final downloadManager = ref.read(downloadManagerProvider);

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

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final audioEngine = ref.watch(audioEngineProvider);

    // Filter results if online
    final filteredOnline = _selectedFilter == 'All'
        ? _onlineResults
        : _onlineResults.where((t) => t.backend.toLowerCase() == _selectedFilter.toLowerCase()).toList();

    // Map active results (live search or live trending charts)
    final isQueryActive = _searchController.text.trim().isNotEmpty;
    final trendingAsync = ref.watch(innerTubeChartsProvider);
    final trendingTracks = trendingAsync.value ?? [];

    final List<Track> displayTracks = isQueryActive
        ? [
            ..._libraryResults,
            ...filteredOnline.map((ext) => Track(
                  id: '${ext.backend}:${ext.id}',
                  title: ext.title,
                  artists: ext.artists,
                  album: ext.album,
                  albumArtUrl: ext.albumArtUrl,
                  durationSeconds: ext.durationSeconds,
                  isrc: ext.isrc,
                  quality: ext.availableQualities.isNotEmpty
                      ? ext.availableQualities.first
                      : AudioQuality.flac16Bit,
                  addedAt: DateTime.now(),
                )),
          ]
        : trendingTracks;

    // Limit to 10 items
    final itemsToShow = displayTracks.take(10).toList();

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 56dp rounded search bar on surfaceContainerHigh with search icon & close icon
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onQueryChanged,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search songs, artists, albums...',
                          hintStyle: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        onPressed: () {
                          AppLogger.trace('[SearchScreen.clearQuery]');
                          _searchController.clear();
                          _executeSearch('');
                        },
                      ),
                  ],
                ),
              ),

              // Autocomplete suggestions from InnerTube
              if (_suggestions.isNotEmpty && _searchController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _suggestions.take(8).map((sugg) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          avatar: Icon(Icons.north_west_rounded, size: 14, color: colorScheme.primary),
                          label: Text(sugg),
                          shape: const StadiumBorder(),
                          onPressed: () {
                            _searchController.text = sugg;
                            _executeSearch(sugg);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // 2. Chip group: "All", "Spotify", "Qobuz", "Deezer", "Apple"
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Spotify', 'Qobuz', 'Deezer', 'Apple'].map((filter) {
                    final isSelected = _selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter),
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
                          AppLogger.trace('[SearchScreen.selectFilter]', 'filter: $filter');
                          setState(() => _selectedFilter = filter);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Recent searches history chips if idle
              if (!isQueryActive && _recentQueries.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _recentQueries.take(5).map((q) {
                    return ActionChip(
                      avatar: Icon(Icons.history_rounded, size: 14, color: colorScheme.primary),
                      label: Text(q),
                      backgroundColor: colorScheme.surfaceContainer,
                      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                      shape: const StadiumBorder(),
                      side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.15)),
                      onPressed: () => _selectQuery(q),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 18),

              // 3. Section Title
              Text(
                isQueryActive ? 'Results' : 'Trending Hits & Charts',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),

              const SizedBox(height: 10),

              // Loading spinner if search in flight or charts loading
              if (_isSearching || (!isQueryActive && trendingAsync.isLoading))
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: CircularProgressIndicator(color: colorScheme.primary),
                  ),
                )
              else if (itemsToShow.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      isQueryActive
                          ? 'No lossless tracks found for "${_searchController.text}"'
                          : 'Search songs, artists, albums, or paste a Spotify link',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                    ),
                  ),
                )
              else
                // 4. 8 result list items
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: itemsToShow.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final track = itemsToShow[index];
                    final isDownloading = _downloadingIds.contains(track.id);

                    return Material(
                      color: colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          AppLogger.trace('[SearchScreen.playResultTrack]', 'title: ${track.title}');
                          audioEngine.playTrack(track);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              // Artwork / leading 40dp circle
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: track.albumArtUrl != null
                                      ? Image.network(
                                          track.albumArtUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Icon(
                                            Icons.music_note_rounded,
                                            color: colorScheme.primary,
                                          ),
                                        )
                                      : Icon(
                                          Icons.music_note_rounded,
                                          color: colorScheme.primary,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Title and details
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
                              // Duration
                              Text(
                                _formatDuration(track.durationSeconds),
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Download button
                              IconButton(
                                icon: isDownloading
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colorScheme.primary,
                                        ),
                                      )
                                    : Icon(
                                        Icons.download_rounded,
                                        color: colorScheme.onSurfaceVariant,
                                        size: 20,
                                      ),
                                tooltip: 'Download Offline',
                                onPressed: isDownloading ? null : () => _triggerDownload(track),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // Bottom padding for 60dp MiniPlayer
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
