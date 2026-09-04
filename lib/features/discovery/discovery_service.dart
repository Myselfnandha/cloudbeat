import 'dart:async';
import '../../core/contracts/acquisition_contract.dart';
import '../../core/contracts/catalog_contract.dart';
import '../../core/contracts/models.dart';

class DailyMix {
  final String title;
  final String description;
  final List<Track> tracks;

  const DailyMix({
    required this.title,
    required this.description,
    required this.tracks,
  });
}

class DiscoveryService {
  final CatalogContract _catalog;
  final AcquisitionContract _acquisition;

  DiscoveryService({
    required CatalogContract catalog,
    required AcquisitionContract acquisition,
  })  : _catalog = catalog,
        _acquisition = acquisition;

  AcquisitionContract get acquisition => _acquisition;

  /// Generate personalized Daily Mixes blending 70% vault tracks with 30% discovery
  Future<List<DailyMix>> generateDailyMixes() async {
    final recentTracks = await _catalog.getRecentTracks(limit: 30);
    final affinityScores = await _catalog.getGenreAffinityScores();
    final highAffinity = await _catalog.getHighAffinityTracks(limit: 20);

    final mixes = <DailyMix>[];

    // Mix 1: Top Affinity Genre
    String topGenre = 'Soundtrack';
    if (affinityScores.isNotEmpty) {
      final sorted = affinityScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topGenre = sorted.first.key;
    }

    final topGenreTracks = highAffinity
        .where((t) => (t.genre?.toLowerCase() ?? '') == topGenre.toLowerCase())
        .toList();

    mixes.add(DailyMix(
      title: 'Daily Mix 1: $topGenre',
      description: 'Your favorite $topGenre vault tracks and discoveries.',
      tracks: topGenreTracks.isNotEmpty ? topGenreTracks : recentTracks.take(10).toList(),
    ));

    // Mix 2: Forgotten Vault Gems
    final forgotten = await _catalog.getForgottenGems(daysUnplayed: 14, limit: 10);
    mixes.add(DailyMix(
      title: 'Daily Mix 2: Rewind Vault',
      description: 'Rediscover tracks from your Telegram vault you haven\'t heard in a while.',
      tracks: forgotten.isNotEmpty ? forgotten : recentTracks.reversed.take(10).toList(),
    ));

    // Mix 3: Acoustic / Chill
    final chillTracks = highAffinity
        .where((t) => (t.genre?.toLowerCase() ?? '').contains('chill') ||
                      (t.genre?.toLowerCase() ?? '').contains('acoustic'))
        .toList();

    mixes.add(DailyMix(
      title: 'Daily Mix 3: Chill & Unwind',
      description: 'Mellow grooves and relaxed rhythms.',
      tracks: chillTracks.isNotEmpty ? chillTracks : recentTracks.take(8).toList(),
    ));

    return mixes;
  }

  /// Infinite Auto-Radio generator when queue ends
  Future<List<Track>> generateAutoRadio(Track seedTrack) async {
    final sameArtist = await _catalog.getTracksByArtist(
      seedTrack.artists.isNotEmpty ? seedTrack.artists.first : '',
    );
    final sameGenre = (await _catalog.getHighAffinityTracks(limit: 20))
        .where((t) => t.genre == seedTrack.genre && t.id != seedTrack.id)
        .toList();

    final radioTracks = <Track>[];
    radioTracks.addAll(sameArtist.where((t) => t.id != seedTrack.id).take(5));
    radioTracks.addAll(sameGenre.take(10));

    if (radioTracks.isEmpty) {
      radioTracks.addAll(await _catalog.getRecentTracks(limit: 10));
    }
    return radioTracks;
  }
}
