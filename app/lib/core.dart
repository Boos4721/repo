import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _NewNative = Pointer<Void> Function();
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FeedNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  IntPtr,
);
typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _RequestNative = Pointer<Utf8> Function(Uint8);
typedef _DemoNative = Pointer<Utf8> Function();

class AntCore {
  late final DynamicLibrary _lib;
  late final Pointer<Void> _engine;
  late final void Function(Pointer<Void>) _free, _reset;
  late final Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int) _feed;
  late final void Function(Pointer<Utf8>) _stringFree;
  late final Pointer<Utf8> Function(int) _request;
  late final Pointer<Utf8> Function() _demo;
  bool _disposed = false;
  AntCore() {
    _lib = Platform.isIOS
        ? DynamicLibrary.process()
        : DynamicLibrary.open(
            Platform.isAndroid
                ? 'libant_core.so'
                : Platform.environment['ANT_CORE_LIBRARY'] ??
                      '../rust/target/debug/libant_core.so',
          );
    _engine = _lib.lookupFunction<_NewNative, Pointer<Void> Function()>(
      'ant_engine_new',
    )();
    _free = _lib.lookupFunction<_FreeNative, void Function(Pointer<Void>)>(
      'ant_engine_free',
    );
    _reset = _lib.lookupFunction<_FreeNative, void Function(Pointer<Void>)>(
      'ant_engine_reset',
    );
    _feed = _lib
        .lookupFunction<
          _FeedNative,
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int)
        >('ant_engine_feed');
    _stringFree = _lib
        .lookupFunction<_StringFreeNative, void Function(Pointer<Utf8>)>(
          'ant_string_free',
        );
    _request = _lib.lookupFunction<_RequestNative, Pointer<Utf8> Function(int)>(
      'ant_read_request',
    );
    _demo = _lib.lookupFunction<_DemoNative, Pointer<Utf8> Function()>(
      'ant_demo_frame',
    );
  }
  dynamic _take(Pointer<Utf8> p) {
    try {
      return jsonDecode(p.toDartString());
    } finally {
      _stringFree(p);
    }
  }

  List<int> request() => List<int>.from(_take(_request(0xa1)) as List);
  List<int> demo() => List<int>.from(_take(_demo()) as List);
  Map<String, dynamic> feed(List<int> bytes) {
    if (_disposed) throw StateError('Rust session disposed');
    final p = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      p.asTypedList(bytes.length).setAll(0, bytes);
      return Map<String, dynamic>.from(
        _take(_feed(_engine, p, bytes.length)) as Map,
      );
    } finally {
      calloc.free(p);
    }
  }

  void reset() {
    if (!_disposed) _reset(_engine);
  }

  void dispose() {
    if (!_disposed) {
      _free(_engine);
      _disposed = true;
    }
  }
}
