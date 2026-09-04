import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/telegram_vault/telegram_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TelegramVaultService vault;
  late Directory tempDir;

  setUp(() async {
    vault = TelegramVaultService();
    tempDir = await Directory.systemTemp.createTemp('vault_test_');
  });

  tearDown(() async {
    vault.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TelegramVaultService Tests', () {
    test('Authentication flow transitions properly', () async {
      expect(vault.currentAuthState, VaultAuthState.unauthenticated);

      await vault.sendPhoneNumber('+1234567890');
      expect(vault.currentAuthState, VaultAuthState.waitCode);

      await vault.sendAuthCode('12345');
      expect(vault.currentAuthState, VaultAuthState.authenticated);

      await vault.logout();
      expect(vault.currentAuthState, VaultAuthState.unauthenticated);
    });

    test('2FA authentication flow transitions properly', () async {
      await vault.sendPhoneNumber('+1234567890');
      expect(vault.currentAuthState, VaultAuthState.waitCode);

      await vault.sendAuthCode('2FA');
      expect(vault.currentAuthState, VaultAuthState.waitPassword);

      await vault.sendPassword('supersecret2fa');
      expect(vault.currentAuthState, VaultAuthState.authenticated);
    });

    test('streamChunk returns bytes with matching length and offset slicing', () async {
      final chunk = await vault.streamChunk(
        fileId: 'mock_file_id',
        offset: 1024,
        length: 2048,
      );

      expect(chunk.length, 2048);
      expect(chunk[0], 1024 % 256);
      expect(chunk[1], 1025 % 256);
    });

    test('uploadTrackFiles uploads track to correct decade supergroup and saves to manifest', () async {
      final flac = File('${tempDir.path}/track.flac')..writeAsStringSync('flac');
      final opus = File('${tempDir.path}/track.opus')..writeAsStringSync('opus');

      final track = Track(
        id: 'coolie_1',
        title: 'Coolie Disco',
        artists: ['Anirudh'],
        album: 'Coolie',
        year: 2025,
        genre: 'Tamil',
        durationSeconds: 240,
        addedAt: DateTime.now(),
      );

      final uploaded = await vault.uploadTrackFiles(
        track: track,
        flacFile: flac,
        opusFile: opus,
      );

      expect(uploaded.telegramChatId, -1002000002020); // 2020s supergroup
      expect(uploaded.flacFileId?.startsWith('tg_flac_'), true);
      expect(uploaded.opusFileId?.startsWith('tg_opus_'), true);
      expect(uploaded.telegramMessageId, isNotNull);

      // Verify manifest was updated
      final manifest = await vault.downloadMasterManifest();
      expect(manifest.length, 1);
      expect(manifest.first.id, 'coolie_1');
    });
  });
}
