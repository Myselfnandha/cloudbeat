import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/contracts/audio_contract.dart';

class CompanionDevice {
  final String id;
  final String name;
  final String address;
  final int port;

  const CompanionDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
  });
}

class CompanionSyncService {
  final AudioEngineContract _audioEngine;
  final StreamController<CompanionDevice> _discoveredDevicesController =
      StreamController<CompanionDevice>.broadcast();
  HttpServer? _server;
  WebSocket? _activeClient;
  StreamSubscription? _playerStatusSub;

  CompanionSyncService({required AudioEngineContract audioEngine})
      : _audioEngine = audioEngine;

  Stream<CompanionDevice> get discoveredDevices =>
      _discoveredDevicesController.stream;

  bool get isConnected => _activeClient != null;

  /// Start companion sync server on local network port
  Future<int> startCompanionHost({int port = 8999}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleIncomingHttp);

    // Broadcast playback state changes to connected companion
    _playerStatusSub = _audioEngine.statusStream.listen((status) {
      if (_activeClient != null) {
        _activeClient!.add(jsonEncode({
          'type': 'status_update',
          'status': status.name,
          'currentTrack': _audioEngine.currentTrack?.toMap(),
          'positionMs': _audioEngine.currentPosition.inMilliseconds,
        }));
      }
    });

    return _server!.port;
  }

  void _handleIncomingHttp(HttpRequest request) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocketTransformer.upgrade(request).then((socket) {
        _activeClient = socket;
        socket.listen(
          _handleMessage,
          onDone: () => _activeClient = null,
          onError: (_) => _activeClient = null,
        );
      });
    } else {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('CloudBeat Companion Host Active')
        ..close();
    }
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final data = jsonDecode(rawMessage.toString()) as Map<String, dynamic>;
      final command = data['command'] as String?;

      switch (command) {
        case 'play':
          _audioEngine.resume();
          break;
        case 'pause':
          _audioEngine.pause();
          break;
        case 'next':
          _audioEngine.skipToNext();
          break;
        case 'prev':
          _audioEngine.skipToPrevious();
          break;
        case 'seek':
          final positionMs = data['positionMs'] as int?;
          if (positionMs != null) {
            _audioEngine.seek(Duration(milliseconds: positionMs));
          }
          break;
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    await _playerStatusSub?.cancel();
    await _activeClient?.close();
    await _server?.close(force: true);
    _server = null;
    _activeClient = null;
  }
}
