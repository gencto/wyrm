import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/action_info.dart';
import 'package:models/node_detail.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'param_spec_mapper.dart';
import 'values.dart';

/// The full `~meta` of [key] as a [NodeDetail].
NodeDetail nodeDetailOf(String key, NodeMeta m) => NodeDetail(
  key: key,
  display: m.displayName,
  profile: m.profileName,
  type: m.ty,
  unit: m.unit?.toString(),
  writable: _setLevel(m.writable),
  invokable: m.invokable?.wireName,
  choices: (m.enumValues ?? const <String>[]).lock,
  actions: [
    for (final e in (m.actions ?? const <String, ActionMeta>{}).entries)
      if (e.value.level != Perm.none) actionInfoOf(e.key, e.value),
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

/// One action of a node's meta.
ActionInfo actionInfoOf(String name, ActionMeta a) => ActionInfo(
  name: name,
  display: a.display,
  group: a.group,
  level: a.level ?? Perm.write,
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
