import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _FetchLyricsC = Pointer<Utf8> Function(
  Pointer<Utf8> title,
  Pointer<Utf8> artist,
  Uint64 durationMs,
);
typedef _FetchLyricsDart = Pointer<Utf8> Function(
  Pointer<Utf8> title,
  Pointer<Utf8> artist,
  int durationMs,
);

typedef _FreeLyricsStringC = Void Function(Pointer<Utf8> str);
typedef _FreeLyricsStringDart = void Function(Pointer<Utf8> str);

class NeteaseFfi {
  static NeteaseFfi? _instance;
  DynamicLibrary? _lib;

  _FetchLyricsDart? _fetchLyrics;
  _FreeLyricsStringDart? _freeString;

  bool get isAvailable => _lib != null && _fetchLyrics != null && _freeString != null;

  NeteaseFfi._(String? customLibPath) {
    try {
      _lib = _openLibrary(customLibPath);
      _fetchLyrics = _lib!.lookupFunction<_FetchLyricsC, _FetchLyricsDart>('CloudBeat_FetchNeteaseLyrics');
      _freeString = _lib!.lookupFunction<_FreeLyricsStringC, _FreeLyricsStringDart>('CloudBeat_FreeLyricsString');
    } catch (_) {
      _lib = null;
      _fetchLyrics = null;
      _freeString = null;
    }
  }

  static NeteaseFfi instance({String? customLibPath}) {
    return _instance ??= NeteaseFfi._(customLibPath);
  }

  static DynamicLibrary? _openLibrary(String? customPath) {
    if (customPath != null && File(customPath).existsSync()) {
      return DynamicLibrary.open(customPath);
    }

    final candidates = [
      'libcloudbeat_lyrics.so',
      'rust/target/release/libcloudbeat_lyrics.so',
      '${Directory.current.path}/rust/target/release/libcloudbeat_lyrics.so',
      '/home/nandha/Desktop/songstore/cloudbeat/rust/target/release/libcloudbeat_lyrics.so',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
    }
    return null;
  }

  String? fetchNeteaseLyricsJson(String title, String artist, {int durationMs = 0}) {
    if (!isAvailable) return null;

    final titlePtr = title.toNativeUtf8();
    final artistPtr = artist.toNativeUtf8();
    try {
      final resPtr = _fetchLyrics!(titlePtr, artistPtr, durationMs);
      if (resPtr == nullptr) return null;

      final jsonStr = resPtr.toDartString();
      _freeString!(resPtr);
      return jsonStr;
    } catch (_) {
      return null;
    } finally {
      malloc.free(titlePtr);
      malloc.free(artistPtr);
    }
  }
}
