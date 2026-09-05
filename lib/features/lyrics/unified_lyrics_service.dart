import '../../core/contracts/lyrics_contract.dart';
import '../../core/contracts/models.dart';
import 'providers/apple_music_lyrics_service.dart';
import 'providers/lrclib_lyrics_service.dart';
import 'providers/netease_lyrics_service.dart';

class UnifiedLyricsService implements LyricsContract {
  final List<LyricsProviderContract> _providers;
  final Map<String, LyricsResult> _memoryCache = {};

  UnifiedLyricsService({
    List<LyricsProviderContract>? providers,
  }) : _providers = providers ??
            [
              AppleMusicLyricsService(),
              LrclibLyricsService(),
              NeteaseLyricsService(),
            ];

  @override
  Future<LyricsResult?> fetchLyrics(Track track) async {
    final cacheKey = '${track.title.toLowerCase().trim()}_${track.artists.join(',').toLowerCase().trim()}';
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    final artistStr = track.artists.join(', ');
    final trackDuration = Duration(seconds: track.durationSeconds);

    // Query all providers concurrently with timeout protection
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
    final validResults = results.whereType<LyricsResult>().toList();

    if (validResults.isEmpty) return null;

    // Pick candidate with highest quality ranking score
    validResults.sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
    final bestResult = validResults.first;

    _memoryCache[cacheKey] = bestResult;
    return bestResult;
  }
}
