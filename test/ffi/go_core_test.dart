import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/ffi/acquisition_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Go Core C-Shared FFI Bridge Tests', () {
    late AcquisitionFfiBridge bridge;

    setUp(() {
      bridge = AcquisitionFfiBridge.instance(
        customLibPath: 'go_core/libcloudbeat_core.so',
      );
    });

    test('deriveDeezerKey generates 32-char hex Blowfish key', () {
      final keyHex = bridge.deriveDeezerKey('3135556');
      expect(keyHex.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(keyHex), true);
    });

    test('signZarz creates valid HMAC-SHA256 headers', () {
      final headers = bridge.signZarz(
        sessionId: 'sess_test_123456',
        sessionSecret: 'secret_key_base64_val',
        method: 'POST',
        path: '/v2/dl/dzr',
        body: '{"track_id":"12345"}',
        appVersion: 'deezer@1.3.4',
      );

      expect(headers.containsKey('X-Zarz-Session'), true);
      expect(headers['X-Zarz-Session'], 'sess_test_123456');
      expect(headers.containsKey('X-Zarz-Signature'), true);
      expect(headers['X-Zarz-Signature']!.isNotEmpty, true);
      expect(headers.containsKey('X-Zarz-Timestamp'), true);
      expect(headers.containsKey('X-Zarz-Nonce'), true);
      expect(headers['X-Zarz-Nonce']!.length, 12);
    });

    test('decryptDeezerChunk handles chunk without crash', () {
      final chunk = Uint8List(2048);
      for (int i = 0; i < 2048; i++) {
        chunk[i] = i % 256;
      }

      // Chunk index 0 is encrypted
      expect(() => bridge.decryptDeezerChunk(chunk, 0, '3135556'), returnsNormally);
      // Chunk index 1 is not encrypted (skipped)
      expect(() => bridge.decryptDeezerChunk(chunk, 1, '3135556'), returnsNormally);
    });

    test('checkBackendHealth returns active provider status', () async {
      final health = await bridge.checkBackendHealth();
      expect(health['deezer'], true);
      expect(health['qobuz'], true);
    });
  });
}
