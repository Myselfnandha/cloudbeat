import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/contracts/lyrics_contract.dart';
import '../../../core/ffi/netease_ffi.dart';
import '../parsers/lrc_parser.dart';

class NeteaseLyricsService implements LyricsProviderContract {
  final NeteaseFfi _ffi;
  final http.Client _httpClient;

  static const String _searchUrl = 'https://music.163.com/api/search/get';
  static const String _lyricUrl = 'https://music.163.com/api/song/lyric/v1';
  static const String _userAgent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  NeteaseLyricsService({
    NeteaseFfi? ffi,
    http.Client? httpClient,
  })  : _ffi = ffi ?? NeteaseFfi.instance(),
        _httpClient = httpClient ?? http.Client();

  @override
  LyricsSource get source => LyricsSource.netease;

  @override
  Future<LyricsResult?> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final durationMs = duration?.inMilliseconds ?? 0;

    // 1. Attempt Native Rust FFI
    if (_ffi.isAvailable) {
      try {
        final jsonResult = _ffi.fetchNeteaseLyricsJson(title, artist, durationMs: durationMs);
        if (jsonResult != null && jsonResult.isNotEmpty) {
          final data = jsonDecode(jsonResult) as Map<String, dynamic>;
          return _buildFromResultJson(data, title, artist);
        }
      } catch (_) {}
    }

    // 2. Direct HTTP Fallback (for environments without native binary)
    return _fetchViaHttp(title, artist, durationMs);
  }

  Future<LyricsResult?> _fetchViaHttp(String title, String artist, int durationMs) async {
    try {
      final searchUri = Uri.parse(_searchUrl).replace(queryParameters: {
        's': '$title $artist',
        'type': '1',
        'limit': '5',
      });

      final searchResp = await _httpClient.get(searchUri, headers: {
        'User-Agent': _userAgent,
        'Referer': 'https://music.163.com',
      }).timeout(const Duration(seconds: 4));

      if (searchResp.statusCode != 200) return null;

      final searchJson = jsonDecode(searchResp.body) as Map<String, dynamic>;
      final resultObj = searchJson['result'] as Map<String, dynamic>?;
      final songs = (resultObj?['songs'] as List<dynamic>?) ?? [];
      if (songs.isEmpty) return null;

      // Pick song with closest duration or first song
      Map<String, dynamic> song = songs.first as Map<String, dynamic>;
      if (durationMs > 0) {
        int minDiff = 1000000000;
        for (final s in songs) {
          final sMap = s as Map<String, dynamic>;
          final songDur = (sMap['duration'] as int?) ?? 0;
          if (songDur > 0) {
            final diff = (songDur - durationMs).abs();
            if (diff < minDiff) {
              minDiff = diff;
              song = sMap;
            }
          }
        }
      }

      final songId = song['id'];
      if (songId == null) return null;

      final lyricUri = Uri.parse(_lyricUrl).replace(queryParameters: {
        'id': songId.toString(),
        'cp': 'false',
        'lv': '0',
        'tv': '0',
        'rv': '0',
        'kv': '0',
        'yv': '0',
        'ytv': '0',
        'yrv': '0',
      });

      final lyricResp = await _httpClient.get(lyricUri, headers: {
        'User-Agent': _userAgent,
        'Referer': 'https://music.163.com',
      }).timeout(const Duration(seconds: 4));

      if (lyricResp.statusCode != 200) return null;

      final lyricJson = jsonDecode(lyricResp.body) as Map<String, dynamic>;
      final isInstrumental = lyricJson['pureMusic'] as bool? ?? false;

      final yrcMap = lyricJson['yrc'] as Map<String, dynamic>?;
      final yrcText = yrcMap?['lyric'] as String?;

      final lrcMap = lyricJson['lrc'] as Map<String, dynamic>?;
      final lrcText = lrcMap?['lyric'] as String?;

      final songName = song['name'] as String? ?? title;
      final artistsList = (song['artists'] as List<dynamic>?)
              ?.map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
              .where((a) => a.isNotEmpty)
              .join(', ') ??
          artist;

      if (yrcText != null && yrcText.trim().isNotEmpty) {
        final lines = LrcParser.parse(yrcText);
        return LyricsResult(
          trackTitle: songName,
          artist: artistsList,
          format: LyricsFormat.ttml,
          source: LyricsSource.netease,
          rawLyrics: yrcText,
          lines: lines,
          qualityScore: 750, // High-quality YRC sync from Netease
        );
      }

      if (lrcText != null && lrcText.trim().isNotEmpty) {
        final lines = LrcParser.parse(lrcText);
        final isSynced = lines.any((l) => l.startTime > Duration.zero);
        return LyricsResult(
          trackTitle: songName,
          artist: artistsList,
          format: isSynced ? LyricsFormat.syncedLrc : LyricsFormat.plainText,
          source: LyricsSource.netease,
          rawLyrics: lrcText,
          lines: lines,
          qualityScore: LyricsResult.calculateScore(
            isSynced ? LyricsFormat.syncedLrc : LyricsFormat.plainText,
            LyricsSource.netease,
          ),
        );
      }

      if (isInstrumental) {
        return LyricsResult(
          trackTitle: songName,
          artist: artistsList,
          format: LyricsFormat.plainText,
          source: LyricsSource.netease,
          rawLyrics: '[Instrumental]',
          isInstrumental: true,
          qualityScore: LyricsResult.calculateScore(LyricsFormat.plainText, LyricsSource.netease, isInstrumental: true),
        );
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  LyricsResult? _buildFromResultJson(Map<String, dynamic> data, String title, String artist) {
    final rawLyrics = data['raw_lyrics'] as String? ?? '';
    final formatStr = data['format'] as String? ?? 'plain';
    final isInstrumental = data['is_instrumental'] as bool? ?? false;
    final trackTitle = data['title'] as String? ?? title;
    final artistName = data['artist'] as String? ?? artist;

    if (isInstrumental) {
      return LyricsResult(
        trackTitle: trackTitle,
        artist: artistName,
        format: LyricsFormat.plainText,
        source: LyricsSource.netease,
        rawLyrics: '[Instrumental]',
        isInstrumental: true,
        qualityScore: LyricsResult.calculateScore(LyricsFormat.plainText, LyricsSource.netease, isInstrumental: true),
      );
    }

    if (rawLyrics.trim().isEmpty) return null;

    final lines = LrcParser.parse(rawLyrics);
    LyricsFormat format = LyricsFormat.plainText;
    if (formatStr == 'synced_yrc') {
      format = LyricsFormat.ttml;
    } else if (formatStr == 'synced_lrc' || lines.any((l) => l.startTime > Duration.zero)) {
      format = LyricsFormat.syncedLrc;
    }

    return LyricsResult(
      trackTitle: trackTitle,
      artist: artistName,
      format: format,
      source: LyricsSource.netease,
      rawLyrics: rawLyrics,
      lines: lines,
      qualityScore: LyricsResult.calculateScore(format, LyricsSource.netease),
    );
  }
}
