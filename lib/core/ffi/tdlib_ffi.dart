import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Native TDLib C-ABI Signatures
typedef _TdCreateC = Pointer<Void> Function();
typedef _TdCreateDart = Pointer<Void> Function();

typedef _TdSendC = Void Function(Pointer<Void> client, Pointer<Utf8> request);
typedef _TdSendDart = void Function(Pointer<Void> client, Pointer<Utf8> request);

typedef _TdReceiveC = Pointer<Utf8> Function(Pointer<Void> client, Double timeout);
typedef _TdReceiveDart = Pointer<Utf8> Function(Pointer<Void> client, double timeout);

typedef _TdExecuteC = Pointer<Utf8> Function(Pointer<Void> client, Pointer<Utf8> request);
typedef _TdExecuteDart = Pointer<Utf8> Function(Pointer<Void> client, Pointer<Utf8> request);

typedef _TdDestroyC = Void Function(Pointer<Void> client);
typedef _TdDestroyDart = void Function(Pointer<Void> client);

class TdlibFfi {
  static TdlibFfi? _instance;
  final DynamicLibrary? _lib;

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
      _tdCreate = _lib.lookupFunction<_TdCreateC, _TdCreateDart>('td_json_client_create');
      _tdSend = _lib.lookupFunction<_TdSendC, _TdSendDart>('td_json_client_send');
      _tdReceive = _lib.lookupFunction<_TdReceiveC, _TdReceiveDart>('td_json_client_receive');
      _tdExecute = _lib.lookupFunction<_TdExecuteC, _TdExecuteDart>('td_json_client_execute');
      _tdDestroy = _lib.lookupFunction<_TdDestroyC, _TdDestroyDart>('td_json_client_destroy');
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

  static DynamicLibrary? _tryOpenLibrary(String? customPath) {
    if (customPath != null && File(customPath).existsSync()) {
      try {
        return DynamicLibrary.open(customPath);
      } catch (_) {
        return null;
      }
    }

    if (Platform.isAndroid) {
      try {
        return DynamicLibrary.open('libtdjson.so');
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
            return DynamicLibrary.open(path);
          } catch (_) {}
        }
      }
      try {
        return DynamicLibrary.open('libtdjson.so');
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Pointer<Void>? createClient() {
    if (!isAvailable || _tdCreate == null) return null;
    return _tdCreate();
  }

  void send(Pointer<Void>? client, Map<String, dynamic> request) {
    if (!isAvailable || _tdSend == null || client == null) return;
    final jsonStr = jsonEncode(request);
    final ptr = jsonStr.toNativeUtf8();
    _tdSend(client, ptr);
    malloc.free(ptr);
  }

  Map<String, dynamic>? receive(Pointer<Void>? client, {double timeout = 1.0}) {
    if (!isAvailable || _tdReceive == null || client == null) return null;
    final ptr = _tdReceive(client, timeout);
    if (ptr == nullptr || ptr.address == 0) return null;
    try {
      final jsonStr = ptr.toDartString();
      if (jsonStr.isEmpty) return null;
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? execute(Map<String, dynamic> request) {
    if (!isAvailable || _tdExecute == null) return null;
    final jsonStr = jsonEncode(request);
    final ptr = jsonStr.toNativeUtf8();
    final resPtr = _tdExecute(nullptr, ptr);
    malloc.free(ptr);
    if (resPtr == nullptr || resPtr.address == 0) return null;
    try {
      final resStr = resPtr.toDartString();
      return jsonDecode(resStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void destroyClient(Pointer<Void>? client) {
    if (!isAvailable || _tdDestroy == null || client == null) return;
    _tdDestroy(client);
  }
}
