import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../contracts/acquisition_contract.dart';
import '../contracts/models.dart';
import '../matching/track_matcher.dart';

/// Lightweight YouTube Music / Piped audio stream resolver with multi-instance rotation.
class PipedStreamResolver {
  final http.Client _client;
  final List<String> _pipedInstances;
  final List<String> _invidiousInstances;
  int _currentPipedIndex = 0;
  int _currentInvidiousIndex = 0;

  PipedStreamResolver({
    http.Client? client,
    List<String>? pipedInstances,
    List<String>? invidiousInstances,
  })  : _client = client ?? http.Client(),
        _pipedInstances = pipedInstances ?? [
          'https://pipedapi.kavin.rocks',
          'https://api.piped.privacydev.net',
          'https://piped-api.garudalinux.org',
          'https://pipedapi.tokhmi.xyz',
          'https://pipedapi.leptons.xyz',
          'https://yt.drgnz.club',
        ],
        _invidiousInstances = invidiousInstances ?? [
          'https://inv.tux.pizza/api/v1',
          'https://invidious.nerdvpn.de/api/v1',
          'https://vid.puffyan.us/api/v1',
          'https://invidious.privacydev.net/api/v1',
        ];

  /// Resolves an audio stream URL for track [title] and [artist]
  Future<StreamResolution?> resolveAudioStream({
    required String title,
    required String artist,
    int durationSeconds = 0,
  }) async {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    if (cleanTitle.isEmpty) return null;

    // 1. Try Piped API instances
    for (int i = 0; i < _pipedInstances.length; i++) {
      final instance = _pipedInstances[(_currentPipedIndex + i) % _pipedInstances.length];
      try {
        final resolution = await _resolveFromPiped(instance, cleanTitle, cleanArtist, durationSeconds);
        if (resolution != null) {
          _currentPipedIndex = (_currentPipedIndex + i) % _pipedInstances.length;
          return resolution;
        }
      } catch (e) {
        debugPrint('[PipedResolver] Instance $instance error: $e');
      }
    }

    // 2. Try Invidious API instances
    for (int i = 0; i < _invidiousInstances.length; i++) {
      final instance = _invidiousInstances[(_currentInvidiousIndex + i) % _invidiousInstances.length];
      try {
        final resolution = await _resolveFromInvidious(instance, cleanTitle, cleanArtist, durationSeconds);
        if (resolution != null) {
          _currentInvidiousIndex = (_currentInvidiousIndex + i) % _invidiousInstances.length;
          return resolution;
        }
      } catch (e) {
        debugPrint('[PipedResolver] Invidious instance $instance error: $e');
      }
    }

    return null;
  }

  Future<StreamResolution?> _resolveFromPiped(
    String instance,
    String title,
    String artist,
    int durationSeconds,
  ) async {
    final query = Uri.encodeComponent('$title $artist'.trim());
    final searchUri = Uri.parse('$instance/search?q=$query&filter=music_songs');
    
    final searchRes = await _client.get(searchUri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 4));

    if (searchRes.statusCode != 200) return null;
    final searchData = jsonDecode(searchRes.body);
    final items = (searchData is Map && searchData['items'] is List)
        ? searchData['items'] as List
        : (searchData is List ? searchData : []);

    if (items.isEmpty) return null;

    String? bestVideoId;
    double bestScore = 0.0;

    for (final item in items) {
      if (item is! Map) continue;
      final candTitle = item['title']?.toString() ?? '';
      final candUploader = item['uploaderName']?.toString() ?? item['uploader']?.toString() ?? '';
      final candDuration = (item['duration'] as num?)?.toInt() ?? 0;
      final url = item['url']?.toString() ?? '';
      final videoId = url.contains('v=') ? url.split('v=')[1].split('&')[0] : url.replaceFirst('/watch?v=', '');

      if (videoId.isEmpty) continue;

      double score = TrackMatcher.scoreTrackMatch(
        targetTitle: title,
        targetArtist: artist,
        candidateTitle: candTitle,
        candidateArtist: candUploader,
        targetDuration: durationSeconds,
        candidateDuration: candDuration,
      );

      // Clean stream boost: Official YouTube Music Topic channels provide pristine album cuts
      if (candUploader.trim().endsWith(' - Topic') || candUploader.trim().endsWith('Topic')) {
        score += 20.0;
      }

      // Penalize movie clip / film production channels
      final uploaderLower = candUploader.toLowerCase();
      if ((uploaderLower.contains('movie') || uploaderLower.contains('film') || uploaderLower.contains('cinema')) &&
          !artist.toLowerCase().contains('movie')) {
        score -= 25.0;
      }

      if (score > bestScore && score >= 35.0) {
        bestScore = score;
        bestVideoId = videoId;
      }
    }

    final selectedVideoId = bestVideoId;
    if (selectedVideoId == null || selectedVideoId.isEmpty) return null;

    // Fetch stream manifest
    final streamsUri = Uri.parse('$instance/streams/$selectedVideoId');
    final streamsRes = await _client.get(streamsUri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 4));

    if (streamsRes.statusCode != 200) return null;
    final streamsData = jsonDecode(streamsRes.body) as Map<String, dynamic>;
    final audioStreams = streamsData['audioStreams'] as List<dynamic>?;
    if (audioStreams == null || audioStreams.isEmpty) return null;

    // Sort by highest bitrate
    audioStreams.sort((a, b) {
      final b1 = (a['bitrate'] as num?)?.toInt() ?? 0;
      final b2 = (b['bitrate'] as num?)?.toInt() ?? 0;
      return b2.compareTo(b1);
    });

    for (final s in audioStreams) {
      final sUrl = s['url']?.toString();
      if (sUrl != null && sUrl.isNotEmpty) {
        final bitrate = (s['bitrate'] as num?)?.toInt() ?? 128000;
        final quality = bitrate >= 200000 ? AudioQuality.opus320k : AudioQuality.lossyFallback;
        return StreamResolution(
          streamUrl: sUrl,
          quality: quality,
        );
      }
    }

    return null;
  }

  Future<StreamResolution?> _resolveFromInvidious(
    String instance,
    String title,
    String artist,
    int durationSeconds,
  ) async {
    final query = Uri.encodeComponent('$title $artist'.trim());
    final searchUri = Uri.parse('$instance/search?q=$query&type=video');

    final searchRes = await _client.get(searchUri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 4));

    if (searchRes.statusCode != 200) return null;
    final items = jsonDecode(searchRes.body) as List<dynamic>?;
    if (items == null || items.isEmpty) return null;

    String? bestVideoId;
    double bestScore = 0.0;

    for (final item in items) {
      if (item is! Map) continue;
      final candTitle = item['title']?.toString() ?? '';
      final candAuthor = item['author']?.toString() ?? '';
      final candDuration = (item['lengthSeconds'] as num?)?.toInt() ?? 0;
      final videoId = item['videoId']?.toString();

      if (videoId == null || videoId.isEmpty) continue;

      double score = TrackMatcher.scoreTrackMatch(
        targetTitle: title,
        targetArtist: artist,
        candidateTitle: candTitle,
        candidateArtist: candAuthor,
        targetDuration: durationSeconds,
        candidateDuration: candDuration,
      );

      // Clean stream boost: Topic channels
      if (candAuthor.trim().endsWith(' - Topic') || candAuthor.trim().endsWith('Topic')) {
        score += 20.0;
      }

      // Penalize movie clip / film production channels
      final authorLower = candAuthor.toLowerCase();
      if ((authorLower.contains('movie') || authorLower.contains('film') || authorLower.contains('cinema')) &&
          !artist.toLowerCase().contains('movie')) {
        score -= 25.0;
      }

      if (score > bestScore && score >= 35.0) {
        bestScore = score;
        bestVideoId = videoId;
      }
    }

    final selectedId = bestVideoId;
    if (selectedId == null || selectedId.isEmpty) return null;

    final videoUri = Uri.parse('$instance/videos/$selectedId');
    final videoRes = await _client.get(videoUri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 4));

    if (videoRes.statusCode != 200) return null;
    final videoData = jsonDecode(videoRes.body) as Map<String, dynamic>;
    final adaptiveFormats = videoData['adaptiveFormats'] as List<dynamic>?;
    if (adaptiveFormats == null) return null;

    final audioFormats = adaptiveFormats.where((f) => (f['type']?.toString() ?? '').contains('audio')).toList();
    if (audioFormats.isEmpty) return null;

    audioFormats.sort((a, b) {
      final b1 = (a['bitrate'] as num?)?.toInt() ?? 0;
      final b2 = (b['bitrate'] as num?)?.toInt() ?? 0;
      return b2.compareTo(b1);
    });

    for (final f in audioFormats) {
      final url = f['url']?.toString();
      if (url != null && url.isNotEmpty) {
        final bitrate = (f['bitrate'] as num?)?.toInt() ?? 128000;
        final quality = bitrate >= 200000 ? AudioQuality.opus320k : AudioQuality.lossyFallback;
        return StreamResolution(
          streamUrl: url,
          quality: quality,
        );
      }
    }

    return null;
  }
}
