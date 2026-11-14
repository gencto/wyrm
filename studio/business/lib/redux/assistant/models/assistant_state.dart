import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/audit_entry.dart';

part 'assistant_state.freezed.dart';

@freezed
abstract class AssistantState with _$AssistantState {
  const factory AssistantState({
    String? draft,
    @Default('task') String panel,
    String? agent,
    @Default(IMapConst({})) IMap<String, String> cfg,
    @Default(true) bool docs,
    @Default(IMapConst({})) IMap<String, ISet<int>> unticked,
    @Default(IMapConst({})) IMap<String, String> refusals,
    @Default(IMapConst({})) IMap<String, ISet<String>> picks,
    @Default(false) bool shown,
    @Default(IListConst([])) IList<String> watched,
    @Default(IMapConst({})) IMap<String, ISet<String>> rowPicks,
    @Default(IListConst([])) IList<String> chips,
    @Default(IMapConst({})) IMap<String, ISet<int>> revealed,
    @Default(false) bool drawer,
    @Default(IListConst([])) IList<String> prefixes,
    ISet<String>? secrets,
    String? timelineKey,
    @Default(IListConst([])) IList<AuditEntry> timelineAudit,
  }) = _AssistantState;
}
