import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../contracts/acquisition_contract.dart';
import '../contracts/models.dart';
import 'app_logger.dart';

/// Lightweight resolver using the open-source Cobalt API for high-speed audio extraction.
class CobaltStreamResolver {
  final http.Client _client;
  final List<String> _instances;
  String _customInstance;

  CobaltStreamResolver({
    http.Client? client,
    List<String>? instances,
    String customInstance = '',
  })  : _client = client ?? http.Client(),
        _instances = instances ?? [
          'https://api.cobalt.tools',
          'https://cobalt-api.koyeb.app',
          'https://cobalt.xy24.eu.org',
        ],
        _customInstance = customInstance.trim();

  void updateCustomInstance(String url) {
    AppLogger.trace('CobaltStreamResolver', 'updateCustomInstance', {'url': url});
    _customInstance = url.trim();
  }

  /// Resolves an audio stream from an existing media URL (e.g. YouTube, SoundCloud) via Cobalt.
  Future<StreamResolution?> resolveMediaUrl(String mediaUrl) async {
    AppLogger.trace('CobaltStreamResolver', 'resolveMediaUrl', {'mediaUrl': mediaUrl});
    if (mediaUrl.trim().isEmpty) return null;

    final targetInstances = <String>[];
    if (_customInstance.isNotEmpty) {
      targetInstances.add(_customInstance);
    }
    targetInstances.addAll(_instances);

    for (final instance in targetInstances) {
      try {
        final cleanBase = instance.endsWith('/') ? instance.substring(0, instance.length - 1) : instance;
        final endpoint = Uri.parse(cleanBase);

        // Cobalt API v10 / v7 payload format
        final payload = jsonEncode({
          'url': mediaUrl,
          'downloadMode': 'audio',
          'audioFormat': 'opus',
          'audioBitrate': '320',
          'isAudioOnly': true,
        });

        final res = await _client.post(
          endpoint,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'User-Agent': 'CloudBeat/1.1 (AudioStream)',
          },
          body: payload,
        ).timeout(const Duration(seconds: 5));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final data = jsonDecode(res.body);
          if (data is Map<String, dynamic>) {
            final streamUrl = data['url']?.toString();
            if (streamUrl != null && streamUrl.isNotEmpty) {
              return StreamResolution(
                streamUrl: streamUrl,
                quality: AudioQuality.opus320k,
              );
            }
            // Cobalt picker format
            final picker = data['picker'] as List<dynamic>?;
            if (picker != null && picker.isNotEmpty) {
              final firstItem = picker.first;
              if (firstItem is Map && firstItem['url'] != null) {
                return StreamResolution(
                  streamUrl: firstItem['url'].toString(),
                  quality: AudioQuality.opus320k,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[CobaltResolver] Instance $instance error: $e');
      }
    }

    return null;
  }
}
