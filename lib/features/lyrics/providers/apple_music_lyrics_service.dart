import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
import '../parsers/ttml_parser.dart';

class AppleMusicLyricsService implements LyricsProviderContract {
  final http.Client _httpClient;

  AppleMusicLyricsService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  LyricsSource get source => LyricsSource.appleMusic;

  @override
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    try {
      // Query Apple Music catalog / lyrics endpoints (or upstream bridge proxy)
      final query = Uri.encodeComponent('$title $artist');
      final searchUri = Uri.parse('https://itunes.apple.com/search?term=$query&entity=song&limit=1');
      
      final response = await _httpClient.get(searchUri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final song = results.first as Map<String, dynamic>;
      final trackName = song['trackName'] as String? ?? title;
      final artistName = song['artistName'] as String? ?? artist;

      // Note: Full Apple Music TTML streams require active MediaUserToken or Web API lyrics payloads.
      // If TTML is provided in raw form or via extension proxy:
      final rawTtml = song['ttml'] as String?;
      if (rawTtml != null && rawTtml.isNotEmpty) {
        return parseTtmlLyrics(
          ttmlContent: rawTtml,
          title: trackName,
          artist: artistName,
        );
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Parses a raw TTML XML string into a structured [LyricsResult]
  LyricsResult? parseTtmlLyrics({
    required String ttmlContent,
    required String title,
    required String artist,
  }) {
    final lines = TtmlParser.parse(ttmlContent);
    if (lines.isEmpty) return null;

    final hasWordLevel = lines.any((l) => l.hasWordTiming);

    return LyricsResult(
      trackTitle: title,
      artist: artist,
      format: hasWordLevel ? LyricsFormat.ttml : LyricsFormat.syncedLrc,
      source: LyricsSource.appleMusic,
      rawLyrics: ttmlContent,
      lines: lines,
      qualityScore: LyricsResult.calculateScore(
        hasWordLevel ? LyricsFormat.ttml : LyricsFormat.syncedLrc,
        LyricsSource.appleMusic,
      ),
    );
  }
}
