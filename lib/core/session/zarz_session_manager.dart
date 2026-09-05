import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ZarzChallenge {
  final String challengeId;
  final String serverNonce;
  final String turnstileSiteKey;
  final int expiresIn;

  const ZarzChallenge({
    required this.challengeId,
    required this.serverNonce,
    required this.turnstileSiteKey,
    required this.expiresIn,
  });

  factory ZarzChallenge.fromJson(Map<String, dynamic> json) {
    return ZarzChallenge(
      challengeId: json['challenge_id']?.toString() ?? '',
      serverNonce: json['server_nonce']?.toString() ?? '',
      turnstileSiteKey: json['turnstile_site_key']?.toString() ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 300,
    );
  }
}

class ZarzSessionCredentials {
  final String sessionId;
  final String sessionSecret;
  final DateTime expiresAt;

  const ZarzSessionCredentials({
    required this.sessionId,
    required this.sessionSecret,
    required this.expiresAt,
  });

  bool get isValid => sessionId.isNotEmpty && DateTime.now().isBefore(expiresAt.subtract(const Duration(seconds: 30)));
}

class ZarzSessionManager {
  static const String defaultBaseUrl = 'https://api.zarz.moe';
  static const String defaultAppVersion = 'deezer@1.3.4';
  static const String callbackScheme = 'cloudbeat';
  static const String callbackHost = 'session-grant';

  final String baseUrl;
  final http.Client _client;
  ZarzSessionCredentials? _cachedCredentials;
  String? _installId;
  ZarzChallenge? _activeChallenge;

  ZarzSessionManager({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _installId = prefs.getString('zarz_install_id');
    if (_installId == null || _installId!.isEmpty) {
      _installId = _generateRandomHex(16);
      await prefs.setString('zarz_install_id', _installId!);
    }

    final savedSessionId = prefs.getString('zarz_session_id');
    final savedSecret = prefs.getString('zarz_session_secret');
    final savedExpiryMs = prefs.getInt('zarz_session_expires_at');

    if (savedSessionId != null && savedSecret != null && savedExpiryMs != null) {
      final expiry = DateTime.fromMillisecondsSinceEpoch(savedExpiryMs);
      if (DateTime.now().isBefore(expiry.subtract(const Duration(seconds: 30)))) {
        _cachedCredentials = ZarzSessionCredentials(
          sessionId: savedSessionId,
          sessionSecret: savedSecret,
          expiresAt: expiry,
        );
      }
    }
  }

  bool get hasValidSession => _cachedCredentials != null && _cachedCredentials!.isValid;

  ZarzSessionCredentials? get credentials => _cachedCredentials;

  String get installId {
    _installId ??= _generateRandomHex(16);
    return _installId!;
  }

  /// Step 1: Bootstrap session challenge from Zarz API
  Future<ZarzChallenge> bootstrap({String appVersion = defaultAppVersion}) async {
    final uri = Uri.parse('$baseUrl/v2/bootstrap').replace(queryParameters: {
      'app_version': appVersion,
      'install_id': installId,
    });

    final res = await _client.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent': 'CloudBeat/1.3.2 (Mobile)',
    }).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw Exception('Zarz bootstrap failed with status ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final challenge = ZarzChallenge.fromJson(data);
    _activeChallenge = challenge;
    return challenge;
  }

  /// Step 2: Open Turnstile challenge in In-App Browser View / Custom Tab
  Future<bool> launchTurnstileChallenge({ZarzChallenge? challenge}) async {
    final active = challenge ?? _activeChallenge ?? await bootstrap();
    _activeChallenge = active;

    final cbUrl = '$callbackScheme://$callbackHost?state=${Uri.encodeComponent(active.serverNonce)}';
    final challengeUri = Uri.parse('$baseUrl/v2/challenge').replace(queryParameters: {
      'id': active.challengeId,
      'cb': cbUrl,
    });

    debugPrint('[Zarz] Launching Turnstile challenge: $challengeUri');
    bool launched = false;
    try {
      launched = await launchUrl(challengeUri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      launched = false;
    }

    if (!launched) {
      launched = await launchUrl(challengeUri, mode: LaunchMode.externalApplication);
    }
    return launched;
  }

  /// Parse deep link callback URI or raw text for grant token
  ({String grant, String state})? parseCallback(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final grant = uri.queryParameters['grant'] ?? uri.queryParameters['code'];
      final state = uri.queryParameters['state'] ?? '';
      if (grant != null && grant.isNotEmpty) {
        return (grant: grant, state: state);
      }
    }

    final grantMatch = RegExp(r'(?:^|[?&#\s])grant=([^&#\s]+)').firstMatch(trimmed);
    final codeMatch = RegExp(r'(?:^|[?&#\s])code=([^&#\s]+)').firstMatch(trimmed);
    final stateMatch = RegExp(r'(?:^|[?&#\s])state=([^&#\s]+)').firstMatch(trimmed);

    final grant = grantMatch?.group(1) ?? codeMatch?.group(1);
    final state = stateMatch?.group(1) ?? '';

    if (grant != null && grant.isNotEmpty) {
      return (grant: Uri.decodeComponent(grant), state: Uri.decodeComponent(state));
    }
    return null;
  }

  /// Step 3: Complete session exchange using the granted Turnstile token
  Future<ZarzSessionCredentials> completeGrant({
    required String grantToken,
    String? challengeId,
    String? state,
  }) async {
    final cid = challengeId ?? _activeChallenge?.challengeId ?? '';
    final s = state ?? _activeChallenge?.serverNonce ?? '';

    final uri = Uri.parse('$baseUrl/v2/session/exchange');
    final payload = jsonEncode({
      'grant_token': grantToken,
      if (cid.isNotEmpty) 'challenge_id': cid,
      if (s.isNotEmpty) 'state': s,
      'install_id': installId,
    });

    final res = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'CloudBeat/1.3.2 (Mobile)',
      },
      body: payload,
    ).timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) {
      throw Exception('Zarz session exchange failed with status ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final sessionId = data['session_id']?.toString() ?? '';
    final sessionSecret = data['session_secret']?.toString() ?? '';
    final ttlSeconds = (data['expires_in'] as num?)?.toInt() ?? 86400;

    if (sessionId.isEmpty || sessionSecret.isEmpty) {
      throw Exception('Malformed session exchange response: ${res.body}');
    }

    final expiresAt = DateTime.now().add(Duration(seconds: ttlSeconds));
    final creds = ZarzSessionCredentials(
      sessionId: sessionId,
      sessionSecret: sessionSecret,
      expiresAt: expiresAt,
    );

    _cachedCredentials = creds;
    _activeChallenge = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zarz_session_id', creds.sessionId);
    await prefs.setString('zarz_session_secret', creds.sessionSecret);
    await prefs.setInt('zarz_session_expires_at', creds.expiresAt.millisecondsSinceEpoch);

    debugPrint('[Zarz] Session established successfully: ${creds.sessionId} (TTL: ${ttlSeconds}s)');
    return creds;
  }

  /// Derive 300-second rolling window key
  static String deriveRollingKey(String sessionSecret, String sessionId, DateTime now) {
    final window = now.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ 300;
    final rollingInput = '$window:$sessionId';

    final hmacKey = Hmac(sha256, utf8.encode(sessionSecret));
    final digest = hmacKey.convert(utf8.encode(rollingInput));
    return _base64UrlNoPad(digest.bytes);
  }

  /// Generate ZARZ-HMAC-V1 signed headers
  Map<String, String> generateSignedHeaders({
    required String method,
    required String path,
    String body = '',
    String appVersion = defaultAppVersion,
    DateTime? timestamp,
  }) {
    final creds = _cachedCredentials;
    if (creds == null || !creds.isValid) {
      throw StateError('Zarz session is not authenticated or expired');
    }

    final now = timestamp ?? DateTime.now().toUtc();
    final nonce = _generateRandomHex(12);

    final bodyBytes = utf8.encode(body);
    final bodyHash = sha256.convert(bodyBytes).toString();

    final timestampISO = '${now.toUtc().toIso8601String().substring(0, 23)}Z';
    const platform = 'extension';

    final rk = deriveRollingKey(creds.sessionSecret, creds.sessionId, now);

    final payload = [
      'ZARZ-HMAC-V1',
      method.toUpperCase(),
      path,
      '', // empty query line
      bodyHash,
      timestampISO,
      nonce,
      creds.sessionId,
      appVersion,
      platform,
    ].join('\n');

    final mac = Hmac(sha256, utf8.encode(rk));
    final signature = _base64UrlNoPad(mac.convert(utf8.encode(payload)).bytes);

    return {
      'X-Zarz-Session': creds.sessionId,
      'X-Zarz-Timestamp': timestampISO,
      'X-Zarz-Nonce': nonce,
      'X-Zarz-Body-SHA256': bodyHash,
      'X-Zarz-App-Version': appVersion,
      'X-Zarz-Platform': platform,
      'X-Zarz-Signature': signature,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  /// Two-Phase Zarz V2 Download Resolution
  Future<Map<String, dynamic>> resolveStreamDescriptor({
    required String provider, // 'qbz', 'dzr', 'tid'
    required String trackId,
    String format = 'FLAC',
  }) async {
    if (!hasValidSession) {
      throw StateError('Zarz session required for $provider stream resolution');
    }

    // Step 1: Mint download ticket via POST /tickets
    final resourceHash = sha256.convert(utf8.encode('$provider:track:$trackId')).toString();
    final ticketBody = jsonEncode({
      'capability': 'download_ticket',
      'provider': provider,
      'resource_hash': resourceHash,
    });

    final ticketHeaders = generateSignedHeaders(
      method: 'POST',
      path: '/tickets',
      body: ticketBody,
      appVersion: _appVersionForProvider(provider),
    );

    final ticketRes = await _client.post(
      Uri.parse('$baseUrl/tickets'),
      headers: ticketHeaders,
      body: ticketBody,
    ).timeout(const Duration(seconds: 10));

    if (ticketRes.statusCode != 200) {
      throw Exception('Ticket minting failed HTTP ${ticketRes.statusCode}: ${ticketRes.body}');
    }

    final ticketData = jsonDecode(ticketRes.body) as Map<String, dynamic>;
    final ticketId = ticketData['ticket_id']?.toString() ?? ticketData['id']?.toString();
    if (ticketId == null || ticketId.isEmpty) {
      throw Exception('No ticket_id returned: ${ticketRes.body}');
    }

    // Step 2: Request stream descriptor via POST /v2/dl/<provider>
    final dlEndpoint = _endpointForProvider(provider);
    final dlPath = '/v2/dl/$dlEndpoint';
    final dlBody = jsonEncode({
      'id': trackId,
      'type': 'track',
      'format': format,
    });

    final dlHeaders = generateSignedHeaders(
      method: 'POST',
      path: dlPath,
      body: dlBody,
      appVersion: _appVersionForProvider(provider),
    );
    dlHeaders['X-Zarz-Ticket'] = ticketId;

    final dlRes = await _client.post(
      Uri.parse('$baseUrl$dlPath'),
      headers: dlHeaders,
      body: dlBody,
    ).timeout(const Duration(seconds: 12));

    if (dlRes.statusCode != 200) {
      throw Exception('Stream descriptor request failed HTTP ${dlRes.statusCode}: ${dlRes.body}');
    }

    return jsonDecode(dlRes.body) as Map<String, dynamic>;
  }

  void invalidateSession() {
    _cachedCredentials = null;
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('zarz_session_id');
      prefs.remove('zarz_session_secret');
      prefs.remove('zarz_session_expires_at');
    });
  }

  static String _endpointForProvider(String provider) {
    switch (provider.toLowerCase()) {
      case 'deezer':
      case 'dzr':
        return 'dzr';
      case 'qobuz':
      case 'qbz':
        return 'qbz';
      case 'tidal':
      case 'tid':
        return 'tid';
      case 'amazon':
      case 'amz':
        return 'amazeamazeamaze';
      default:
        return provider;
    }
  }

  static String _appVersionForProvider(String provider) {
    switch (provider.toLowerCase()) {
      case 'deezer':
      case 'dzr':
        return 'deezer@1.3.4';
      case 'qobuz':
      case 'qbz':
        return 'qobuz-web@1.2.10';
      case 'tidal':
      case 'tid':
        return 'tidal-web@1.2.2';
      default:
        return defaultAppVersion;
    }
  }

  static String _generateRandomHex(int length) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length ~/ 2, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _base64UrlNoPad(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
