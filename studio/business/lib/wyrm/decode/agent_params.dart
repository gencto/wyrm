import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_params.dart';
import 'package:models/approval_mode.dart';

import 'decoded.dart';

// The agent link's params as JSON (a revision of `sys/links/<id>` ▸
// `history`, the `params` an update stages) and as [AgentParams]: read
// once here, written back by [agentParamsJson].

const _mode = 'require_approval';
const _prefixes = 'allowed_prefixes';

/// The params [json] (a JSON object). `require_approval` is a mode the link
/// has, `allowed_prefixes` a list of text; either may be absent. Any other
/// shape is [Invalid] with its param.
Decoded<AgentParams> agentParamsOf(Object? json) {
  if (json is! Map<String, Object?>) {
    return const Invalid('agent params', '', 'not an object');
  }
  final ApprovalMode? mode;
  switch (json[_mode]) {
    case null:
      mode = null;
    case final String s when ApprovalMode.fromWire(s) != null:
      mode = ApprovalMode.fromWire(s);
    case _:
      return const Invalid('agent params', _mode, 'not a mode of the link');
  }
  final IList<String>? prefixes;
  switch (json[_prefixes]) {
    case null:
      prefixes = null;
    case final List<Object?> l when l.every((e) => e is String):
      prefixes = l.whereType<String>().toIList();
    case _:
      return const Invalid('agent params', _prefixes, 'not a list of text');
  }
  return Valid(
    AgentParams(
      requireApproval: mode,
      allowedPrefixes: prefixes,
      others: {
        for (final e in json.entries)
          if (e.key != _mode && e.key != _prefixes) e.key: e.value,
      }.lock,
    ),
  );
}

/// [p] as the JSON object an update sends: every param it holds.
Map<String, Object?> agentParamsJson(AgentParams p) => {
  ...p.others.unlock,
  if (p.requireApproval case final m?) _mode: m.wire,
  if (p.allowedPrefixes case final l?) _prefixes: l.toList(),
};
