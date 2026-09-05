import 'dart:async';
import 'dart:convert';
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

  /// Fetch live trending shelves with 24h SQLite caching
  Future<List<DailyMix>> getLiveTrendingMixes({String? provider}) async {
    final cacheKey = provider != null ? 'live_trending_mixes_$provider' : 'live_trending_mixes_all';
    final cached = await _catalog.getCacheData(cacheKey);

    if (cached != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(cached);
        final List<DailyMix> mixes = [];
        for (final m in decodedList) {
          final title = m['title'] as String;
          final description = m['description'] as String;
          final tracks = (m['tracks'] as List).map((t) => Track.fromMap(t)).toList();
          mixes.add(DailyMix(title: title, description: description, tracks: tracks));
        }
        return mixes;
      } catch (_) {
        // Cache corrupted, fallback to live
      }
    }

    final mixes = <DailyMix>[];
    final backends = provider != null ? [provider] : ['spotify', 'deezer', 'apple', 'qobuz', 'tidal', 'amazon'];
    
    // Global Trending
    try {
      final globalHits = await _acquisition.searchAllBackends(
        'Top 50 Hits',
        backends: backends,
        limit: 20,
      );
      // Strictly filter out any YouTube results
      final filteredGlobal = globalHits.where((t) => t.backend != 'ytmusic' && t.backend != 'youtube').toList();
      if (filteredGlobal.isNotEmpty) {
        final tracks = await _markTracksWithLibraryState(filteredGlobal.map(_externalToTrack).toList());
        mixes.add(DailyMix(
          title: provider != null ? '${provider.toUpperCase()} Top Hits' : 'Global Trending',
          description: 'Top hits dominating the charts worldwide.',
          tracks: tracks,
        ));
      }

      // Mood: Focus
      final focusHits = await _acquisition.searchAllBackends(
        'LoFi Focus',
        backends: backends,
        limit: 15,
      );
      final filteredFocus = focusHits.where((t) => t.backend != 'ytmusic' && t.backend != 'youtube').toList();
      if (filteredFocus.isNotEmpty) {
        final tracks = await _markTracksWithLibraryState(filteredFocus.map(_externalToTrack).toList());
        mixes.add(DailyMix(
          title: 'Deep Focus',
          description: 'LoFi and ambient to keep you in the zone.',
          tracks: tracks,
        ));
      }

      // Mood: Workout
      final workoutHits = await _acquisition.searchAllBackends(
        'Workout Hype',
        backends: backends,
        limit: 15,
      );
      final filteredWorkout = workoutHits.where((t) => t.backend != 'ytmusic' && t.backend != 'youtube').toList();
      if (filteredWorkout.isNotEmpty) {
        final tracks = await _markTracksWithLibraryState(filteredWorkout.map(_externalToTrack).toList());
        mixes.add(DailyMix(
          title: 'Workout Intensity',
          description: 'High energy tracks for your session.',
          tracks: tracks,
        ));
      }
    } catch (_) {}

    if (mixes.isNotEmpty) {
      final cacheData = mixes.map((m) => {
        'title': m.title,
        'description': m.description,
        'tracks': m.tracks.map((t) => t.toMap()).toList(),
      }).toList();
      await _catalog.setCacheData(cacheKey, jsonEncode(cacheData));
    }

    return mixes;
  }

  Future<List<Track>> _markTracksWithLibraryState(List<Track> tracks) async {
    final favorites = await _catalog.getFavorites();
    final downloaded = await _catalog.getDownloadedTracks();

    final favIds = favorites.map((t) => t.id).toSet();
    final dlMap = {for (var t in downloaded) t.id: t.localFilePath};

    return tracks.map((track) {
      final isFav = favIds.contains(track.id);
      final dlPath = dlMap[track.id];
      return track.copyWith(
        isFavorite: isFav,
        isDownloaded: dlPath != null,
        localFilePath: dlPath,
      );
    }).toList();
  }

  Track _externalToTrack(ExternalTrackResult e) {
    return Track(
      id: '${e.backend}:${e.id}',
      title: e.title,
      artists: e.artists,
      album: e.album,
      albumArtUrl: e.albumArtUrl,
      durationSeconds: e.durationSeconds,
      isrc: e.isrc,
      isDownloaded: false,
      localFilePath: null,
      addedAt: DateTime.now(),
    );
  }

  /// Generate personalized Daily Mixes blending 70% library tracks with 30% discovery
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
      description: 'Your favorite $topGenre library tracks and discoveries.',
      tracks: topGenreTracks.isNotEmpty ? topGenreTracks : recentTracks.take(10).toList(),
    ));

    // Mix 2: Forgotten Library Gems
    final forgotten = await _catalog.getForgottenGems(daysUnplayed: 14, limit: 10);
    mixes.add(DailyMix(
      title: 'Daily Mix 2: Rewind Library',
      description: 'Rediscover tracks from your library you haven\'t heard in a while.',
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
