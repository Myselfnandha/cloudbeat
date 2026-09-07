import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/services/app_logger.dart';
import '../parsers/lrc_parser.dart';

/// KuGou Asian & Anime Lyrics Engine (lyrics.kugou.com)
class KuGouLyricsService implements LyricsProviderContract {
  final http.Client _httpClient;

  KuGouLyricsService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  @override
  LyricsSource get source => LyricsSource.kugou;

  static const String _searchSongUrl = 'http://mobilecdn.kugou.com/api/v3/search/song';
  static const String _searchLyricsUrl = 'http://lyrics.kugou.com/search';
  static const String _downloadLyricsUrl = 'http://lyrics.kugou.com/download';

  @override
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    AppLogger.trace('KuGouLyricsService', 'fetchLyrics', {'title': title, 'artist': artist});
    try {
      // 1. Search song to retrieve hash
      final searchSongUri = Uri.parse(_searchSongUrl).replace(queryParameters: {
        'format': 'json',
        'keyword': '$title $artist',
        'page': '1',
        'pagesize': '5',
      });

      final searchSongResp = await _httpClient.get(
        searchSongUri,
        headers: {'User-Agent': 'CloudBeat/1.3.2'},
      ).timeout(const Duration(seconds: 6));

      if (searchSongResp.statusCode != 200) return null;
      final songBody = jsonDecode(searchSongResp.body) as Map<String, dynamic>;
      final songData = songBody['data'] as Map<String, dynamic>?;
      final songInfoList = songData?['info'] as List<dynamic>?;

      if (songInfoList == null || songInfoList.isEmpty) return null;

      final firstSong = songInfoList.first as Map<String, dynamic>;
      final hash = firstSong['hash'] as String? ?? '';
      final durMs = ((firstSong['duration'] as num?)?.toInt() ?? 0) * 1000;

      // 2. Search lyrics candidate
      final searchLrcUri = Uri.parse(_searchLyricsUrl).replace(queryParameters: {
        'ver': '1',
        'man': 'yes',
        'client': 'pc',
        'keyword': title,
        'duration': durMs.toString(),
        if (hash.isNotEmpty) 'hash': hash,
      });

      final searchLrcResp = await _httpClient.get(
        searchLrcUri,
        headers: {'User-Agent': 'CloudBeat/1.3.2'},
      ).timeout(const Duration(seconds: 6));

      if (searchLrcResp.statusCode != 200) return null;
      final lrcBody = jsonDecode(searchLrcResp.body) as Map<String, dynamic>;
      final candidates = lrcBody['candidates'] as List<dynamic>?;

      if (candidates == null || candidates.isEmpty) return null;

      final bestCand = candidates.first as Map<String, dynamic>;
      final lrcId = bestCand['id']?.toString() ?? '';
      final accessKey = bestCand['accesskey']?.toString() ?? '';

      if (lrcId.isEmpty || accessKey.isEmpty) return null;

      // 3. Download base64 lyrics payload
      final downloadUri = Uri.parse(_downloadLyricsUrl).replace(queryParameters: {
        'ver': '1',
        'client': 'pc',
        'id': lrcId,
        'accesskey': accessKey,
        'fmt': 'lrc',
        'charset': 'utf8',
      });

      final downloadResp = await _httpClient.get(
        downloadUri,
        headers: {'User-Agent': 'CloudBeat/1.3.2'},
      ).timeout(const Duration(seconds: 6));

      if (downloadResp.statusCode != 200) return null;
      final downloadBody = jsonDecode(downloadResp.body) as Map<String, dynamic>;
      final b64Content = downloadBody['content'] as String? ?? '';

      if (b64Content.isEmpty) return null;

      final decodedBytes = base64Decode(b64Content);
      final rawLrc = utf8.decode(decodedBytes, allowMalformed: true);

      final lines = LrcParser.parse(rawLrc);
      if (lines.isEmpty) return null;

      final hasWords = lines.any((l) => l.hasWordTiming);
      return LyricsResult(
        trackTitle: title,
        artist: artist,
        format: hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc,
        source: LyricsSource.kugou,
        rawLyrics: rawLrc,
        lines: lines,
        qualityScore: LyricsResult.calculateScore(hasWords ? LyricsFormat.ttml : LyricsFormat.syncedLrc, LyricsSource.kugou),
      );
    } catch (e) {
      AppLogger.trace('KuGouLyricsService', 'fetchError', {'error': e.toString()});
    }
    return null;
  }
}
