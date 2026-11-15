import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'approval_mode.dart';

part 'agent_params.freezed.dart';

/// The params of the agent link as an update stages them (`sys/links/<id>`
/// ▸ `update {params}`): the two that *What it may do* edits, typed, and
/// every other param kept as the link has it. An update replaces the whole
/// params of a link, so the others go back unchanged.
@freezed
abstract class AgentParams with _$AgentParams {
  const factory AgentParams({
    /// `require_approval`; null when the params do not set it.
    ApprovalMode? requireApproval,

    /// `allowed_prefixes`; null when the params do not set it.
    IList<String>? allowedPrefixes,

    /// Every other param, as the link has it (plain JSON values: the screen
    /// shows and edits none of them).
    @Default(IMapConst({})) IMap<String, Object?> others,
  }) = _AgentParams;
}
