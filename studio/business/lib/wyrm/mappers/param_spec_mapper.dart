import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/param_spec.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The parameters of an action as [ParamSpec]s, in declaration order.
List<ParamSpec> paramSpecsOf(ActionMeta action) => [
  for (final e in action.params.entries) paramSpecOf(e.key, e.value),
];

/// One parameter (spec 02 `ParamMeta`) as a [ParamSpec].
ParamSpec paramSpecOf(String name, ParamMeta p) {
  final choices = p.enumValues ?? const <String>[];
  return ParamSpec(
    name: name,
    display: p.display,
    type: choices.isNotEmpty ? 'enum' : (p.ty?.wireName ?? 'string'),
    required: p.required ?? false,
    defaultValue: toDart(p.defaultValue),
    choices: choices.lock,
    editor: p.isPassword ? null : p.editor,
    secret: p.isPassword,
    description: p.description ?? p.placeholder,
  );
}
