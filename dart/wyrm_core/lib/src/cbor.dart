// Canonical CBOR (RFC 8949 §4.2.1, length-first key order as in RFC 7049):
// shortest heads, integer map keys ascending, text keys by encoded length
// then bytewise, floats in the shortest lossless form (f16 → f32 → f64).
// The decoder accepts any well-formed CBOR, including indefinite lengths
// and tags (tags are skipped).

import 'dart:convert';
import 'dart:typed_data';

import 'value.dart';

/// A malformed or unsupported CBOR item.
class CborError implements Exception {
  final String message;
  CborError(this.message);
  @override
  String toString() => 'CborError: $message';
}

const int _two32 = 0x100000000;

/// Low-level canonical CBOR encoder.
class CborWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void _head(int major, int n) {
    if (n < 0) throw ArgumentError('negative CBOR argument $n');
    final m = major << 5;
    if (n < 24) {
      _b.addByte(m | n);
    } else if (n < 0x100) {
      _b.add([m | 24, n]);
    } else if (n < 0x10000) {
      _b.add([m | 25, n >> 8, n & 0xff]);
    } else if (n < _two32) {
      _b.add([m | 26, (n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]);
    } else {
      final hi = n ~/ _two32;
      final lo = n % _two32;
      _b.add([
        m | 27,
        (hi >> 24) & 0xff, (hi >> 16) & 0xff, (hi >> 8) & 0xff, hi & 0xff, //
        (lo >> 24) & 0xff, (lo >> 16) & 0xff, (lo >> 8) & 0xff, lo & 0xff,
      ]);
    }
  }

  /// Unsigned integer (major 0).
  void uint(int n) => _head(0, n);

  /// Signed integer: major 0 for `n >= 0`, major 1 otherwise.
  void integer(int n) => n >= 0 ? _head(0, n) : _head(1, -1 - n);

  void text(String s) {
    final u = utf8.encode(s);
    _head(3, u.length);
    _b.add(u);
  }

  void bytes(List<int> b) {
    _head(2, b.length);
    _b.add(b);
  }

  void arrayHeader(int n) => _head(4, n);
  void mapHeader(int n) => _head(5, n);
  void boolean(bool v) => _b.addByte(v ? 0xf5 : 0xf4);
  void nil() => _b.addByte(0xf6);

  /// Shortest lossless float.
  void float(double v) {
    if (v.isNaN) {
      _b.add([0xf9, 0x7e, 0x00]);
      return;
    }
    final bd = ByteData(8);
    bd.setFloat32(0, v);
    if (bd.getFloat32(0) == v) {
      final half = halfBitsExact(v);
      if (half != null) {
        _b.add([0xf9, half >> 8, half & 0xff]);
      } else {
        _b.addByte(0xfa);
        _b.add(bd.buffer.asUint8List(0, 4));
      }
    } else {
      bd.setFloat64(0, v);
      _b.addByte(0xfb);
      _b.add(bd.buffer.asUint8List(0, 8));
    }
  }

  /// Append already-encoded CBOR.
  void raw(List<int> encoded) => _b.add(encoded);

  void value(Value v) => v.encode(this);

  Uint8List takeBytes() => _b.takeBytes();
}

/// IEEE half bits for `v` if `v` is exactly representable as f16.
int? halfBitsExact(double v) {
  final bd = ByteData(4)..setFloat32(0, v);
  final bits = bd.getUint32(0);
  final sign = (bits >> 16) & 0x8000;
  final exp32 = (bits >> 23) & 0xff;
  final mant = bits & 0x7fffff;
  if (exp32 == 0 && mant == 0) return sign; // ±0
  if (exp32 == 0xff) return mant == 0 ? sign | 0x7c00 : null; // ±inf
  if (exp32 == 0) return null; // f32 subnormal: below the f16 range
  final e = exp32 - 127;
  if (e >= -14 && e <= 15) {
    if (mant & 0x1fff != 0) return null;
    return sign | ((e + 15) << 10) | (mant >> 13);
  }
  if (e >= -24 && e < -14) {
    final s = 0x800000 | mant;
    final shift = -(e + 1);
    if (s & ((1 << shift) - 1) != 0) return null;
    return sign | (s >> shift);
  }
  return null;
}

/// f16 bits → double.
double halfToDouble(int h) {
  final sign = (h & 0x8000) != 0 ? -1.0 : 1.0;
  final exp = (h >> 10) & 0x1f;
  final mant = h & 0x3ff;
  if (exp == 0) return sign * mant * _pow2(-24);
  if (exp == 0x1f) return mant == 0 ? sign * double.infinity : double.nan;
  return sign * (1024 + mant) * _pow2(exp - 25);
}

double _pow2(int e) {
  var r = 1.0;
  if (e >= 0) {
    for (var i = 0; i < e; i++) {
      r *= 2;
    }
  } else {
    for (var i = 0; i < -e; i++) {
      r /= 2;
    }
  }
  return r;
}

/// Canonical order for text keys: UTF-8 length first, then bytewise.
int canonicalTextOrder(String a, String b) {
  final ua = utf8.encode(a);
  final ub = utf8.encode(b);
  if (ua.length != ub.length) return ua.length - ub.length;
  for (var i = 0; i < ua.length; i++) {
    if (ua[i] != ub[i]) return ua[i] - ub[i];
  }
  return 0;
}

/// CBOR major types as seen by [CborReader.peek].
enum CborType { uint, nint, bytes, text, array, map, tag, simple, float, breakMark }

/// Low-level CBOR decoder over one buffer.
class CborReader {
  final Uint8List _buf;
  final ByteData _bd;
  int pos = 0;

  CborReader(Uint8List bytes)
      : _buf = bytes,
        _bd = ByteData.sublistView(bytes);

  bool get atEnd => pos >= _buf.length;

  int _byte() {
    if (pos >= _buf.length) throw CborError('unexpected end of input');
    return _buf[pos++];
  }

  CborType peek() {
    if (pos >= _buf.length) throw CborError('unexpected end of input');
    final b = _buf[pos];
    if (b == 0xff) return CborType.breakMark;
    switch (b >> 5) {
      case 0:
        return CborType.uint;
      case 1:
        return CborType.nint;
      case 2:
        return CborType.bytes;
      case 3:
        return CborType.text;
      case 4:
        return CborType.array;
      case 5:
        return CborType.map;
      case 6:
        return CborType.tag;
      default:
        final ai = b & 0x1f;
        return (ai >= 25 && ai <= 27) ? CborType.float : CborType.simple;
    }
  }

  /// Head argument; `null` for indefinite length (ai = 31).
  int? _arg(int ai) {
    if (ai < 24) return ai;
    switch (ai) {
      case 24:
        return _byte();
      case 25:
        _need(2);
        final v = _bd.getUint16(pos);
        pos += 2;
        return v;
      case 26:
        _need(4);
        final v = _bd.getUint32(pos);
        pos += 4;
        return v;
      case 27:
        _need(8);
        final hi = _bd.getUint32(pos);
        final lo = _bd.getUint32(pos + 4);
        pos += 8;
        if (hi >= 0x80000000) throw CborError('integer above 2^63-1');
        return hi * _two32 + lo;
      case 31:
        return null;
      default:
        throw CborError('reserved additional info $ai');
    }
  }

  void _need(int n) {
    if (pos + n > _buf.length) throw CborError('unexpected end of input');
  }

  (int, int?) _head() {
    final b = _byte();
    return (b >> 5, _arg(b & 0x1f));
  }

  int _definite(int major, String what) {
    final (m, n) = _head();
    if (m != major) throw CborError('expected $what, got major type $m');
    if (n == null) throw CborError('indefinite $what not allowed here');
    return n;
  }

  int readUint() => _definite(0, 'unsigned integer');

  int readInt() {
    final (m, n) = _head();
    if (n == null) throw CborError('bad integer');
    if (m == 0) return n;
    if (m == 1) return -1 - n;
    throw CborError('expected integer, got major type $m');
  }

  bool readBool() {
    final b = _byte();
    if (b == 0xf4) return false;
    if (b == 0xf5) return true;
    throw CborError('expected bool');
  }

  double readFloat() {
    final b = _byte();
    switch (b) {
      case 0xf9:
        _need(2);
        final h = _bd.getUint16(pos);
        pos += 2;
        return halfToDouble(h);
      case 0xfa:
        _need(4);
        final v = _bd.getFloat32(pos);
        pos += 4;
        return v;
      case 0xfb:
        _need(8);
        final v = _bd.getFloat64(pos);
        pos += 8;
        return v;
    }
    throw CborError('expected float');
  }

  /// Text string; indefinite (chunked) strings are joined.
  String readText() => utf8.decode(_string(3, 'text'));

  /// Byte string; indefinite (chunked) strings are joined.
  Uint8List readBytes() => _string(2, 'bytes');

  Uint8List _string(int major, String what) {
    final (m, n) = _head();
    if (m != major) throw CborError('expected $what, got major type $m');
    if (n != null) {
      _need(n);
      final out = Uint8List.fromList(_buf.sublist(pos, pos + n));
      pos += n;
      return out;
    }
    final b = BytesBuilder();
    while (peek() != CborType.breakMark) {
      b.add(_string(major, what));
    }
    pos++;
    return b.takeBytes();
  }

  /// Array length, `null` = indefinite (ends at [isBreak]).
  int? readArrayHeader() {
    final (m, n) = _head();
    if (m != 4) throw CborError('expected array, got major type $m');
    return n;
  }

  /// Map length, `null` = indefinite (ends at [isBreak]).
  int? readMapHeader() {
    final (m, n) = _head();
    if (m != 5) throw CborError('expected map, got major type $m');
    return n;
  }

  /// Definite map length (WYRM structs never use indefinite maps).
  int readMapLen() {
    final n = readMapHeader();
    if (n == null) throw CborError('indefinite map not allowed here');
    return n;
  }

  /// Skip a tag head (the tagged item follows).
  void skipTagHead() {
    final (m, _) = _head();
    if (m != 6) throw CborError('expected tag, got major type $m');
  }

  /// Consume a break if one is next.
  bool takeBreak() {
    if (pos < _buf.length && _buf[pos] == 0xff) {
      pos++;
      return true;
    }
    return false;
  }

  void readNull() {
    final b = _byte();
    if (b != 0xf6 && b != 0xf7) throw CborError('expected null');
  }

  /// Skip one complete item.
  void skip() {
    final t = peek();
    switch (t) {
      case CborType.uint:
      case CborType.nint:
        _head();
      case CborType.bytes:
      case CborType.text:
        _string(t == CborType.bytes ? 2 : 3, 'string');
      case CborType.array:
        final n = readArrayHeader();
        if (n == null) {
          while (!takeBreak()) {
            skip();
          }
        } else {
          for (var i = 0; i < n; i++) {
            skip();
          }
        }
      case CborType.map:
        final n = readMapHeader();
        if (n == null) {
          while (!takeBreak()) {
            skip();
            skip();
          }
        } else {
          for (var i = 0; i < 2 * n; i++) {
            skip();
          }
        }
      case CborType.tag:
        _head();
        skip();
      case CborType.float:
        readFloat();
      case CborType.simple:
        final b = _byte();
        if ((b & 0x1f) == 24) _byte();
      case CborType.breakMark:
        throw CborError('unexpected break');
    }
  }

  /// One item as a WYRM [Value] (text-keyed maps only).
  Value readValue() => Value.decode(this);

  /// One item as plain Dart objects, any map keys: `null`, `bool`, `int`,
  /// `double`, `String`, `Uint8List`, `List<Object?>`, `Map<Object?, Object?>`.
  /// For diagnostics and tests; protocol code uses the typed decoders.
  Object? readAny() {
    switch (peek()) {
      case CborType.uint:
      case CborType.nint:
        return readInt();
      case CborType.bytes:
        return readBytes();
      case CborType.text:
        return readText();
      case CborType.array:
        final n = readArrayHeader();
        final out = <Object?>[];
        if (n == null) {
          while (!takeBreak()) {
            out.add(readAny());
          }
        } else {
          for (var i = 0; i < n; i++) {
            out.add(readAny());
          }
        }
        return out;
      case CborType.map:
        final n = readMapHeader();
        final out = <Object?, Object?>{};
        if (n == null) {
          while (!takeBreak()) {
            final k = readAny();
            out[k] = readAny();
          }
        } else {
          for (var i = 0; i < n; i++) {
            final k = readAny();
            out[k] = readAny();
          }
        }
        return out;
      case CborType.tag:
        _head();
        return readAny();
      case CborType.float:
        return readFloat();
      case CborType.simple:
        final b = _buf[pos];
        if (b == 0xf4 || b == 0xf5) return readBool();
        if (b == 0xf6 || b == 0xf7) {
          readNull();
          return null;
        }
        throw CborError('unsupported simple value 0x${b.toRadixString(16)}');
      case CborType.breakMark:
        throw CborError('unexpected break');
    }
  }

  /// Fail if input remains after the top-level item.
  void expectEnd() {
    if (!atEnd) throw CborError('${_buf.length - pos} trailing bytes');
  }
}

/// Decode exactly one top-level item with [read].
T decodeCbor<T>(List<int> bytes, T Function(CborReader r) read) {
  final r = CborReader(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  final v = read(r);
  r.expectEnd();
  return v;
}

/// Encode with [write] into a fresh buffer.
Uint8List encodeCbor(void Function(CborWriter w) write) {
  final w = CborWriter();
  write(w);
  return w.takeBytes();
}

/// Lower-case hex of [b].
String hexOf(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Bytes of a hex string.
Uint8List hexDecode(String h) {
  if (h.length.isOdd) throw FormatException('odd hex length');
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}
