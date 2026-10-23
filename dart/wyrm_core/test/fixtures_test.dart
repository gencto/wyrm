// Compatibility contract (spec rule): every fixture in
// spec/fixtures/fixtures.json decodes to its documented JSON and the typed
// codec re-encodes it to the exact canonical bytes.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wyrm_core/wyrm_core.dart';

final _specDir = Directory('../../spec');

List<Map<String, Object?>> _fixtures() {
  final raw = File('${_specDir.path}/fixtures/fixtures.json').readAsStringSync();
  return (jsonDecode(raw) as List).cast<Map<String, Object?>>();
}

/// Typed decode → encode for a fixture, chosen by name as in the Rust test.
Uint8List _typedRoundTrip(String name, Uint8List bytes) {
  Uint8List rt<T>(T Function(CborReader) dec, void Function(CborWriter, T) enc) {
    final v = decodeCbor(bytes, dec);
    final out = encodeCbor((w) => enc(w, v));
    // Decoding the re-encoded bytes must give the same bytes again.
    final again = encodeCbor((w) => enc(w, decodeCbor(out, dec)));
    expect(hexOf(again), hexOf(out), reason: '$name: second round trip');
    return out;
  }

  if (name.startsWith('val_')) return rt(Sample.decode, (w, s) => s.encode(w));
  if (name.startsWith('hist_')) return rt(HistRow.decodeList, HistRow.encodeList);
  if (name == 'meta_view_list') return rt(NodeMeta.decodeList, NodeMeta.encodeList);
  if (name == 'meta_view_keys') return rt(decodeKeyList, encodeKeyList);
  if (name == 'meta_patch') return rt(MetaPatch.decode, (w, p) => p.encode(w));
  if (name.startsWith('profile_')) return rt(ProfileDef.decode, (w, p) => p.encode(w));
  if (name.startsWith('meta_')) return rt(NodeMeta.decode, (w, m) => m.encode(w));
  if (name.startsWith('att_')) return rt(Attachment.decode, (w, a) => a.encode(w));
  if (name == 'ptok_claims_v1') {
    // Generic Value and the typed claims must both be exact.
    final viaClaims = PtokClaims.fromCbor(bytes).toCbor();
    expect(hexOf(viaClaims), hexOf(bytes), reason: '$name: PtokClaims');
    return rt(Value.decode, (w, v) => v.encode(w));
  }
  fail('unclassified fixture $name — add it to the Dart codec');
}

/// Decoded CBOR in the generator's JSON conventions: map keys as text,
/// byte strings as lower-case hex.
Object? _asJson(Object? v) => switch (v) {
      Uint8List b => hexOf(b),
      List<Object?> l => [for (final e in l) _asJson(e)],
      Map<Object?, Object?> m => {for (final e in m.entries) '${e.key}': _asJson(e.value)},
      _ => v,
    };

bool _jsonEq(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_jsonEq(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

void main() {
  final fixtures = _fixtures();

  test('fixture count matches the .cbor.hex files', () {
    final files = Directory('${_specDir.path}/fixtures')
        .listSync()
        .where((f) => f.path.endsWith('.cbor.hex'))
        .length;
    expect(fixtures.length, files);
    expect(fixtures.length, greaterThanOrEqualTo(23));
  });

  for (final f in fixtures) {
    final name = f['name'] as String;
    final hex = f['hex'] as String;
    group(name, () {
      final bytes = hexDecode(hex);

      test('length', () => expect(bytes.length, f['len']));

      test('decodes to the documented JSON', () {
        final any = decodeCbor(bytes, (r) => r.readAny());
        expect(_jsonEq(_asJson(any), f['json']), isTrue,
            reason: 'decoded ${_asJson(any)}\nexpected ${f['json']}');
      });

      test('typed codec re-encodes to the exact bytes', () {
        expect(hexOf(_typedRoundTrip(name, bytes)), hex);
      });

      test('the .cbor.hex file agrees', () {
        final file = File('${_specDir.path}/fixtures/$name.cbor.hex');
        expect(file.readAsStringSync().trim(), hex);
      });
    });
  }

  test('val_number typed fields', () {
    final f = fixtures.firstWhere((f) => f['name'] == 'val_number');
    final s = Sample.fromCbor(hexDecode(f['hex'] as String));
    expect(s.v, const VFloat(21.4));
    expect(s.q, Quality.good);
    expect(s.t, 1760000000123456);
  });

  test('meta_number_full typed fields', () {
    final f = fixtures.firstWhere((f) => f['name'] == 'meta_number_full');
    final m = NodeMeta.fromCbor(hexDecode(f['hex'] as String));
    expect(m.is_, const TCode(2));
    expect(m.profileName, 'wy:number');
    expect(m.ty, TypeCode.number);
    expect(m.unit, const TText('°C'));
    expect(m.cfg!['min'], const VFloat(-40.0));
    expect(m.cfg!['precision'], const VInt(1));
    expect(m.displayName, 'Supply air temp');
    expect(m.rev, 17);
  });

  test('meta_folder_full action', () {
    final f = fixtures.firstWhere((f) => f['name'] == 'meta_folder_full');
    final m = NodeMeta.fromCbor(hexDecode(f['hex'] as String));
    final reset = m.actions!['reset']!;
    expect(reset.params['mode']!.ty, TypeCode.enum_);
    expect(reset.params['mode']!.enumValues, ['soft', 'hard']);
    expect(reset.result, isA<ResultType>());
    expect(m.children, ['supply_temp', 'return_temp', 'fan']);
  });

  test('meta_action_ui UI fields', () {
    final f = fixtures.firstWhere((f) => f['name'] == 'meta_action_ui');
    final m = NodeMeta.fromCbor(hexDecode(f['hex'] as String));
    final add = m.actions!['add_device']!;
    expect(add.display, 'Add Device');
    expect(add.group, 'new');
    expect(add.params['unit']!.display, 'Slave ID');
    expect(add.params['unit']!.description, '1..247');
    expect(add.params['host']!.placeholder, '10.0.1.199');
    expect(add.params['password']!.isPassword, isTrue);
    expect(m.actions!['restart']!.group, isNull);
  });

  test('profile_extends typed fields', () {
    final f = fixtures.firstWhere((f) => f['name'] == 'profile_extends');
    final p = ProfileDef.fromCbor(hexDecode(f['hex'] as String));
    expect(p.extends_, 'wy:number');
    expect(p.meta.ty, TypeCode.number);
    expect(p.meta.unit, const TText('°C'));
  });

  test('att_reply_err status', () {
    final f = fixtures.firstWhere((f) => f['name'] == 'att_reply_err');
    final a = Attachment.fromCbor(hexDecode(f['hex'] as String));
    expect(a.status!.isError, isTrue);
    expect(a.status!.known, Status.outOfRange);
    expect(a.err, 'value 150 > max 120');
  });

  test('ptok claims structure', () {
    final f = fixtures.firstWhere((f) => f['name'] == 'ptok_claims_v1');
    final c = PtokClaims.fromCbor(hexDecode(f['hex'] as String));
    expect(c.site, 'plant-a');
    expect(c.grants, hasLength(3));
    expect(c.grants[1].k, 'wy/plant-a/downstream/bacnet/**');
    expect(c.grants[1].p, Perm.write);
    expect(c.jti, List.filled(16, 0x11));
  });

  test('view=keys expands and compresses', () {
    final f = fixtures.firstWhere((f) => f['name'] == 'meta_view_keys');
    final compressed = decodeCbor(hexDecode(f['hex'] as String), decodeKeyList);
    final expanded = expandKeys(compressed);
    expect(expanded, ['ahu1/supply_temp', 'ahu1/return_temp', 'ahu1/fan', 'ahu2/supply_temp']);
    expect(compressKeys(expanded), compressed);
  });
}
