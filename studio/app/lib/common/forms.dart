import 'package:async_redux/async_redux.dart';
import 'package:business/wyrm/failures.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:models/error_kind.dart';
import 'package:models/param_spec.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';

/// The fields of a form built from an action's parameters (docs/studio.md
/// §6.6). Values are kept by the form; `onChanged` here does nothing.
List<ParamFieldVm> paramFields(IList<ParamSpec> specs) => [
  for (final p in specs) paramField(p),
];

/// One parameter as a field.
ParamFieldVm paramField(ParamSpec p) {
  final kind = switch (p) {
    ParamSpec(secret: true) => ParamKind.secret,
    ParamSpec(editor: 'file') => ParamKind.file,
    ParamSpec(editor: 'textarea') ||
    ParamSpec(type: 'map' || 'array') => ParamKind.textarea,
    ParamSpec(choices: final c) when c.isNotEmpty => ParamKind.choice,
    ParamSpec(type: 'bool') => ParamKind.toggle,
    ParamSpec(type: 'number') => ParamKind.number,
    _ => ParamKind.text,
  };
  final bounds = [
    if (p.min case final m?) '$m',
    if (p.max case final m?) '$m',
  ];
  return ParamFieldVm(
    id: p.name,
    label: p.display ?? p.name,
    kind: kind,
    value: p.defaultValue,
    choices: p.choices.unlock,
    required: p.required,
    hint: bounds.length == 2 ? bounds.join('…') : p.description,
    description: bounds.length == 2 ? p.description : null,
    onChanged: (_) {},
  );
}

/// The values of an [ActionForm] as action arguments: a picked file becomes
/// its bytes, a map typed as JSON text stays text (the broker parses it).
Map<String, Object?> plainArgs(Map<String, Object?> values) => {
  for (final MapEntry(:key, :value) in values.entries)
    key: switch (value) {
      final PickedFile f => f.bytes,
      _ => value,
    },
};

/// What a failed dispatch says to the form that sent it
/// (docs/design/specs/errors.md §3, *Back to the form*): the broker's words
/// and the field they name, when it refused the input. Null when [status]
/// is no refusal of the input (the error dialog alone says the rest).
///
/// [fields] maps a parameter of the call to the id of the form's field
/// that holds it, where the two differ.
FieldRefusal? formRefusal(
  ActionStatus status, {
  Map<String, String> fields = const {},
}) {
  final e = switch (status.originalError) {
    final StudioException x => x.error,
    _ => switch (status.wrappedError) {
      final StudioException x => x.error,
      _ => null,
    },
  };
  if (e == null || e.kind != ErrorKind.input || e.message.isEmpty) {
    return null;
  }
  return switch (e.field) {
    final f? => FieldRefusal(saidOf(e.message, f), field: fields[f] ?? f),
    null => FieldRefusal(e.message),
  };
}

/// The submit of every form that sends something: waits for [sent], runs
/// [onOk] when it went through (close the dialog), and answers the form
/// what the broker refused, so it marks the field ([formRefusal]). One
/// mechanism for all forms; a form only says what it dispatches.
Future<FieldRefusal?> sendForm(
  Future<ActionStatus> sent, {
  VoidCallback? onOk,
  Map<String, String> fields = const {},
}) async {
  final status = await sent;
  if (status.isCompletedOk) {
    onOk?.call();
    return null;
  }
  return formRefusal(status, fields: fields);
}
