import 'package:models/panel_slot.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The width the user dragged a side panel to. The value is stored as it
/// arrives; the panel clamps it to its own bounds when it draws.
class SetPanelWidthAction extends Action {
  SetPanelWidthAction(this.slot, this.width);

  final PanelSlot slot;
  final double width;

  @override
  AppState? reduce() {
    if (!width.isFinite || width <= 0 || panels.widths[slot] == width) {
      return null;
    }
    return state.copyWith.panels(widths: panels.widths.add(slot, width));
  }
}
