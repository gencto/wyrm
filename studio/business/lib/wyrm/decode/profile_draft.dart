import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/json_value.dart';
import 'package:models/manifest_fault.dart';
import 'package:models/manifest_problem.dart';
import 'package:models/profile_draft.dart';
import 'package:models/profile_read.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

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

/// A field of a profile that is not of its form.
final class _Bad implements Exception {
  const _Bad(this.problem);

  final ManifestProblem problem;
}

Never _bad(ManifestFault fault, [String field = '', String? found]) =>
    throw _Bad(ManifestProblem(fault: fault, field: field, found: found));

/// The [ProfileDraft] of the bytes of a profile's JSON file: `extends`,
/// `type` (a spec 02 type by its name), `unit`, `enum` (names),
/// `display`, `children` (names), `cfg` and `attr` (maps). Read strictly:
/// bytes that are no JSON object, a field the form does not have, a type
/// Studio does not know and a field of another form each give a typed
/// problem with the field (and the name, for an unknown type); nothing of
/// such a file is sent.
ProfileRead profileDraftOf(List<int> bytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    decodeLog.fine('profile: not JSON: ${e.message}');
    return ProfileRead.unreadable(
      ManifestProblem(fault: ManifestFault.notJson, offset: e.offset),
    );
  }
  return profileDraftOfJson(json);
}

/// [profileDraftOf] for a file already parsed as JSON ([json] is what
/// `jsonDecode` gives).
ProfileRead profileDraftOfJson(Object? json) {
  try {
    final JsonValue value;
    try {
      value = JsonValue.of(json);
    } on JsonTooDeep {
      _bad(ManifestFault.tooDeep);
    }
    final f = switch (value) {
      JsonMap(:final fields) => fields,
      _ => _bad(ManifestFault.notObject),
    };
    for (final key in f.keys) {
      if (!_known.contains(key)) {
        _bad(ManifestFault.unknownField, key);
      }
    }
    String? text(String field) => switch (f[field]) {
      null || JsonNull() => null,
      JsonText(:final text) => text,
      _ => _bad(ManifestFault.wrongForm, field),
    };
    IList<String>? names(String field) => switch (f[field]) {
      null || JsonNull() => null,
      JsonList(:final items) => [
        for (final x in items)
          switch (x) {
            JsonText(:final text) => text,
            _ => _bad(ManifestFault.wrongForm, field),
          },
      ].lock,
      _ => _bad(ManifestFault.wrongForm, field),
    };
    IMap<String, JsonValue>? map(String field) => switch (f[field]) {
      null || JsonNull() => null,
      JsonMap(:final fields) => fields,
      _ => _bad(ManifestFault.wrongForm, field),
    };
    return ProfileRead.read(
      ProfileDraft(
        parent: text('extends'),
        type: switch (text('type')) {
          null => null,
          final name =>
            TypeCode.values.where((c) => c.wireName == name).firstOrNull ??
                _bad(ManifestFault.unknownName, 'type', name),
        },
        unit: text('unit'),
        enumValues: names('enum'),
        display: text('display'),
        children: names('children'),
        cfg: map('cfg'),
        attr: map('attr'),
      ),
    );
  } on _Bad catch (b) {
    return ProfileRead.unreadable(b.problem);
  }
}
