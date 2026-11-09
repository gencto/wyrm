import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/panel_slot.dart';

part 'panels_state.freezed.dart';

@freezed
abstract class PanelsState with _$PanelsState {
  const factory PanelsState({
    @Default(IMapConst<PanelSlot, double>({})) IMap<PanelSlot, double> widths,
  }) = _PanelsState;
}
