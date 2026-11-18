import 'dart:typed_data';

import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/profile_draft.dart';
import 'package:models/studio_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../decode/decoded.dart';
import '../decode/profile_draft.dart';
import '../failures.dart';

/// The bytes `sys/profiles ▸ put` takes for a picked file: a `.cbor` file is
/// the CBOR `ProfileDef` already and goes as it is; a JSON file is read
/// once into a [ProfileDraft] ([profileDraftOf]) and encoded here
/// (specs/system.md, proposed).
///
/// A JSON file that is no profile is refused before the call: a typed
/// refusal the app words ([ErrorHint.fileNotRead]) with the field at
/// fault, which is also in the log.
Uint8List profileBytes(String fileName, Uint8List bytes) {
  if (!fileName.toLowerCase().endsWith('.json')) {
    return bytes;
  }
  switch (profileDraftOf(bytes)..record(fileName)) {
    case Valid(:final value):
      return encodeProfile(value, fileName: fileName);
    case Invalid(:final field):
      throw _notRead(fileName, field);
  }
}

StudioException _notRead(String fileName, String field) => StudioException(
  StudioError(
    kind: ErrorKind.input,
    hint: ErrorHint.fileNotRead,
    call: 'read',
    thing: fileName,
    field: field.isEmpty ? null : field,
  ),
);

/// A CBOR `ProfileDef` (spec 02) of [draft]: the `NodeMeta` entries under
/// their integer keys, then the text key `extends`.
Uint8List encodeProfile(ProfileDraft draft, {String fileName = 'profile'}) {
  Map<String, Value>? values(ProfileDraft d, {required bool cfg}) =>
      switch (cfg ? d.cfg : d.attr) {
        final m? => {
          for (final e in m.entries) e.key: Value.from(e.value.raw),
        },
        null => null,
      };
  final meta = NodeMeta(
    ty: draft.type,
    unit: switch (draft.unit) {
      final u? => TText(u),
      null => null,
    },
    enumValues: draft.enumValues?.unlock,
    cfg: values(draft, cfg: true),
    attr: values(draft, cfg: false),
    children: draft.children?.unlock,
    display: draft.display,
  ).toCbor();
  final parent = draft.parent;
  if (parent == null) {
    return meta;
  }
  // A map of fewer than 23 entries has a one-byte head (0xA0 + n): one more
  // entry is one more in that byte.
  final n = meta.first & 0x1f;
  if (meta.first >> 5 != 5 || n >= 23) {
    throw _notRead(fileName, 'extends');
  }
  return Uint8List.fromList([
    0xa0 + n + 1,
    ...meta.skip(1),
    ...encodeCbor((w) => w.text('extends')),
    ...encodeCbor((w) => w.text(parent)),
  ]);
}
