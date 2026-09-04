import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/ffi/tdlib_ffi.dart';
import 'package:cloudbeat/features/telegram_vault/native_telegram_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TdlibFfi Native Interface Tests', () {
    test('TdlibFfi instance initializes safely', () {
      expect(tdlib, isNotNull);
    });
  });

  group('NativeTelegramVaultService Tests', () {
    test('Can instantiate vault', () {
      final vault = NativeTelegramVaultService();
      expect(vault, isNotNull);
    });
  });
}
