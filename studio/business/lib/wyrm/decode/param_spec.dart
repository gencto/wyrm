import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/param_spec.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';

/// The parameters of an action as [ParamSpec]s, in declaration order.
List<ParamSpec> paramSpecsOf(ActionMeta action) => [
  for (final e in action.params.entries) paramSpecOf(e.key, e.value),
];

/// One parameter (spec 02 `ParamMeta`, decoded by `wyrm_client`) as a
/// [ParamSpec]: a parameter with choices is an `enum`, one with no type a
/// `string`; its default as JSON; a password's editor is its `secret`.
ParamSpec paramSpecOf(String name, ParamMeta p) {
  final choices = p.enumValues ?? const <String>[];
  return ParamSpec(
    name: name,
    display: p.display,
    type: choices.isNotEmpty ? TypeCode.enum_ : (p.ty ?? TypeCode.string),
    required: p.required ?? false,
    defaultValue: toDart(p.defaultValue),
    choices: choices.lock,
    editor: p.isPassword ? null : p.editorKind,
    secret: p.isPassword,
    description: p.description ?? p.placeholder,
  );
}
