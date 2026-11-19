import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/agent_config.dart';
import 'package:models/approval_refusal.dart';
import 'package:models/assistant_panel.dart';
import 'package:models/audit_entry.dart';

part 'assistant_state.freezed.dart';

@freezed
abstract class AssistantState with _$AssistantState {
  const factory AssistantState({
    String? draft,
    @Default(AssistantPanel.task) AssistantPanel panel,
    String? agent,

    /// What the agent may do, from its root `cfg`; null until it is read
    /// (or when its meta is not readable).
    AgentConfig? config,

    /// The agent's `cfg` was read and is not one Studio reads (a setting of
    /// another type, a mode the link does not have): what it may do, and
    /// so who approves, is not known.
    @Default(false) bool configInvalid,
    @Default(true) bool docs,
    @Default(IMapConst({})) IMap<String, ISet<int>> unticked,
    @Default(IMapConst({})) IMap<String, ApprovalRefusal> refusals,
    @Default(IMapConst({})) IMap<String, ISet<String>> picks,
    @Default(false) bool shown,
    @Default(IListConst([])) IList<String> watched,
    @Default(IMapConst({})) IMap<String, ISet<String>> rowPicks,
    @Default(IListConst([])) IList<String> chips,
    @Default(IMapConst({})) IMap<String, ISet<int>> revealed,
    @Default(false) bool drawer,

    /// The finding nodes the drawer watches while it is shown (its own
    /// readers, apart from [watched]); empty while it is hidden.
    @Default(IListConst([])) IList<String> drawerWatched,

    /// The drawer is on screen (Explorer's tab active, the drawer open).
    @Default(false) bool drawerShown,
    ISet<String>? secrets,
    String? timelineKey,
    @Default(IListConst([])) IList<AuditEntry> timelineAudit,
  }) = _AssistantState;
}
