import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/json_value.dart';
import 'package:models/profile_draft.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'fields.dart';

const _shape = 'profile';

/// The fields of a profile's JSON form (specs/system.md).
const _known = {
  'extends',
  'type',
  'unit',
  'enum',
  'display',
  'children',
  'cfg',
  'attr',
};

/// The [ProfileDraft] of the bytes of a profile's JSON file: `extends`,
/// `type` (a spec 02 type by its name), `unit`, `enum` (names),
/// `display`, `children` (names), `cfg` and `attr` (maps). Read strictly:
/// bytes that are no JSON object, a field the form does not have, a type
/// Studio does not know and a field of another form are each [Invalid]
/// with the field; nothing of such a file is sent.
Decoded<ProfileDraft> profileDraftOf(List<int> bytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return const Invalid(_shape, '', 'not JSON');
  }
  return profileDraftOfJson(json);
}

/// [profileDraftOf] for a file already parsed as JSON.
Decoded<ProfileDraft> profileDraftOfJson(Object? json) => decoding(_shape, () {
  final f = switch (JsonValue.tryOf(json)) {
    JsonMap(:final fields) => fields,
    _ => throw const BadField('', 'not a JSON object'),
  };
  for (final key in f.keys) {
    if (!_known.contains(key)) {
      throw BadField(key, 'not a field of a profile');
    }
  }
  String? text(String field) => switch (f[field]) {
    null || JsonNull() => null,
    JsonText(:final text) => text,
    _ => throw BadField(field, 'not a text'),
  };
  IList<String>? names(String field) => switch (f[field]) {
    null || JsonNull() => null,
    JsonList(:final items) => [
      for (final x in items)
        switch (x) {
          JsonText(:final text) => text,
          _ => throw BadField(field, 'not texts'),
        },
    ].lock,
    _ => throw BadField(field, 'not a list'),
  };
  IMap<String, JsonValue>? map(String field) => switch (f[field]) {
    null || JsonNull() => null,
    JsonMap(:final fields) => fields,
    _ => throw BadField(field, 'not a map'),
  };
  return ProfileDraft(
    parent: text('extends'),
    type: switch (text('type')) {
      null => null,
      final name =>
        TypeCode.values.where((c) => c.wireName == name).firstOrNull ??
            (throw const BadField('type', 'not a known type')),
    },
    unit: text('unit'),
    enumValues: names('enum'),
    display: text('display'),
    children: names('children'),
    cfg: map('cfg'),
    attr: map('attr'),
  );
});
