import 'package:models/error_kind.dart';
import 'package:models/param_spec.dart';
import 'package:models/studio_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'failures.dart';

/// Runs one broker call; a refusal becomes a [StudioException] that keeps
/// the status as data and the broker's own message (docs/studio.md §2
/// rule 7, docs/design/specs/errors.md §1). [name] is the call (`list`,
/// `meta`, `set`, an action), [key] the key it is made on, [thing] the name
/// of its object for the title when the key's last segment is not it;
/// [write] says it changes something on the broker.
Future<T> call<T>(
  String name,
  String key,
  Future<T> Function() f, {
  String? thing,
  bool write = false,
}) async {
  try {
    return await f();
  } on WyrmException catch (e) {
    throw StudioException.refused(
      e,
      key: key,
      call: name,
      thing: thing,
      write: write,
    );
  }
}

/// The children of [key]; a refusal as in [call].
Future<List<Child>> listOf(WyrmApi api, String key, {String? thing}) =>
    call('list', key, () => api.children(key), thing: thing);

/// The full meta of [key]; a refusal as in [call].
Future<NodeMeta> metaOf(WyrmApi api, String key, {String? thing}) =>
    call('meta', key, () => api.meta(key), thing: thing);

/// The rows of one `invoke` that changes something, collected; a refusal
/// as in [call]. A timeout of it may have been applied, and the dialog
/// says so; an action that only reads goes through [askAll].
Future<List<Value>> invokeAll(
  WyrmApi api,
  String key,
  String action, [
  Value? args,
  String? thing,
]) => call(
  action,
  key,
  () => api.invoke(key, action, args).toList(),
  thing: thing,
  write: true,
);

/// The first row of an action's answer, or `VNull`.
Future<Value> invokeOne(
  WyrmApi api,
  String key,
  String action, [
  Value? args,
  String? thing,
]) async {
  final rows = await invokeAll(api, key, action, args, thing);
  return rows.isEmpty ? const VNull() : rows.first;
}

/// The rows of an action that only reads (`get_log`, `history`,
/// `node_types`, `tail`); a refusal as in [call].
Future<List<Value>> askAll(
  WyrmApi api,
  String key,
  String action, [
  Value? args,
  String? thing,
]) => call(
  action,
  key,
  () => api.invoke(key, action, args).toList(),
  thing: thing,
);

/// The first row of a reading action's answer, or `VNull`.
Future<Value> askOne(
  WyrmApi api,
  String key,
  String action, [
  Value? args,
  String? thing,
]) async {
  final rows = await askAll(api, key, action, args, thing);
  return rows.isEmpty ? const VNull() : rows.first;
}

/// `{success, message}` of an install-style answer: throws a `broker`
/// error with the message when success is false. [action] on [key] is the
/// call that answered.
void requireSuccess(
  Value answer,
  String key,
  String action, {
  String? thing,
}) {
  if (answer['success'] case VBool(v: false)) {
    throw StudioException(
      StudioError(
        kind: ErrorKind.broker,
        message: switch (answer['message']) {
          VStr(:final v) => v,
          _ => '',
        },
        key: key,
        call: action,
        thing: thing,
        site: siteOf(key),
        write: true,
      ),
    );
  }
}

/// The current value of [key]: the first sample of a subscription (the
/// broker answers it from its `~val` storage), or null when none comes
/// within [wait].
Future<Value?> readValue(
  WyrmApi api,
  String key, {
  Duration wait = const Duration(seconds: 2),
}) async {
  try {
    final e = await api
        .subscribe(key)
        .where((e) => e is ValSample)
        .first
        .timeout(wait);
    return (e as ValSample).sample.v;
  } on Object {
    return null;
  }
}

/// The current values under [pattern] (a `*` pattern): every sample that
/// arrives within [wait], by key.
Future<Map<String, Value>> readValues(
  WyrmApi api,
  String pattern, {
  Duration wait = const Duration(milliseconds: 1200),
}) async {
  final out = <String, Value>{};
  try {
    await for (final e
        in api
            .subscribe(pattern)
            .timeout(
              wait,
              onTimeout: (sink) => sink.close(),
            )) {
      if (e case ValSample(:final key, :final sample)) {
        out[key] = sample.v;
      }
    }
  } on Object {
    // A refused or missing pattern reads as nothing.
  }
  return out;
}

/// Dart values as an argument map.
Value valueOf(Map<String, Object?> args) => Value.from(args);

/// The arguments of a form that go to the broker: an optional field left
/// empty is left out, so the action keeps or defaults it. The fields of
/// [keepEmpty] are the exception: an empty one is sent as `""`
/// ([clearedNames]: a node's name the user cleared).
Map<String, Object?> argsToSend(
  Map<String, Object?> args, {
  Iterable<String> keepEmpty = const [],
}) => {
  for (final MapEntry(:key, :value) in args.entries)
    if (value != null && (value != '' || keepEmpty.contains(key))) key: value,
};

/// The fields of a form whose empty value means "clear it", not "keep it"
/// (ADR 0042 §4): a `display` that the action prefilled with the node's
/// name. `edit` without `display` keeps the name and `""` clears it; an
/// Add form, or one that did not prefill a name, still leaves an empty
/// field out (the action's own default stands).
Set<String> clearedNames(Iterable<ParamSpec> params) => {
  for (final p in params)
    if (p.name == 'display' &&
        p.defaultValue is String &&
        (p.defaultValue! as String).trim().isNotEmpty)
      p.name,
};
