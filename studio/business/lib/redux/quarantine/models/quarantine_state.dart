import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/param_spec.dart';
import 'package:models/quarantine_entry.dart';

part 'quarantine_state.freezed.dart';

@freezed
abstract class QuarantineState with _$QuarantineState {
  const factory QuarantineState({
    @Default(IMapConst({})) IMap<String, QuarantineEntry> table,
    @Default(IListConst([])) IList<String> view,
    String? selectedEntry,
    @Default(IMapConst({})) IMap<String, IList<ParamSpec>> forms,
  }) = _QuarantineState;
}
