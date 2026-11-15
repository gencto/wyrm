import 'package:async_redux/async_redux.dart';
import 'package:models/palette_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_block_library_action.dart';

/// A tab of the palette is picked. My blocks shows only where the broker
/// has custom blocks, and asks for the site's library each time.
class ShowPaletteTabAction extends Action {
  ShowPaletteTabAction(this.tab);

  final PaletteTab tab;

  @override
  AppState? reduce() {
    if (tab == PaletteTab.my) {
      // Its own read; it brings its own state.
      _start(RetrieveBlockLibraryAction());
    }
    if ((tab == PaletteTab.my && !flowEditor.caps.blocks) ||
        tab == flowEditor.palette) {
      return null;
    }
    return state.copyWith.flowEditor(palette: tab);
  }

  /// Starts [action] and does not wait for it: it brings its own state
  /// (and its own waiting state, where it has one).
  void _start(ReduxAction<AppState> action) => dispatch(action);
}
