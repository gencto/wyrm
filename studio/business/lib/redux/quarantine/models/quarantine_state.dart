import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/quarantine_entry.dart';

part 'quarantine_state.freezed.dart';

@freezed
abstract class QuarantineState with _$QuarantineState {
  const factory QuarantineState({
    @Default(IMapConst({})) IMap<String, QuarantineEntry> table,
    @Default(IListConst([])) IList<String> view,
    @Default(true) bool holdUnknown,
    @Default(false) bool allowAll,
    String? selectedEntry,
  }) = _QuarantineState;
}
