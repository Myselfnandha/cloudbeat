import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/services/app_logger.dart';
import '../parsers/lrc_parser.dart';
import '../parsers/ttml_parser.dart';

/// Paxsenix Lyrics Engine (Apple Music Syllable-Level TTML & Duet/Vocal Separation)
class PaxsenixLyricsService implements LyricsProviderContract {
  final http.Client _httpClient;
  String? _cachedAppleToken;
  DateTime? _tokenFetchedAt;

  PaxsenixLyricsService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  @override
  LyricsSource get source => LyricsSource.paxsenix;

  static const String _appleMusicApiBase = 'https://amp-api.music.apple.com/v1/catalog/us';
  static const String _paxsenixBase = 'https://lyrics.paxsenix.org';

  final List<RegExp> _titleCleanup = [
    RegExp(r'\s*\(.*?(official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit).*?\)', caseSensitive: false),
    RegExp(r'\s*\[.*?(official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit).*?\]', caseSensitive: false),
    RegExp(r'\s*【.*?】'),
    RegExp(r'\s*\|.*$'),
    RegExp(r'\s*-\s*(official|video|audio|lyrics|lyric|visualizer).*$', caseSensitive: false),
    RegExp(r'\s*\(feat\..*?\)', caseSensitive: false),
    RegExp(r'\s*\(ft\..*?\)', caseSensitive: false),
    RegExp(r'\s*feat\..*$', caseSensitive: false),
    RegExp(r'\s*ft\..*$', caseSensitive: false),
  ];

  String _cleanTitle(String title) {
    var cleaned = title.trim();
    for (final pattern in _titleCleanup) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    return cleaned.trim();
  }

  String _cleanArtist(String artist) {
    final separators = [' & ', ' and ', ', ', ' x ', ' X ', ' feat. ', ' feat ', ' ft. ', ' ft '];
    var cleaned = artist.trim();
    for (final sep in separators) {
      if (cleaned.toLowerCase().contains(sep.toLowerCase())) {
        cleaned = cleaned.split(RegExp(RegExp.escape(sep), caseSensitive: false))[0];
        break;
      }
    }
    return cleaned.trim();
  }

  Future<String?> _getAppleToken() async {
    if (_cachedAppleToken != null && _tokenFetchedAt != null) {
      if (DateTime.now().difference(_tokenFetchedAt!).inHours < 6) {
        return _cachedAppleToken;
      }
    }

    try {
      final mainPageResp = await _httpClient.get(
        Uri.parse('https://beta.music.apple.com'),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
      );
      if (mainPageResp.statusCode != 200) return null;

      final indexJsMatch = RegExp(r'/assets/index~[^/]+\.js').firstMatch(mainPageResp.body);
      if (indexJsMatch == null) return null;

      final jsUrl = 'https://beta.music.apple.com${indexJsMatch.group(0)}';
      final jsResp = await _httpClient.get(
        Uri.parse(jsUrl),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
      );
      if (jsResp.statusCode != 200) return null;

      final tokenMatch = RegExp(r'eyJ[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+').firstMatch(jsResp.body);
      if (tokenMatch != null) {
        _cachedAppleToken = tokenMatch.group(0);
        _tokenFetchedAt = DateTime.now();
        return _cachedAppleToken;
      }
    } catch (e) {
      AppLogger.trace('PaxsenixLyricsService', 'tokenError', {'error': e.toString()});
    }
    return null;
  }

  @override
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    AppLogger.trace('PaxsenixLyricsService', 'fetchLyrics', {'title': title, 'artist': artist});
    try {
      final token = await _getAppleToken();
      if (token == null) return null;

      final cleanedTitle = _cleanTitle(title);
      final cleanedArtist = _cleanArtist(artist);
      final query = Uri.encodeComponent('$cleanedTitle $cleanedArtist');

      final searchUrl = '$_appleMusicApiBase/search?term=$query&types=songs&limit=10&l=en-US';
      final searchResp = await _httpClient.get(
        Uri.parse(searchUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Origin': 'https://music.apple.com',
          'Referer': 'https://music.apple.com/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      );

      if (searchResp.statusCode != 200) return null;
      final searchData = jsonDecode(searchResp.body) as Map<String, dynamic>;
      final results = searchData['results'] as Map<String, dynamic>?;
      final songsObj = results?['songs'] as Map<String, dynamic>?;
      final songsList = songsObj?['data'] as List<dynamic>?;

      if (songsList == null || songsList.isEmpty) return null;

      // Match best track by duration and title
      String? bestTrackId;
      int bestScore = -1000;
      final targetDurMs = duration?.inMilliseconds ?? 0;

      for (final song in songsList) {
        final id = song['id']?.toString();
        if (id == null) continue;
        final attr = song['attributes'] as Map<String, dynamic>? ?? {};
        final songName = (attr['name'] as String? ?? '').toLowerCase();
        final durMs = attr['durationInMillis'] as int? ?? 0;

        int score = 0;
        if (targetDurMs > 0 && durMs > 0) {
          final diff = (durMs - targetDurMs).abs();
          if (diff <= 2000) {
            score += 100;
          } else if (diff <= 5000) {
            score += 50;
          } else {
            score -= 30;
          }
        }

        if (songName == cleanedTitle.toLowerCase()) {
          score += 80;
        } else if (songName.contains(cleanedTitle.toLowerCase())) {
          score += 40;
        }

        if (score > bestScore) {
          bestScore = score;
          bestTrackId = id;
        }
      }

      if (bestTrackId == null) return null;

      // Query Paxsenix Apple Music lyrics endpoint
      final lyricsUrl = '$_paxsenixBase/apple-music/lyrics?id=$bestTrackId';
      final lyricsResp = await _httpClient.get(
        Uri.parse(lyricsUrl),
        headers: {'User-Agent': 'CloudBeat/1.3.2'},
      );

      if (lyricsResp.statusCode != 200) return null;
      final body = jsonDecode(lyricsResp.body) as Map<String, dynamic>;

      // Priority 1: Raw TTML (rich word-by-word timestamps & agents)
      final ttml = body['ttmlContent'] as String?;
      if (ttml != null && ttml.trim().isNotEmpty) {
        final parsedLines = TtmlParser.parse(ttml);
        if (parsedLines.isNotEmpty) {
          return LyricsResult(
            trackTitle: title,
            artist: artist,
            format: LyricsFormat.ttml,
            source: LyricsSource.paxsenix,
            rawLyrics: ttml,
            lines: parsedLines,
            qualityScore: LyricsResult.calculateScore(LyricsFormat.ttml, LyricsSource.paxsenix),
          );
        }
      }

      // Priority 2: ELRC Multi-Person (agent badges + syllable tags)
      final elrcMulti = body['elrcMultiPerson'] as String?;
      if (elrcMulti != null && elrcMulti.trim().isNotEmpty) {
        final parsedLines = LrcParser.parse(elrcMulti);
        if (parsedLines.isNotEmpty) {
          final hasWords = parsedLines.any((l) => l.hasWordTiming);
          return LyricsResult(
            trackTitle: title,
            artist: artist,
            format: hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc,
            source: LyricsSource.paxsenix,
            rawLyrics: elrcMulti,
            lines: parsedLines,
            qualityScore: LyricsResult.calculateScore(hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc, LyricsSource.paxsenix),
          );
        }
      }

      // Priority 3: ELRC
      final elrc = body['elrc'] as String?;
      if (elrc != null && elrc.trim().isNotEmpty) {
        final parsedLines = LrcParser.parse(elrc);
        if (parsedLines.isNotEmpty) {
          return LyricsResult(
            trackTitle: title,
            artist: artist,
            format: LyricsFormat.syncedLrc,
            source: LyricsSource.paxsenix,
            rawLyrics: elrc,
            lines: parsedLines,
            qualityScore: LyricsResult.calculateScore(LyricsFormat.syncedLrc, LyricsSource.paxsenix),
          );
        }
      }

      // Priority 4: Plain lyrics
      final plain = body['plain'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        final plainLines = plain.split('\n').map((l) => LyricsLine(startTime: Duration.zero, text: l.trim())).where((l) => l.text.isNotEmpty).toList();
        return LyricsResult(
          trackTitle: title,
          artist: artist,
          format: LyricsFormat.plainText,
          source: LyricsSource.paxsenix,
          rawLyrics: plain,
          lines: plainLines,
          qualityScore: LyricsResult.calculateScore(LyricsFormat.plainText, LyricsSource.paxsenix),
        );
      }
    } catch (e) {
      AppLogger.trace('PaxsenixLyricsService', 'fetchError', {'error': e.toString()});
    }
    return null;
  }
}
