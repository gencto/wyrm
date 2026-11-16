import 'package:async_redux/async_redux.dart';

import '../../../wyrm/flow_view/palette_view.dart' show MyBlockItem;
import '../../app_state.dart';
import '../../common/action.dart';
import 'enter_block_action.dart';
import 'remove_custom_block_action.dart';
import 'remove_library_block_action.dart';
import 'save_block_to_library_action.dart';
import 'update_block_from_library_action.dart';

/// An item of the context menu of a My blocks entry [name] (spec §20).
/// `Rename` asks the new name first and is `RenameCustomBlockAction`.
class PaletteMenuAction extends Action {
  PaletteMenuAction(this.name, this.item);

  final String name;
  final MyBlockItem item;

  @override
  AppState? reduce() {
    switch (item) {
      case MyBlockItem.edit:
        dispatchSync(EnterBlockAction(name));
      // The library's own calls; each brings its own state.
      case MyBlockItem.save:
        _start(SaveBlockToLibraryAction(name));
      case MyBlockItem.update:
        _start(UpdateBlockFromLibraryAction(name));
      case MyBlockItem.delete:
        dispatchSync(RemoveCustomBlockAction(name));
      case MyBlockItem.removeLibrary:
        _start(RemoveLibraryBlockAction(name));
      case MyBlockItem.rename:
        break;
    }
    return null;
  }

  /// Starts [action] and does not wait for it: it brings its own state
  /// (and its own waiting state, where it has one).
  void _start(ReduxAction<AppState> action) => dispatch(action);
}
