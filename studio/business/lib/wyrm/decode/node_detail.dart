import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/action_info.dart';
import 'package:models/node_detail.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';
import 'param_spec.dart';

/// The full `~meta` of [key] as a [NodeDetail].
NodeDetail nodeDetailOf(String key, NodeMeta m) => NodeDetail(
  key: key,
  display: m.displayName,
  profile: m.profileName,
  type: m.ty,
  unit: m.unit?.toString(),
  writable: _setLevel(m.writable),
  invokable: m.invokable,
  choices: (m.enumValues ?? const <String>[]).lock,
  actions: [
    for (final e in (m.actions ?? const <String, ActionMeta>{}).entries)
      // as the link checks a call (`act.level.or(invokable)`, wyrm-link-sdk
      // runtime): an action with no level of its own takes the node's
      // `invokable`; with neither, or `none`, it is not callable
      if (e.value.level ?? m.invokable case final level?
          when level != Perm.none)
        actionInfoOf(e.key, e.value, level),
  ].lock,
  cfg: {
    for (final e in (m.cfg ?? const <String, Value>{}).entries)
      e.key: _text(e.value),
  }.lock,
  attr: {
    for (final e in (m.attr ?? const <String, Value>{}).entries)
      e.key: _text(e.value),
  }.lock,
  hasOverride: m.hasOverride ?? false,
  hasHistory: m.hasHistory ?? (m.attr?['history'] != null),
  rev: m.rev,
);

/// The level a set of a value with `~meta.writable` [w] needs; null when it
/// cannot be set.
Perm? _setLevel(Writable? w) => switch (w) {
  Writable.write => Perm.write,
  Writable.config => Perm.config,
  Writable.never || null => null,
};

/// One action of a node's meta, callable at [level].
ActionInfo actionInfoOf(String name, ActionMeta a, Perm level) => ActionInfo(
  name: name,
  level: level,
  display: a.display,
  group: a.group,
  params: paramSpecsOf(a).lock,
  result: switch (a.result) {
    ResultStream() => 'stream',
    ResultVoid() => 'void',
    ResultType(:final type) => type.wireName,
    null => null,
  },
);

String _text(Value v) => switch (v) {
  VStr(:final v) => v,
  VMap() || VArray() => '${toDart(v)}',
  _ => text(v) ?? '',
};
