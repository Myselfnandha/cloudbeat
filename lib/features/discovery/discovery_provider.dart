import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/providers.dart';
import '../acquisition/native_acquisition_service.dart';

final discoveryProvider = StateNotifierProvider<DiscoveryNotifier, Map<String, List<ExternalTrackResult>>>((ref) {
  final catalog = ref.read(catalogContractProvider);
  final acquisition = ref.read(acquisitionContractProvider);
  return DiscoveryNotifier(catalog, acquisition);
});

class DiscoveryNotifier extends StateNotifier<Map<String, List<ExternalTrackResult>>> {
  final CatalogContract _catalog;
  final AcquisitionContract _acquisition;

  DiscoveryNotifier(this._catalog, this._acquisition) : super({}) {
    // We don't automatically load all, let the UI request what it needs
  }

  Future<void> fetchShelf(String shelfId) async {
    // Already in memory?
    if (state.containsKey(shelfId) && state[shelfId]!.isNotEmpty) return;

    // Check DB Cache (ephemeral)
    final cacheKey = 'discovery_shelf_$shelfId';
    final cachedData = await _catalog.getCacheData(cacheKey);
    if (cachedData != null) {
      try {
        final decoded = jsonDecode(cachedData) as List;
        final tracks = decoded.map((m) {
          final map = m as Map<String, dynamic>;
          List<AudioQuality> qualities = [AudioQuality.flac16Bit];
          if (map['availableQualities'] is List) {
            qualities = (map['availableQualities'] as List).map((q) => 
              AudioQuality.values.firstWhere((e) => e.toString() == q, orElse: () => AudioQuality.flac16Bit)
            ).toList();
          }
          return ExternalTrackResult(
            id: map['id'],
            title: map['title'],
            artists: List<String>.from(map['artists'] ?? []),
            album: map['album'],
            albumArtUrl: map['albumArtUrl'],
            durationSeconds: map['durationSeconds'] ?? 180,
            backend: map['backend'] ?? 'unknown',
            availableQualities: qualities,
            isrc: map['isrc'],
          );
        }).toList();
        
        state = {...state, shelfId: tracks};
        return;
      } catch (e) {
        print('Error parsing cache for shelf $shelfId: $e');
      }
    }

    // Cache miss or expired, fetch from acquisition layer
    String backend = 'deezer'; // Default
    if (shelfId == 'spotify_top') backend = 'spotify';
    else if (shelfId == 'qobuz_new') backend = 'qobuz';
    else if (shelfId == 'deezer_charts') backend = 'deezer';
    else if (shelfId == 'ytmusic_trending') backend = 'ytmusic';
    
    final results = await _acquisition.getTrending(backend);
    
    if (results.isNotEmpty) {
      state = {...state, shelfId: results};
      
      // Save to cache with 24h TTL
      final jsonList = results.map((r) => {
        'id': r.id,
        'title': r.title,
        'artists': r.artists,
        'album': r.album,
        'albumArtUrl': r.albumArtUrl,
        'durationSeconds': r.durationSeconds,
        'backend': r.backend,
        'availableQualities': r.availableQualities.map((q) => q.toString()).toList(),
        'isrc': r.isrc,
      }).toList();
      
      await _catalog.setCacheData(cacheKey, jsonEncode(jsonList), expiresIn: const Duration(hours: 24));
    }
  }
}
