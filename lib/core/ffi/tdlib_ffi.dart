import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// Native TDLib C-ABI Signatures
typedef _TdCreateC = ffi.Pointer<ffi.Void> Function();
typedef _TdCreateDart = ffi.Pointer<ffi.Void> Function();

typedef _TdSendC = ffi.Void Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<Utf8> request);
typedef _TdSendDart = void Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<Utf8> request);

typedef _TdReceiveC = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void> client, ffi.Double timeout);
typedef _TdReceiveDart = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void> client, double timeout);

typedef _TdExecuteC = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<Utf8> request);
typedef _TdExecuteDart = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<Utf8> request);

typedef _TdDestroyC = ffi.Void Function(ffi.Pointer<ffi.Void> client);
typedef _TdDestroyDart = void Function(ffi.Pointer<ffi.Void> client);

class TdlibFfi {
  static TdlibFfi? _instance;
  final ffi.DynamicLibrary? _lib;

  late final _TdCreateDart? _tdCreate;
  late final _TdSendDart? _tdSend;
  late final _TdReceiveDart? _tdReceive;
  late final _TdExecuteDart? _tdExecute;
  late final _TdDestroyDart? _tdDestroy;

  final bool isAvailable;

  TdlibFfi._({String? customPath})
      : _lib = _tryOpenLibrary(customPath),
        isAvailable = _tryOpenLibrary(customPath) != null {
    if (_lib != null) {
      try {
        _tdCreate = _lib.lookupFunction<_TdCreateC, _TdCreateDart>('td_json_client_create');
        _tdSend = _lib.lookupFunction<_TdSendC, _TdSendDart>('td_json_client_send');
        _tdReceive = _lib.lookupFunction<_TdReceiveC, _TdReceiveDart>('td_json_client_receive');
        _tdExecute = _lib.lookupFunction<_TdExecuteC, _TdExecuteDart>('td_json_client_execute');
        _tdDestroy = _lib.lookupFunction<_TdDestroyC, _TdDestroyDart>('td_json_client_destroy');
      } catch (_) {
        _tdCreate = null;
        _tdSend = null;
        _tdReceive = null;
        _tdExecute = null;
        _tdDestroy = null;
      }
    } else {
      _tdCreate = null;
      _tdSend = null;
      _tdReceive = null;
      _tdExecute = null;
      _tdDestroy = null;
    }
  }

  static TdlibFfi instance({String? customPath}) {
    return _instance ??= TdlibFfi._(customPath: customPath);
  }

  void initialize() {
    // Kept for backward compatibility
  }

  static ffi.DynamicLibrary? _tryOpenLibrary(String? customPath) {
    if (customPath != null && File(customPath).existsSync()) {
      try {
        return ffi.DynamicLibrary.open(customPath);
      } catch (_) {
        return null;
      }
    }

    if (Platform.isAndroid) {
      try {
        return ffi.DynamicLibrary.open('libtdjson.so');
      } catch (_) {
        return null;
      }
    } else if (Platform.isLinux) {
      final candidates = [
        'libtdjson.so',
        '/usr/lib/libtdjson.so',
        '/usr/local/lib/libtdjson.so',
        '${Directory.current.path}/libtdjson.so',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          try {
            return ffi.DynamicLibrary.open(path);
          } catch (_) {}
        }
      }
      try {
        return ffi.DynamicLibrary.open('libtdjson.so');
      } catch (_) {
        return null;
      }
    } else if (Platform.isWindows) {
      try {
        return ffi.DynamicLibrary.open('tdjson.dll');
      } catch (_) {
        return null;
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      try {
        return ffi.DynamicLibrary.process();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  ffi.Pointer<ffi.Void>? createClient() {
    if (!isAvailable || _tdCreate == null) return null;
    return _tdCreate();
  }

  ffi.Pointer<ffi.Void> clientCreate() {
    final c = createClient();
    return c ?? ffi.nullptr;
  }

  void send(ffi.Pointer<ffi.Void>? client, Map<String, dynamic> request) {
    if (!isAvailable || _tdSend == null || client == null || client == ffi.nullptr) return;
    final jsonStr = jsonEncode(request);
    final ptr = jsonStr.toNativeUtf8();
    _tdSend(client, ptr);
    malloc.free(ptr);
  }

  void clientSend(ffi.Pointer<ffi.Void> client, String request) {
    if (!isAvailable || _tdSend == null || client == ffi.nullptr) return;
    final ptr = request.toNativeUtf8();
    _tdSend(client, ptr);
    malloc.free(ptr);
  }

  Map<String, dynamic>? receive(ffi.Pointer<ffi.Void>? client, {double timeout = 1.0}) {
    if (!isAvailable || _tdReceive == null || client == null || client == ffi.nullptr) return null;
    final ptr = _tdReceive(client, timeout);
    if (ptr == ffi.nullptr || ptr.address == 0) return null;
    try {
      final jsonStr = ptr.toDartString();
      if (jsonStr.isEmpty) return null;
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String? clientReceive(ffi.Pointer<ffi.Void> client, double timeout) {
    if (!isAvailable || _tdReceive == null || client == ffi.nullptr) return null;
    final ptr = _tdReceive(client, timeout);
    if (ptr == ffi.nullptr || ptr.address == 0) return null;
    try {
      return ptr.toDartString();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? execute(Map<String, dynamic> request) {
    if (!isAvailable || _tdExecute == null) return null;
    final jsonStr = jsonEncode(request);
    final ptr = jsonStr.toNativeUtf8();
    final resPtr = _tdExecute(ffi.nullptr, ptr);
    malloc.free(ptr);
    if (resPtr == ffi.nullptr || resPtr.address == 0) return null;
    try {
      final resStr = resPtr.toDartString();
      return jsonDecode(resStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String? clientExecute(ffi.Pointer<ffi.Void> client, String request) {
    if (!isAvailable || _tdExecute == null) return null;
    final ptr = request.toNativeUtf8();
    final resPtr = _tdExecute(client, ptr);
    malloc.free(ptr);
    if (resPtr == ffi.nullptr || resPtr.address == 0) return null;
    try {
      return resPtr.toDartString();
    } catch (_) {
      return null;
    }
  }

  void destroyClient(ffi.Pointer<ffi.Void>? client) {
    if (!isAvailable || _tdDestroy == null || client == null || client == ffi.nullptr) return;
    _tdDestroy(client);
  }

  void clientDestroy(ffi.Pointer<ffi.Void> client) {
    destroyClient(client);
  }
}

final tdlib = TdlibFfi.instance();
