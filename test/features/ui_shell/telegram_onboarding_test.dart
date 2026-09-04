import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/contracts/vault_contract.dart';
import 'package:cloudbeat/core/providers.dart';
import 'package:cloudbeat/features/ui_shell/telegram_onboarding_screen.dart';

class MockInteractiveVaultContract implements VaultContract {
  final _stateController = StreamController<VaultAuthState>.broadcast();
  VaultAuthState _state = VaultAuthState.unauthenticated;

  @override
  Stream<VaultAuthState> get authStateStream => _stateController.stream;

  @override
  VaultAuthState get currentAuthState => _state;

  void _setState(VaultAuthState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  @override
  Future<void> sendPhoneNumber(String phoneNumber) async {
    _setState(VaultAuthState.waitCode);
  }

  @override
  Future<void> sendAuthCode(String code) async {
    if (code == '2FA') {
      _setState(VaultAuthState.waitPassword);
    } else {
      _setState(VaultAuthState.authenticated);
    }
  }

  @override
  Future<void> sendPassword(String password) async {
    _setState(VaultAuthState.authenticated);
  }

  @override
  Future<void> logout() async {
    _setState(VaultAuthState.unauthenticated);
  }

  @override
  Future<Uint8List> streamChunk({required String fileId, required int offset, required int length}) async =>
      Uint8List(length);

  @override
  Future<Track> uploadTrackFiles({
    required Track track,
    required File flacFile,
    required File opusFile,
    void Function(double progress)? onProgress,
  }) async =>
      track;

  @override
  Future<List<Track>> downloadMasterManifest() async => const [];

  @override
  Future<void> publishMasterManifest(List<Track> catalog) async {}

  @override
  Future<int> getOrCreateDecadeSupergroup(int year) async => -100123456789;

  @override
  Future<int> getOrCreateGenreTopic(int supergroupId, String genreOrLanguage) async => 1;

  void dispose() {
    _stateController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockInteractiveVaultContract mockVault;

  setUp(() {
    mockVault = MockInteractiveVaultContract();
  });

  tearDown(() {
    mockVault.dispose();
  });

  testWidgets('TelegramOnboardingScreen displays Step 1 (phone input) initially', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultContractProvider.overrideWithValue(mockVault),
        ],
        child: const MaterialApp(
          home: TelegramOnboardingScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('CloudBeat Vault'), findsOneWidget);
    expect(find.text('STEP 1 OF 3'), findsOneWidget);
    expect(find.text('Connect Your Telegram Account'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Send Verification Code'), findsOneWidget);
  });

  testWidgets('Shows error if invalid phone is submitted', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultContractProvider.overrideWithValue(mockVault),
        ],
        child: const MaterialApp(
          home: TelegramOnboardingScreen(),
        ),
      ),
    );

    await tester.pump();

    // Tap button with empty phone
    await tester.tap(find.text('Send Verification Code'));
    await tester.pump();

    expect(find.text('Enter phone in international format (e.g. +14155552671)'), findsOneWidget);

    // Enter phone without leading '+'
    await tester.enterText(find.byType(TextField), '14155552671');
    await tester.tap(find.text('Send Verification Code'));
    await tester.pump();

    expect(find.text('Enter phone in international format (e.g. +14155552671)'), findsOneWidget);
  });

  testWidgets('Steps through full onboarding flow: Phone -> 2FA -> Success -> onCompleted', (tester) async {
    bool onCompletedCalled = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultContractProvider.overrideWithValue(mockVault),
        ],
        child: MaterialApp(
          home: TelegramOnboardingScreen(
            onCompleted: () => onCompletedCalled = true,
          ),
        ),
      ),
    );

    await tester.pump();

    // 1. Submit phone number
    await tester.enterText(find.byType(TextField), '+14155552671');
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    // 2. Verify Step 2 (Code)
    expect(find.text('STEP 2 OF 3'), findsOneWidget);
    expect(find.text('Enter Verification Code'), findsOneWidget);
    expect(find.text('Verify Code'), findsOneWidget);

    // 3. Submit code triggering 2FA
    await tester.enterText(find.byType(TextField), '2FA');
    await tester.tap(find.text('Verify Code'));
    await tester.pumpAndSettle();

    // 4. Verify Step 3 (2FA Cloud Password)
    expect(find.text('STEP 3 OF 3'), findsOneWidget);
    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(find.text('Unlock Vault'), findsOneWidget);

    // 5. Submit 2FA Password
    await tester.enterText(find.byType(TextField), 'my_cloud_password');
    await tester.tap(find.text('Unlock Vault'));
    await tester.pumpAndSettle();

    // 6. Verify Connected Screen & Callback
    expect(find.text('Telegram Vault Connected!'), findsOneWidget);
    expect(find.text('Enter CloudBeat Vault'), findsOneWidget);

    await tester.tap(find.text('Enter CloudBeat Vault'));
    await tester.pump();

    expect(onCompletedCalled, isTrue);
  });
}
