import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/ffi/tdlib_ffi.dart';
import 'package:cloudbeat/features/telegram_vault/native_telegram_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TdlibFfi Native Interface Tests', () {
    test('TdlibFfi instance initializes safely on platform', () {
      final ffi = TdlibFfi.instance();
      expect(ffi, isNotNull);
      // If native TDLib library is not present in test runner, isAvailable is false
      // and calling createClient() safely returns null without crashing.
      if (!ffi.isAvailable) {
        expect(ffi.createClient(), isNull);
        expect(ffi.execute({'@type': 'getTextEntities'}), isNull);
      }
    });
  });

  group('NativeTelegramVaultService Tests', () {
    late NativeTelegramVaultService vault;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('native_vault_test_');
      vault = NativeTelegramVaultService(databaseDir: tempDir.path, preAuthenticated: false);
    });

    tearDown(() async {
      vault.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Initial state is unauthenticated when preAuthenticated is false', () {
      expect(vault.currentAuthState, VaultAuthState.unauthenticated);
    });

    test('Initial state is authenticated when preAuthenticated is true (default)', () {
      final defaultVault = NativeTelegramVaultService();
      expect(defaultVault.currentAuthState, VaultAuthState.authenticated);
      defaultVault.dispose();
    });

    test('Standard phone and OTP authentication flow', () async {
      final states = <VaultAuthState>[];
      final subscription = vault.authStateStream.listen(states.add);

      await vault.sendPhoneNumber('+14155552671');
      expect(vault.currentAuthState, VaultAuthState.waitCode);

      await vault.sendAuthCode('54321');
      expect(vault.currentAuthState, VaultAuthState.authenticated);

      await vault.logout();
      expect(vault.currentAuthState, VaultAuthState.unauthenticated);

      await subscription.cancel();
      expect(states, contains(VaultAuthState.waitCode));
      expect(states, contains(VaultAuthState.authenticated));
      expect(states, contains(VaultAuthState.unauthenticated));
    });

    test('2FA authentication flow transitions to waitPassword and authenticates', () async {
      await vault.sendPhoneNumber('+14155552671');
      expect(vault.currentAuthState, VaultAuthState.waitCode);

      await vault.sendAuthCode('2FA');
      expect(vault.currentAuthState, VaultAuthState.waitPassword);

      await vault.sendPassword('cloudbeat_super_pass');
      expect(vault.currentAuthState, VaultAuthState.authenticated);
    });

    test('streamChunk produces sliced byte buffers', () async {
      final chunk = await vault.streamChunk(
        fileId: 'tg_doc_999',
        offset: 512,
        length: 1024,
      );

      expect(chunk.length, 1024);
      expect(chunk[0], 512 % 256);
      expect(chunk[1], 513 % 256);
    });

    test('uploadTrackFiles executes Pure FLAC storage policy and updates manifest', () async {
      final flacFile = File('${tempDir.path}/pure_lossless.flac')..writeAsStringSync('FLAC_DATA');
      final opusFile = File('${tempDir.path}/ignored.opus')..writeAsStringSync('OPUS_DATA');

      final track = Track(
        id: 'audiophile_99',
        title: 'Lossless Symphony',
        artists: ['Maestro'],
        album: 'Acoustic Dreams',
        year: 2024,
        genre: 'Classical',
        durationSeconds: 360,
        addedAt: DateTime.now(),
      );

      double reportedProgress = 0.0;
      final uploaded = await vault.uploadTrackFiles(
        track: track,
        flacFile: flacFile,
        opusFile: opusFile,
        onProgress: (p) => reportedProgress = p,
      );

      expect(reportedProgress, 1.0);
      expect(uploaded.quality, AudioQuality.flac16Bit);
      expect(uploaded.flacFileId, isNotNull);
      expect(uploaded.telegramChatId, isNotNull);
      expect(uploaded.telegramMessageId, 1001);

      // Verify manifest download reflects newly uploaded track
      final manifest = await vault.downloadMasterManifest();
      expect(manifest.length, 1);
      expect(manifest.first.id, 'audiophile_99');
      expect(manifest.first.title, 'Lossless Symphony');
    });

    test('Decade supergroup and genre topics are correctly generated', () async {
      final supergroup2020s = await vault.getOrCreateDecadeSupergroup(2025);
      final supergroup1990s = await vault.getOrCreateDecadeSupergroup(1998);

      expect(supergroup2020s, isNot(equals(supergroup1990s)));

      final topic1 = await vault.getOrCreateGenreTopic(supergroup2020s, 'Electronic');
      final topic2 = await vault.getOrCreateGenreTopic(supergroup2020s, 'Electronic');
      final topic3 = await vault.getOrCreateGenreTopic(supergroup2020s, 'Rock');

      // Idempotent topic lookup
      expect(topic1, equals(topic2));
      expect(topic1, isNot(equals(topic3)));
    });
  });
}
