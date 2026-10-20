// FrameTransport over the wyrm-ffi C ABI (crates/wyrm-ffi/include/wyrm.h).
//
// Requests call the library directly (they return at once). Events are
// pulled by a helper isolate that blocks in `wyrm_next_event` and sends each
// CBOR frame to this isolate, so no native thread calls into Dart.
//
// Close order (the library's ownership rule): `wyrm_shutdown` → the poller
// sees WYRM_ERR_CLOSED and exits → `wyrm_free`.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:wyrm_client/wyrm_client.dart';

const int _ok = 0;
const int _event = 1;
const int _errArg = -1;
const int _errClosed = -2;
const int _errDuplicate = -4;

typedef _OpenN = Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>, Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _Open = Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>, Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _OpenMockN = Pointer<Void> Function(Uint32, Double, Pointer<Pointer<Utf8>>);
typedef _OpenMock = Pointer<Void> Function(int, double, Pointer<Pointer<Utf8>>);
typedef _HN = Int32 Function(Pointer<Void>);
typedef _H = int Function(Pointer<Void>);
typedef _FreeN = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _BufFreeN = Void Function(Pointer<Uint8>, Size);
typedef _BufFree = void Function(Pointer<Uint8>, int);
typedef _StrFreeN = Void Function(Pointer<Utf8>);
typedef _StrFree = void Function(Pointer<Utf8>);
typedef _NextN = Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _Next = int Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _KeyN = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>);
typedef _Key = int Function(Pointer<Void>, int, Pointer<Utf8>);
typedef _UnsubN = Int32 Function(Pointer<Void>, Uint64, Uint64);
typedef _Unsub = int Function(Pointer<Void>, int, int);
typedef _SetN = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>, Pointer<Uint8>, Size);
typedef _Set = int Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Uint8>, int);
typedef _InvokeN = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, Size);
typedef _Invoke = int Function(Pointer<Void>, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, int);

/// The functions of one loaded library.
class _Lib {
  final DynamicLibrary lib;
  _Lib(this.lib);

  late final open = lib.lookupFunction<_OpenN, _Open>('wyrm_open');
  late final shutdown = lib.lookupFunction<_HN, _H>('wyrm_shutdown');
  late final free = lib.lookupFunction<_FreeN, _Free>('wyrm_free');
  late final bufFree = lib.lookupFunction<_BufFreeN, _BufFree>('wyrm_buf_free');
  late final stringFree = lib.lookupFunction<_StrFreeN, _StrFree>('wyrm_string_free');
  late final next = lib.lookupFunction<_NextN, _Next>('wyrm_next_event');
  late final meta = lib.lookupFunction<_KeyN, _Key>('wyrm_meta');
  late final children = lib.lookupFunction<_KeyN, _Key>('wyrm_children');
  late final list = lib.lookupFunction<_KeyN, _Key>('wyrm_list');
  late final subscribe = lib.lookupFunction<_KeyN, _Key>('wyrm_subscribe');
  late final unsubscribe = lib.lookupFunction<_UnsubN, _Unsub>('wyrm_unsubscribe');
  late final set = lib.lookupFunction<_SetN, _Set>('wyrm_set');
  late final invoke = lib.lookupFunction<_InvokeN, _Invoke>('wyrm_invoke');

  _OpenMock get openTestMock => lib.lookupFunction<_OpenMockN, _OpenMock>('wyrm_open_test_mock');

  /// `wyrm_open*` result: the handle address, or throws with the message.
  int takeHandle(Pointer<Void> h, Pointer<Pointer<Utf8>> err) {
    if (h != nullptr) return h.address;
    final e = err.value;
    final msg = e == nullptr ? 'open failed' : e.toDartString();
    if (e != nullptr) stringFree(e);
    throw WyrmException.of(Status.disconnected, msg);
  }
}

/// Opens WYRM sessions through the native library.
class WyrmFfi {
  /// Library path: [path], else `WYRM_FFI_LIB`, else the platform name
  /// (`libwyrm_ffi.dylib`, `libwyrm_ffi.so`, `wyrm_ffi.dll`) on the loader path.
  static String libraryPath([String? path]) =>
      path ??
      Platform.environment['WYRM_FFI_LIB'] ??
      (Platform.isMacOS || Platform.isIOS
          ? 'libwyrm_ffi.dylib'
          : Platform.isWindows
              ? 'wyrm_ffi.dll'
              : 'libwyrm_ffi.so');

  /// Connect a Zenoh client session to [endpoint] (`tcp/127.0.0.1:7447`).
  /// [seed]: a 32-byte Ed25519 key the broker trusts, for `ptok`s on [site].
  /// The blocking connect runs in a helper isolate.
  static Future<FrameClient> open(String endpoint,
      {Uint8List? seed, String? site, String? library}) async {
    if (seed != null && (seed.length != 32 || site == null)) {
      throw ArgumentError('seed must be 32 bytes and needs a site');
    }
    final path = libraryPath(library);
    final addr = await Isolate.run(() {
      final l = _Lib(DynamicLibrary.open(path));
      return using((arena) {
        final err = arena<Pointer<Utf8>>()..value = nullptr;
        Pointer<Uint8> s = nullptr;
        if (seed != null) {
          s = arena<Uint8>(32)..asTypedList(32).setAll(0, seed);
        }
        final h = l.open(endpoint.toNativeUtf8(allocator: arena), s,
            site == null ? nullptr : site.toNativeUtf8(allocator: arena), err);
        return l.takeHandle(h, err);
      });
    });
    return FrameClient(await FfiTransport._start(path, addr));
  }

  /// Test only: the in-process mock (library built with the cargo feature
  /// `test-harness`): site `test`, link `mock`.
  static Future<FrameClient> openTestMock({int points = 6, double rateHz = 20, String? library}) async {
    final path = libraryPath(library);
    final addr = await Isolate.run(() {
      final l = _Lib(DynamicLibrary.open(path));
      return using((arena) {
        final err = arena<Pointer<Utf8>>()..value = nullptr;
        return l.takeHandle(l.openTestMock(points, rateHz, err), err);
      });
    });
    return FrameClient(await FfiTransport._start(path, addr));
  }
}

/// [FrameTransport] over one native handle.
class FfiTransport implements FrameTransport {
  final _Lib _l;
  final Pointer<Void> _h;
  final _in = StreamController<Value>.broadcast(sync: false);
  final ReceivePort _port;
  final Completer<void> _pollerDone = Completer<void>();
  bool _closing = false;

  final String _path;

  FfiTransport._(this._path, this._l, this._h, this._port) {
    _port.listen((m) {
      if (m is TransferableTypedData) {
        try {
          _in.add(decodeFrame(m.materialize().asUint8List()));
        } on CborError {
          // a malformed frame is dropped
        }
      } else {
        // poller finished (shutdown or error)
        _port.close();
        if (!_pollerDone.isCompleted) _pollerDone.complete();
        _in.close();
      }
    });
  }

  static Future<FfiTransport> _start(String path, int addr) async {
    final port = ReceivePort();
    final t = FfiTransport._(path, _Lib(DynamicLibrary.open(path)), Pointer<Void>.fromAddress(addr), port);
    await Isolate.spawn(_poll, (path, addr, port.sendPort));
    return t;
  }

  /// Helper isolate: block in `wyrm_next_event` and forward each frame.
  static void _poll((String, int, SendPort) args) {
    final (path, addr, out) = args;
    final l = _Lib(DynamicLibrary.open(path));
    final h = Pointer<Void>.fromAddress(addr);
    final p = calloc<Pointer<Uint8>>();
    final n = calloc<Size>();
    try {
      while (true) {
        final r = l.next(h, 250, p, n);
        if (r == _event) {
          final len = n.value;
          final copy = Uint8List.fromList(p.value.asTypedList(len));
          l.bufFree(p.value, len);
          out.send(TransferableTypedData.fromList([copy]));
        } else if (r != _ok) {
          break; // closed or error
        }
      }
    } finally {
      calloc.free(p);
      calloc.free(n);
      out.send(null);
    }
  }

  @override
  Stream<Value> get incoming => _in.stream;

  @override
  void send(Map<String, Value> frame) {
    final id = (frame['id'] as VInt).v;
    final op = (frame['op'] as VStr).v;
    final key = switch (frame['key']) { VStr(:final v) => v, _ => '' };
    final rc = using((arena) {
      Pointer<Utf8> s(String x) => x.toNativeUtf8(allocator: arena);
      Pointer<Uint8> buf(Uint8List b) => arena<Uint8>(b.isEmpty ? 1 : b.length)..asTypedList(b.length).setAll(0, b);
      switch (op) {
        case 'meta':
          return _l.meta(_h, id, s(key));
        case 'children':
          return _l.children(_h, id, s(key));
        case 'list':
          return _l.list(_h, id, s(key));
        case 'subscribe':
          return _l.subscribe(_h, id, s(key));
        case 'unsubscribe':
          return _l.unsubscribe(_h, id, (frame['sub'] as VInt).v);
        case 'set':
          final v = (frame['value'] ?? const VNull()).toCbor();
          return _l.set(_h, id, s(key), buf(v), v.length);
        case 'invoke':
          final a = (frame['args'] ?? const VMap({})).toCbor();
          final action = switch (frame['action']) { VStr(:final v) => v, _ => '' };
          return _l.invoke(_h, id, s(key), s(action), buf(a), a.length);
      }
      return _errArg;
    });
    if (rc != _ok) {
      // Report as the gateway would: an error frame for this id.
      final (status, msg) = switch (rc) {
        _errClosed => (Status.disconnected, 'closed'),
        _errDuplicate => (Status.invalidParameter, 'id of an open stream'),
        _errArg => (Status.invalidParameter, 'bad argument'),
        _ => (Status.internalError, 'native error $rc'),
      };
      scheduleMicrotask(() => _in.add(VMap({
            'id': VInt(id),
            'ok': const VBool(false),
            'error': VMap({'status': VInt(status.code), 'message': VStr(msg)}),
          })));
    }
  }

  @override
  Future<void> close() async {
    if (_closing) return _pollerDone.future;
    _closing = true;
    // wyrm_shutdown may block while the session closes: not on this isolate.
    final path = _path;
    final addr = _h.address;
    await Isolate.run(() => _Lib(DynamicLibrary.open(path)).shutdown(Pointer<Void>.fromAddress(addr)));
    var done = true;
    await _pollerDone.future.timeout(const Duration(seconds: 10), onTimeout: () => done = false);
    // Free only once the poller is gone; otherwise leak rather than race.
    if (done) _l.free(_h);
  }
}
