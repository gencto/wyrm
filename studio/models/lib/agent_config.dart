import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'approval_mode.dart';

part 'agent_config.freezed.dart';

/// What the agent link may do, as its root `cfg` says (docs/studio.md
/// §7.8): the settings *What it may do* shows. Whether the API key is set
/// is not in it (the secret's names are read apart, with `config`).
@freezed
abstract class AgentConfig with _$AgentConfig {
  const factory AgentConfig({
    /// The model the agent asks (`model`).
    String? model,

    /// Who approves a plan (`require_approval`); null when not set.
    ApprovalMode? approval,

    /// Where it may propose changes (`allowed_prefixes`).
    @Default(IListConst([])) IList<String> prefixes,

    /// Its daily budget of LLM tokens (`budget_tokens_day`).
    int? budgetTokensDay,

    /// The name of the secret that holds its API key (`api_key_ref`).
    String? apiKeyRef,

    /// Where its requests go (`api_base`).
    String? apiBase,
  }) = _AgentConfig;

  const AgentConfig._();

  /// The host [apiBase] names, or [apiBase] itself when it names none:
  /// *Sent to*.
  String? get sentTo => switch (apiBase) {
    null => null,
    final b => switch (Uri.tryParse(b)?.host) {
      final h? when h.isNotEmpty => h,
      _ => b,
    },
  };
}
