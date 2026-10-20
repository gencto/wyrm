// Zenoh attachment (spec 04): integer-keyed CBOR map, every field optional.

import 'dart:typed_data';

import 'cbor.dart';
import 'tables.dart';

class Attachment {
  StatusCode? status;
  String? qual;
  int? ts;
  bool? refreshed;
  Uint8List? ptok;
  Perm? maxperm;
  String? audit;
  String? err;
  int? rev;
  int? rid;
  int? seq;
  bool? last;
  String? origin;

  /// 16 bytes.
  Uint8List? trace;
  String? enc;

  Attachment({
    this.status,
    this.qual,
    this.ts,
    this.refreshed,
    this.ptok,
    this.maxperm,
    this.audit,
    this.err,
    this.rev,
    this.rid,
    this.seq,
    this.last,
    this.origin,
    this.trace,
    this.enc,
  });

  void encode(CborWriter w) {
    final fields = <int, void Function()>{
      if (status != null) 0: () => w.uint(status!.code),
      if (qual != null) 1: () => w.text(qual!),
      if (ts != null) 2: () => w.uint(ts!),
      if (refreshed != null) 3: () => w.boolean(refreshed!),
      if (ptok != null) 4: () => w.bytes(ptok!),
      if (maxperm != null) 5: () => w.uint(maxperm!.code),
      if (audit != null) 6: () => w.text(audit!),
      if (err != null) 7: () => w.text(err!),
      if (rev != null) 8: () => w.uint(rev!),
      if (rid != null) 9: () => w.uint(rid!),
      if (seq != null) 10: () => w.uint(seq!),
      if (last != null) 11: () => w.boolean(last!),
      if (origin != null) 12: () => w.text(origin!),
      if (trace != null) 13: () => w.bytes(trace!),
      if (enc != null) 14: () => w.text(enc!),
    };
    w.mapHeader(fields.length);
    for (final e in fields.entries) {
      w.uint(e.key);
      e.value();
    }
  }

  static Attachment decode(CborReader r) {
    final a = Attachment();
    final n = r.readMapLen();
    for (var i = 0; i < n; i++) {
      switch (r.readUint()) {
        case 0:
          a.status = StatusCode(r.readUint());
        case 1:
          a.qual = r.readText();
        case 2:
          a.ts = r.readUint();
        case 3:
          a.refreshed = r.readBool();
        case 4:
          a.ptok = r.readBytes();
        case 5:
          final c = r.readUint();
          a.maxperm = Perm.fromCode(c) ?? (throw CborError('bad maxperm $c'));
        case 6:
          a.audit = r.readText();
        case 7:
          a.err = r.readText();
        case 8:
          a.rev = r.readUint();
        case 9:
          a.rid = r.readUint();
        case 10:
          a.seq = r.readUint();
        case 11:
          a.last = r.readBool();
        case 12:
          a.origin = r.readText();
        case 13:
          final b = r.readBytes();
          if (b.length != 16) throw CborError('trace must be 16 bytes');
          a.trace = b;
        case 14:
          a.enc = r.readText();
        default:
          r.skip();
      }
    }
    return a;
  }

  Uint8List toCbor() => encodeCbor(encode);
  static Attachment fromCbor(List<int> b) => decodeCbor(b, decode);
}
