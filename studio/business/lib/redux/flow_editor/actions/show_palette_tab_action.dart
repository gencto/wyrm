import 'package:models/palette_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_block_library_action.dart';

/// A tab of the palette is picked: shown at once. My blocks shows only
/// where the broker has custom blocks, and asks for the site's library each
/// time, the last step of the pick. It changes no state itself (`null`).
class ShowPaletteTabAction extends Action {
  ShowPaletteTabAction(this.tab);

  final PaletteTab tab;

  @override
  Future<AppState?> reduce() async {
    if (!(tab == PaletteTab.my && !flowEditor.caps.blocks) &&
        tab != flowEditor.palette) {
      dispatchSync(_Shown(tab));
    }
    if (tab == PaletteTab.my) {
      await dispatchAndWait(RetrieveBlockLibraryAction());
    }
    return null;
  }
}

/// The palette's tab on screen.
class _Shown extends Action {
  _Shown(this.tab);

  final PaletteTab tab;

  @override
  AppState reduce() => state.copyWith.flowEditor(palette: tab);
}
