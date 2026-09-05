import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../acquisition/ingestion_state_provider.dart';
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

  List<Track> _vaultResults = [];
  List<ExternalTrackResult> _onlineResults = [];
  List<String> _recentQueries = [];
  bool _isSearching = false;
  String _selectedFilter = 'All';

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
        _vaultResults = [];
        _onlineResults = [];
        _isSearching = false;
      });
      return;
    }

    // Save to persistent history
    await _historyService.addQuery(trimmed);
    _loadRecentQueries();

    setState(() => _isSearching = true);
    final catalog = ref.read(catalogContractProvider);
    final acquisition = ref.read(acquisitionContractProvider);

    try {
      final vaultFuture = catalog.searchLocalTracks(trimmed);
      final onlineFuture = acquisition.searchAllBackends(trimmed);

      final results = await Future.wait([vaultFuture, onlineFuture]);

      if (mounted) {
        setState(() {
          _vaultResults = results[0] as List<Track>;
          _onlineResults = results[1] as List<ExternalTrackResult>;
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

  Future<void> _triggerTrackIngestion(ExternalTrackResult extTrack, {bool isAutoVault = false}) async {
    if (!isAutoVault) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ingesting "${extTrack.title}" to Telegram Vault...'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppTheme.card,
        ),
      );
    }

    final track = await ref.read(ingestionStateProvider.notifier).triggerIngestion(
      extTrack,
      isAutoVault: isAutoVault,
    );

    if (track != null && mounted) {
      // Re-query local vault so the newly ingested track appears immediately
      final catalog = ref.read(catalogContractProvider);
      final updated = await catalog.searchLocalTracks(_searchController.text.trim());
      if (mounted) {
        setState(() => _vaultResults = updated);
      }
    }
  }

  Future<void> _onOnlineRowTapped(ExternalTrackResult extTrack, Track? vaultMatch) async {
    final audioEngine = ref.read(audioEngineProvider);

    // If duplicate in vault exists, play the lossless vault copy directly
    if (vaultMatch != null) {
      await audioEngine.play(vaultMatch);
      return;
    }

    // Otherwise, start progressive playback
    final tempTrack = Track(
      id: extTrack.id,
      title: extTrack.title,
      artists: extTrack.artists,
      album: extTrack.album,
      albumArtUrl: extTrack.albumArtUrl,
      durationSeconds: extTrack.durationSeconds,
      opusFileId: extTrack.isrc,
      flacFileId: extTrack.isrc,
      addedAt: DateTime.now(),
    );
    await audioEngine.play(tempTrack);

    // Check Auto-Vault on Play setting
    final prefs = await SharedPreferences.getInstance();
    final autoVaultEnabled = prefs.getBool('auto_vault_on_play') ?? false;
    if (autoVaultEnabled) {
      _triggerTrackIngestion(extTrack, isAutoVault: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioEngine = ref.watch(audioEngineProvider);
    final ingestionStates = ref.watch(ingestionStateProvider);

    final filteredOnline = _selectedFilter == 'All'
        ? _onlineResults
        : _onlineResults.where((r) {
            if (_selectedFilter == 'Qobuz 24-bit') return r.backend == 'qobuz';
            if (_selectedFilter == 'Deezer FLAC') return r.backend == 'deezer';
            if (_selectedFilter == 'YouTube Music') return r.backend == 'ytmusic';
            return true;
          }).toList();

    final showVault = _selectedFilter == 'All' || _selectedFilter == 'In Vault';
    final showOnline = _selectedFilter != 'In Vault';

    final totalItems = (showVault ? _vaultResults.length : 0) +
        (showOnline ? filteredOnline.length : 0);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Field
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onQueryChanged,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, soundtracks...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted),
                          onPressed: () {
                            _searchController.clear();
                            _executeSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
              ),
            ),

            // Provider & Quality Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  _buildFilterChip('All'),
                  _buildFilterChip('In Vault'),
                  _buildFilterChip('Qobuz 24-bit'),
                  _buildFilterChip('Deezer FLAC'),
                  _buildFilterChip('YouTube Music'),
                ],
              ),
            ),

            // Search Results or Empty State View
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _searchController.text.isEmpty
                      ? _buildEmptyState()
                      : totalItems == 0
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.manage_search_rounded,
                                    size: 64,
                                    color: AppTheme.textMuted.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No matches found',
                                    style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              children: [
                                if (showVault && _vaultResults.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'IN YOUR TELEGRAM VAULT',
                                      style: TextStyle(
                                        color: AppTheme.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
                                  ..._vaultResults.map((track) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            width: 48,
                                            height: 48,
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
                                                : const Icon(Icons.music_note, color: AppTheme.primary),
                                          ),
                                        ),
                                        title: Text(
                                          track.title,
                                          style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          track.artists.join(', '),
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primary.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'VAULT',
                                                style: TextStyle(
                                                  color: AppTheme.primary,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.play_circle_fill_rounded,
                                                color: AppTheme.primary,
                                                size: 32,
                                              ),
                                              onPressed: () => audioEngine.play(track),
                                            ),
                                          ],
                                        ),
                                      )),
                                  const SizedBox(height: 16),
                                ],

                                if (showOnline && filteredOnline.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'SPOTIFLAC ONLINE ACQUISITION',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
                                  ...filteredOnline.map((extTrack) {
                                    final vaultMatch = DeduplicationMatcher.findMatch(extTrack, _vaultResults);
                                    final ingestionStatus = ingestionStates[extTrack.id] ?? IngestionStatus.idle;

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      onTap: () => _onOnlineRowTapped(extTrack, vaultMatch),
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: 48,
                                          height: 48,
                                          color: AppTheme.card,
                                          child: extTrack.albumArtUrl != null
                                              ? Image.network(
                                                  extTrack.albumArtUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) => const Icon(
                                                    Icons.cloud_download_rounded,
                                                    color: AppTheme.accentGradientStart,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.cloud_download_rounded,
                                                  color: AppTheme.accentGradientStart,
                                                ),
                                        ),
                                      ),
                                      title: Text(
                                        extTrack.title,
                                        style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${extTrack.artists.join(", ")} • ${extTrack.backend.toUpperCase()}',
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Badge: IN VAULT or Provider Tag
                                          if (vaultMatch != null || ingestionStatus == IngestionStatus.completed)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.greenAccent.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'IN VAULT',
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

                                          // 1-Tap Vault Ingestion Button
                                          if (vaultMatch == null && ingestionStatus != IngestionStatus.completed)
                                            _buildIngestionButton(extTrack, ingestionStatus),

                                          // Instant Play Button
                                          IconButton(
                                            icon: const Icon(
                                              Icons.play_arrow_rounded,
                                              color: AppTheme.textPrimary,
                                              size: 28,
                                            ),
                                            onPressed: () => _onOnlineRowTapped(extTrack, vaultMatch),
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

  Widget _buildIngestionButton(ExternalTrackResult extTrack, IngestionStatus status) {
    switch (status) {
      case IngestionStatus.inProgress:
      case IngestionStatus.queued:
        return const SizedBox(
          width: 32,
          height: 32,
          child: Padding(
            padding: EdgeInsets.all(6.0),
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
          ),
        );
      case IngestionStatus.completed:
        return const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 24);
      case IngestionStatus.error:
        return IconButton(
          icon: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 22),
          onPressed: () => _triggerTrackIngestion(extTrack),
        );
      case IngestionStatus.idle:
        return IconButton(
          icon: const Icon(Icons.cloud_upload_outlined, color: AppTheme.primary, size: 24),
          tooltip: 'Save to Telegram Vault',
          onPressed: () => _triggerTrackIngestion(extTrack),
        );
    }
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent Searches Section
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
                  child: const Text(
                    'Clear All',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
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

          // Quick Trending Suggestions
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
