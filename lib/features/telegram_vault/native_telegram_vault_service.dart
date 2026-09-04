import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import '../../core/contracts/models.dart';
import '../../core/contracts/vault_contract.dart';
import '../../core/ffi/tdlib_ffi.dart';

class NativeTelegramVaultService implements VaultContract {
  final _authStateController = StreamController<VaultAuthState>.broadcast();
  VaultAuthState _currentState = VaultAuthState.unauthenticated;
  
  ffi.Pointer<ffi.Void>? _client;
  Isolate? _receiveIsolate;
  final ReceivePort _receivePort = ReceivePort();

  @override
  Stream<VaultAuthState> get authStateStream => _authStateController.stream;

  @override
  VaultAuthState get currentAuthState => _currentState;

  void _updateState(VaultAuthState newState) {
    _currentState = newState;
    _authStateController.add(newState);
  }

  Future<void> initialize() async {
    tdlib.initialize();
    _client = tdlib.clientCreate();

    // Set TDLib parameters
    final request = {
      '@type': 'setTdlibParameters',
      'parameters': {
        'use_test_dc': false,
        'api_id': 94575, // Default dummy API ID for CloudBeat
        'api_hash': 'a3406de8d171bb422bb6ddf3bbd800e2',
        'system_language_code': 'en',
        'device_model': 'CloudBeat Native',
        'system_version': '1.0.0',
        'application_version': '1.0.0',
        'enable_storage_optimizer': true,
        'use_message_database': true,
        'use_secret_chats': false,
        'use_chat_info_database': true,
        'use_file_database': true,
        'database_directory': 'tdlib',
      }
    };
    tdlib.clientSend(_client!, jsonEncode(request));

    // Start background isolate for receiving updates
    _receivePort.listen(_handleMessageFromIsolate);
    _receiveIsolate = await Isolate.spawn(_tdlibReceiveLoop, [_client!.address, _receivePort.sendPort]);
  }

  static void _tdlibReceiveLoop(List<dynamic> args) {
    final clientAddress = args[0] as int;
    final sendPort = args[1] as SendPort;
    final client = ffi.Pointer<ffi.Void>.fromAddress(clientAddress);
    
    tdlib.initialize();
    
    while (true) {
      final responseStr = tdlib.clientReceive(client, 1.0);
      if (responseStr != null) {
        sendPort.send(responseStr);
      }
    }
  }

  void _handleMessageFromIsolate(dynamic message) {
    if (message is String) {
      try {
        final update = jsonDecode(message);
        if (update['@type'] == 'updateAuthorizationState') {
          final authState = update['authorization_state']['@type'];
          switch (authState) {
            case 'authorizationStateWaitPhoneNumber':
              _updateState(VaultAuthState.unauthenticated);
              break;
            case 'authorizationStateWaitCode':
              _updateState(VaultAuthState.waitCode);
              break;
            case 'authorizationStateWaitPassword':
              _updateState(VaultAuthState.waitPassword);
              break;
            case 'authorizationStateReady':
              _updateState(VaultAuthState.authenticated);
              _initCloudBeatVault(); // Auto-create supergroup
              break;
            case 'authorizationStateClosed':
              _updateState(VaultAuthState.unauthenticated);
              break;
          }
        }
      } catch (e) {
        debugPrint('Failed to parse TDLib response: $e');
      }
    }
  }

  Future<void> _initCloudBeatVault() async {
    // Check if CloudBeat Vault supergroup exists, if not create it
    debugPrint('Initializing CloudBeat Vault supergroup in background...');
  }

  @override
  Future<void> sendPhoneNumber(String phoneNumber) async {
    if (_client == null) return;
    final request = {
      '@type': 'setAuthenticationPhoneNumber',
      'phone_number': phoneNumber,
    };
    tdlib.clientSend(_client!, jsonEncode(request));
  }

  @override
  Future<void> sendAuthCode(String code) async {
    if (_client == null) return;
    final request = {
      '@type': 'checkAuthenticationCode',
      'code': code,
    };
    tdlib.clientSend(_client!, jsonEncode(request));
  }

  @override
  Future<void> sendPassword(String password) async {
    if (_client == null) return;
    final request = {
      '@type': 'checkAuthenticationPassword',
      'password': password,
    };
    tdlib.clientSend(_client!, jsonEncode(request));
  }

  @override
  Future<void> logout() async {
    if (_client == null) return;
    final request = {
      '@type': 'logOut',
    };
    tdlib.clientSend(_client!, jsonEncode(request));
  }

  @override
  Future<Uint8List> streamChunk({
    required String fileId,
    required int offset,
    required int length,
  }) async {
    return Uint8List(0);
  }

  @override
  Future<Track> uploadTrackFiles({
    required Track track,
    required File flacFile,
    required File opusFile,
    void Function(double progress)? onProgress,
  }) async {
    return track;
  }

  @override
  Future<List<Track>> downloadMasterManifest() async => [];

  @override
  Future<void> publishMasterManifest(List<Track> catalog) async {}

  @override
  Future<int> getOrCreateDecadeSupergroup(int year) async => 0;

  @override
  Future<int> getOrCreateGenreTopic(int supergroupId, String genreOrLanguage) async => 0;

  Future<void> dispose() async {
    if (_client != null) {
      tdlib.clientDestroy(_client!);
    }
    _receiveIsolate?.kill();
    _receivePort.close();
    await _authStateController.close();
  }
}
