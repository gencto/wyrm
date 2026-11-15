import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_config.dart';
import 'package:models/approval_mode.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

/// The agent link's root `cfg` (its `~meta`) as an [AgentConfig]: the
/// settings *What it may do* shows. A setting that is absent is null; one
/// of another type, or a mode the agent link does not have, is [Invalid]
/// with its name.
Decoded<AgentConfig> agentConfigOf(Map<String, Value> cfg) {
  try {
    final m = WireMap.of(VMap(cfg), 'agent cfg');
    return Valid(
      AgentConfig(
        model: m.strOrNull('model'),
        approval: m.nameOrNull('require_approval', ApprovalMode.values),
        prefixes: m.stringsOr('allowed_prefixes').lock,
        budgetTokensDay: m.integerOrNull('budget_tokens_day'),
        apiKeyRef: m.strOrNull('api_key_ref'),
        apiBase: m.strOrNull('api_base'),
      ),
    );
  } on DecodeError catch (e) {
    return Invalid('agent cfg', e.path, 'expected ${e.expected}, got ${e.got}');
  }
}

/// The names of the agent link's secrets (`sys/links/<id>` ▸ `secrets`):
/// a list of names, never a value.
Decoded<ISet<String>> secretNamesOf(Value v) => switch (v) {
  VArray(:final v) when v.every((n) => n is VStr) => Valid(
    {
      for (final n in v.whereType<VStr>()) n.v,
    }.lock,
  ),
  VArray() => const Invalid('agent secrets', '', 'a name that is not text'),
  _ => const Invalid('agent secrets', '', 'not a list'),
};
