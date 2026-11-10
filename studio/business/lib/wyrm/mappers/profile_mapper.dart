import 'dart:convert';
import 'dart:typed_data';

import 'package:models/error_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../failures.dart';

/// The bytes `sys/profiles ▸ put` takes for a picked file: a `.cbor` file is
/// the CBOR `ProfileDef` already and goes as it is; a JSON file is encoded
/// here (specs/system.md, proposed).
///
/// The JSON form is the profile's `~meta` in words: `extends`, `type`
/// (`number`, `string`, `bool`, `enum`, …), `unit`, `enum` (names),
/// `display`, `children` (names), `cfg` and `attr` (maps).
Uint8List profileBytes(String fileName, Uint8List bytes) {
  if (!fileName.toLowerCase().endsWith('.json')) {
    return bytes;
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    throw StudioException.said(
      ErrorKind.input,
      'It is not JSON: ${e.message}',
      call: 'read',
      thing: fileName,
    );
  }
  if (json is! Map<String, Object?>) {
    throw StudioException.said(
      ErrorKind.input,
      'A profile is a JSON object.',
      call: 'read',
      thing: fileName,
    );
  }
  return encodeProfile(json);
}

/// A CBOR `ProfileDef` (spec 02): the `NodeMeta` entries under their integer
/// keys, then the text key `extends`.
Uint8List encodeProfile(Map<String, Object?> json) {
  const known = {
    'extends',
    'type',
    'unit',
    'enum',
    'display',
    'children',
    'cfg',
    'attr',
  };
  for (final k in json.keys) {
    if (!known.contains(k)) {
      throw StudioException.said(
        ErrorKind.input,
        'Unknown key "$k" (known: ${known.join(', ')}).',
        call: 'encode',
        thing: 'profile',
      );
    }
  }
  TypeCode? ty;
  if (json['type'] case final String t) {
    ty = TypeCode.values.where((c) => c.wireName == t).firstOrNull;
    if (ty == null) {
      throw StudioException.said(
        ErrorKind.input,
        'Unknown type "$t".',
        call: 'encode',
        thing: 'profile',
      );
    }
  }
  List<String>? names(String key) => switch (json[key]) {
    final List<Object?> l => [for (final e in l) '$e'],
    _ => null,
  };
  Map<String, Value>? map(String key) => switch (json[key]) {
    final Map<String, Object?> m => {
      for (final e in m.entries) e.key: Value.from(e.value),
    },
    _ => null,
  };
  final meta = NodeMeta(
    ty: ty,
    unit: switch (json['unit']) {
      final String u => TText(u),
      _ => null,
    },
    enumValues: names('enum'),
    cfg: map('cfg'),
    attr: map('attr'),
    children: names('children'),
    display: switch (json['display']) {
      final String d => d,
      _ => null,
    },
  ).toCbor();
  final parent = json['extends'];
  if (parent is! String) {
    return meta;
  }
  // A map of fewer than 23 entries has a one-byte head (0xA0 + n): one more
  // entry is one more in that byte.
  final n = meta.first & 0x1f;
  if (meta.first >> 5 != 5 || n >= 23) {
    throw StudioException.said(
      ErrorKind.input,
      'The profile has too many entries to add extends.',
      call: 'encode',
      thing: 'profile',
    );
  }
  return Uint8List.fromList([
    0xa0 + n + 1,
    ...meta.skip(1),
    ...encodeCbor((w) => w.text('extends')),
    ...encodeCbor((w) => w.text(parent)),
  ]);
}
