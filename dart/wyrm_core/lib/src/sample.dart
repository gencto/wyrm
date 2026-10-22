// `~val` payload `{0: v, 1: q, 2: t}` (spec 03) and `~set` request `{0: v}`.

import 'dart:typed_data';

import 'cbor.dart';
import 'tables.dart';
import 'value.dart';

class Sample {
  final Value v;
  final Quality q;

  /// Source timestamp, microseconds since the Unix epoch.
  final int t;

  const Sample(this.v, {this.q = Quality.good, required this.t});

  void encode(CborWriter w) {
    w.mapHeader(3);
    w.uint(0);
    v.encode(w);
    w.uint(1);
    w.uint(q.code);
    w.uint(2);
    w.uint(t);
  }

  static Sample decode(CborReader r) {
    Value v = const VNull();
    var q = Quality.good;
    var t = 0;
    final n = r.readMapLen();
    for (var i = 0; i < n; i++) {
      switch (r.readUint()) {
        case 0:
          v = r.readValue();
        case 1:
          final c = r.readUint();
          q = Quality.fromCode(c) ?? (throw CborError('bad quality $c'));
        case 2:
          t = r.readUint();
        default:
          r.skip();
      }
    }
    return Sample(v, q: q, t: t);
  }

  Uint8List toCbor() => encodeCbor(encode);
  static Sample fromCbor(List<int> b) => decodeCbor(b, decode);

  @override
  bool operator ==(Object other) =>
      other is Sample && other.v == v && other.q == q && other.t == t;
  @override
  int get hashCode => Object.hash(v, q, t);
  @override
  String toString() => 'Sample($v, ${q.wireName}, $t)';
}

/// One row of a history answer (`get ~val?history=`, spec 03): a sample
/// `[t, v, q]`, or with `agg` a rollup `[t_start, v]` (`q` null).
class HistRow {
  /// Microseconds since the Unix epoch: the sample's time or its window's start.
  final int t;
  final Value v;
  final Quality? q;

  const HistRow(this.t, this.v, [this.q]);

  void encode(CborWriter w) {
    w.arrayHeader(q == null ? 2 : 3);
    w.uint(t);
    v.encode(w);
    if (q case final q?) w.uint(q.code);
  }

  static HistRow decode(CborReader r) {
    final n = r.readArrayHeader() ?? (throw CborError('indefinite history row'));
    if (n < 2 || n > 3) throw CborError('history row of $n items (2 or 3)');
    final t = r.readUint();
    final v = r.readValue();
    Quality? q;
    if (n == 3) {
      final c = r.readUint();
      q = Quality.fromCode(c) ?? (throw CborError('bad quality $c'));
    }
    return HistRow(t, v, q);
  }

  static List<HistRow> decodeList(CborReader r) {
    final n = r.readArrayHeader() ?? (throw CborError('indefinite history'));
    return [for (var i = 0; i < n; i++) decode(r)];
  }

  static void encodeList(CborWriter w, List<HistRow> l) {
    w.arrayHeader(l.length);
    for (final row in l) {
      row.encode(w);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HistRow && other.t == t && other.v == v && other.q == q;
  @override
  int get hashCode => Object.hash(t, v, q);
  @override
  String toString() => 'HistRow($t, $v, ${q?.wireName})';
}

/// `~set` request payload `{0: v}` (spec 05).
Uint8List encodeSetRequest(Value v) => encodeCbor((w) {
      w.mapHeader(1);
      w.uint(0);
      v.encode(w);
    });
