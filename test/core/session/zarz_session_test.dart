import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudbeat/core/session/zarz_session_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZarzSessionManager Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('parseCallback extracts grant and state from callback URI', () {
      final manager = ZarzSessionManager();
      final res = manager.parseCallback('cloudbeat://session-grant?grant=gr_test123&state=nonce_abc');
      expect(res, isNotNull);
      expect(res!.grant, 'gr_test123');
      expect(res.state, 'nonce_abc');

      final resNested = manager.parseCallback('spotiflac://session-grant?code=gr_code456&state=nonce_def');
      expect(resNested, isNotNull);
      expect(resNested!.grant, 'gr_code456');
      expect(resNested.state, 'nonce_def');
    });

    test('deriveRollingKey produces stable 300-second window key', () {
      final now1 = DateTime.utc(2026, 9, 6, 1, 0, 10);
      final now2 = DateTime.utc(2026, 9, 6, 1, 4, 50); // Same 300s window
      final key1 = ZarzSessionManager.deriveRollingKey('test_secret_123', 'sess_test', now1);
      final key2 = ZarzSessionManager.deriveRollingKey('test_secret_123', 'sess_test', now2);
      expect(key1, equals(key2));
      expect(key1.isNotEmpty, isTrue);

      final nextWindow = DateTime.utc(2026, 9, 6, 1, 6, 0); // Next 300s window
      final key3 = ZarzSessionManager.deriveRollingKey('test_secret_123', 'sess_test', nextWindow);
      expect(key1, isNot(equals(key3)));
    });

    test('bootstrap parses challenge response correctly', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/v2/bootstrap')) {
          return http.Response(
            jsonEncode({
              'challenge_id': 'chl_test123',
              'server_nonce': 'nonce_xyz',
              'turnstile_site_key': '0x4AAAAAADIYiNDcnB6HDKKi',
              'expires_in': 300,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final manager = ZarzSessionManager(client: mockClient);
      final challenge = await manager.bootstrap();
      expect(challenge.challengeId, 'chl_test123');
      expect(challenge.serverNonce, 'nonce_xyz');
      expect(challenge.turnstileSiteKey, '0x4AAAAAADIYiNDcnB6HDKKi');
    });

    test('completeGrant exchanges grant token and stores credentials', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/v2/session/exchange')) {
          return http.Response(
            jsonEncode({
              'session_id': 'sess_real123',
              'session_secret': 'sec_secret456',
              'expires_in': 86400,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final manager = ZarzSessionManager(client: mockClient);
      final creds = await manager.completeGrant(
        grantToken: 'gr_token_abc',
        challengeId: 'chl_test123',
        state: 'nonce_xyz',
      );

      expect(creds.sessionId, 'sess_real123');
      expect(creds.sessionSecret, 'sec_secret456');
      expect(manager.hasValidSession, isTrue);

      final headers = manager.generateSignedHeaders(
        method: 'POST',
        path: '/tickets',
        body: '{"test":1}',
      );
      expect(headers['X-Zarz-Session'], 'sess_real123');
      expect(headers['X-Zarz-Signature'], isNotEmpty);
      expect(headers['X-Zarz-Nonce'], hasLength(12));
    });

    test('resolveStreamDescriptor mints ticket and requests stream url', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/tickets') {
          return http.Response(
            jsonEncode({'ticket_id': 'tkt_mock789'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/v2/dl/qbz') {
          expect(request.headers['X-Zarz-Ticket'], 'tkt_mock789');
          return http.Response(
            jsonEncode({
              'direct_download_url': 'https://qobuz-cdn.example.com/stream/flac24',
              'quality': 'FLAC_24',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      SharedPreferences.setMockInitialValues({
        'zarz_session_id': 'sess_active',
        'zarz_session_secret': 'sec_active',
        'zarz_session_expires_at': DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch,
      });

      final manager = ZarzSessionManager(client: mockClient);
      await manager.initialize();
      expect(manager.hasValidSession, isTrue);

      final desc = await manager.resolveStreamDescriptor(
        provider: 'qbz',
        trackId: '1891090241',
      );
      expect(desc['direct_download_url'], 'https://qobuz-cdn.example.com/stream/flac24');
    });
  });
}
