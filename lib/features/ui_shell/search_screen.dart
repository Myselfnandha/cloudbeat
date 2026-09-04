import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  List<Track> _vaultResults = [];
  List<ExternalTrackResult> _onlineResults = [];
  bool _isSearching = false;
  String _selectedFilter = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _vaultResults = [];
        _onlineResults = [];
        _isSearching = false;
      });
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    final audioEngine = ref.watch(audioEngineProvider);

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
                onChanged: _performSearch,
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
                            _performSearch('');
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

            // Search Results View
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
                              Text(
                                _searchController.text.isEmpty
                                    ? 'Search across Telegram Vault & SpotiFLAC Backends'
                                    : 'No matches found',
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
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
                              ...filteredOnline.map((extTrack) => ListTile(
                                    contentPadding: EdgeInsets.zero,
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
                                        IconButton(
                                          icon: const Icon(
                                            Icons.play_arrow_rounded,
                                            color: AppTheme.textPrimary,
                                            size: 28,
                                          ),
                                          onPressed: () {
                                            // Progressive stream on-demand
                                            final tempTrack = Track(
                                              id: extTrack.id,
                                              title: extTrack.title,
                                              artists: extTrack.artists,
                                              album: extTrack.album,
                                              albumArtUrl: extTrack.albumArtUrl,
                                              durationSeconds: extTrack.durationSeconds,
                                              addedAt: DateTime.now(),
                                            );
                                            audioEngine.play(tempTrack);
                                          },
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                          ],
                        ),
            ),
          ],
        ),
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
