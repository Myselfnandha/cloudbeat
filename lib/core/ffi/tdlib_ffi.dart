import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// Type definitions for TDLib JSON interface
typedef TdJsonClientCreateNative = ffi.Pointer<ffi.Void> Function();
typedef TdJsonClientCreate = ffi.Pointer<ffi.Void> Function();

typedef TdJsonClientSendNative = ffi.Void Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<Utf8> request);
typedef TdJsonClientSend = void Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<Utf8> request);

typedef TdJsonClientReceiveNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void> client, ffi.Double timeout);
typedef TdJsonClientReceive = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void> client, double timeout);

typedef TdJsonClientExecuteNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<Utf8> request);
typedef TdJsonClientExecute = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void> client, ffi.Pointer<Utf8> request);

typedef TdJsonClientDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void> client);
typedef TdJsonClientDestroy = void Function(ffi.Pointer<ffi.Void> client);

class TdlibFfi {
  late final ffi.DynamicLibrary _lib;
  
  late final TdJsonClientCreate _create;
  late final TdJsonClientSend _send;
  late final TdJsonClientReceive _receive;
  late final TdJsonClientExecute _execute;
  late final TdJsonClientDestroy _destroy;

  bool _initialized = false;

  void initialize() {
    if (_initialized) return;

    if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libtdjson.so');
    } else if (Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('libtdjson.so');
    } else if (Platform.isWindows) {
      _lib = ffi.DynamicLibrary.open('tdjson.dll');
    } else if (Platform.isMacOS || Platform.isIOS) {
      _lib = ffi.DynamicLibrary.process();
    } else {
      throw UnsupportedError('Unsupported platform for TDLib');
    }

    _create = _lib.lookupFunction<TdJsonClientCreateNative, TdJsonClientCreate>('td_json_client_create');
    _send = _lib.lookupFunction<TdJsonClientSendNative, TdJsonClientSend>('td_json_client_send');
    _receive = _lib.lookupFunction<TdJsonClientReceiveNative, TdJsonClientReceive>('td_json_client_receive');
    _execute = _lib.lookupFunction<TdJsonClientExecuteNative, TdJsonClientExecute>('td_json_client_execute');
    _destroy = _lib.lookupFunction<TdJsonClientDestroyNative, TdJsonClientDestroy>('td_json_client_destroy');

    _initialized = true;
  }

  ffi.Pointer<ffi.Void> clientCreate() {
    if (!_initialized) initialize();
    return _create();
  }

  void clientSend(ffi.Pointer<ffi.Void> client, String request) {
    if (!_initialized) initialize();
    final nativeString = request.toNativeUtf8();
    _send(client, nativeString);
    malloc.free(nativeString);
  }

  String? clientReceive(ffi.Pointer<ffi.Void> client, double timeout) {
    if (!_initialized) initialize();
    final result = _receive(client, timeout);
    if (result == ffi.nullptr) return null;
    return result.toDartString();
  }

  String? clientExecute(ffi.Pointer<ffi.Void> client, String request) {
    if (!_initialized) initialize();
    final nativeString = request.toNativeUtf8();
    final result = _execute(client, nativeString);
    malloc.free(nativeString);
    
    if (result == ffi.nullptr) return null;
    return result.toDartString();
  }

  void clientDestroy(ffi.Pointer<ffi.Void> client) {
    if (!_initialized) initialize();
    _destroy(client);
  }
}

final tdlib = TdlibFfi();
