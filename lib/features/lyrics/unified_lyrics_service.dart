import 'package:shared_preferences/shared_preferences.dart';
import '../../core/contracts/lyrics_contract.dart';
import '../../core/contracts/models.dart';
import '../../core/services/app_logger.dart';
import 'providers/apple_music_lyrics_service.dart';
import 'providers/betterlyrics_lyrics_service.dart';
import 'providers/kugou_lyrics_service.dart';
import 'providers/lrclib_lyrics_service.dart';
import 'providers/netease_lyrics_service.dart';
import 'providers/paxsenix_lyrics_service.dart';
import 'providers/simpmusic_lyrics_service.dart';
import 'providers/youlyplus_lyrics_service.dart';

class UnifiedLyricsService implements LyricsContract {
  final List<LyricsProviderContract> _providers;
  final Map<String, LyricsResult> _memoryCache = {};

  UnifiedLyricsService({
    List<LyricsProviderContract>? providers,
  }) : _providers = providers ??
            [
              PaxsenixLyricsService(),
              BetterLyricsService(),
              YouLyPlusLyricsService(),
              LrclibLyricsService(),
              SimpMusicLyricsService(),
              KuGouLyricsService(),
              AppleMusicLyricsService(),
              NeteaseLyricsService(),
            ];

  List<LyricsProviderContract> get providers => List.unmodifiable(_providers);

  String _cacheKey(Track track) {
    return '${track.title.toLowerCase().trim()}_${track.artists.join(',').toLowerCase().trim()}';
  }

  void setManualLyrics(Track track, LyricsResult result) {
    final key = _cacheKey(track);
    _memoryCache[key] = result;
  }

  void clearCache() {
    _memoryCache.clear();
  }

  @override
  Future<LyricsResult?> fetchLyrics(Track track) async {
    AppLogger.trace('UnifiedLyricsService', 'fetchLyrics', {'trackId': track.id, 'title': track.title});
    final key = _cacheKey(track);
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    final artistStr = track.artists.join(', ');
    final trackDuration = Duration(seconds: track.durationSeconds);

    // Read user preferences if available
    String preferredName = 'paxsenix';
    try {
      final prefs = await SharedPreferences.getInstance();
      preferredName = prefs.getString('preferred_lyrics_provider') ?? 'paxsenix';
    } catch (_) {}

    final futures = _providers.map((provider) async {
      try {
        return await provider.fetchLyrics(
          title: track.title,
          artist: artistStr,
          album: track.album,
          duration: trackDuration,
        );
      } catch (_) {
        return null;
      }
    });

    final results = await Future.wait(futures);
    final validResults = results
        .whereType<LyricsResult>()
        .where((r) => r.lines.isNotEmpty || r.rawLyrics.isNotEmpty)
        .toList();

    if (validResults.isEmpty) return null;

    // Sort by quality ranking score, giving slight edge to preferred provider on score ties
    validResults.sort((a, b) {
      int scoreA = a.qualityScore;
      int scoreB = b.qualityScore;
      if (a.source.name.toLowerCase() == preferredName.toLowerCase()) scoreA += 5;
      if (b.source.name.toLowerCase() == preferredName.toLowerCase()) scoreB += 5;
      return scoreB.compareTo(scoreA);
    });

    final bestResult = validResults.first;
    _memoryCache[key] = bestResult;
    return bestResult;
  }

  /// Fetches lyrics from all providers simultaneously for the live source switcher sheet
  Future<Map<LyricsSource, LyricsResult?>> fetchAllProviderResults(Track track) async {
    final artistStr = track.artists.join(', ');
    final trackDuration = Duration(seconds: track.durationSeconds);

    final futures = _providers.map((provider) async {
      try {
        final res = await provider.fetchLyrics(
          title: track.title,
          artist: artistStr,
          album: track.album,
          duration: trackDuration,
        );
        return MapEntry(provider.source, res);
      } catch (_) {
        return MapEntry(provider.source, null);
      }
    });

    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
  }
}
