import 'package:async_redux/async_redux.dart';
import 'package:models/palette_entry.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'add_block_action.dart';
import 'place_library_block_action.dart';

/// An entry of the palette placed on the canvas (spec §2, §18, §20): a
/// block type of the engine, a block of the site's library (the flow
/// copies it first), a point of the Tree tab read ([write]: written), or an
/// action of the tree. Dropped at ([x], [y]); tapped (no place), it goes a
/// step below the blocks placed before it.
class PickPaletteEntryAction extends Action {
  PickPaletteEntryAction(this.entry, {this.x, this.y, this.write = false});

  final PaletteEntry entry;
  final double? x;
  final double? y;

  /// A point dragged as `Write` (a `set` block).
  final bool write;

  @override
  AppState? reduce() {
    final d = flowEditor.draft;
    if (d == null) {
      return null;
    }
    // A tap places the next block on a diagonal of eight steps.
    final step = 60 + 30.0 * (d.blocks.length % 8);
    final px = x ?? step;
    final py = y ?? step;
    switch (entry) {
      case EnginePick(:final type):
        dispatchSync(AddBlockAction(type, px, py));
      case LibraryPick(:final name):
        // Its own read of the library block; it brings its own state.
        _start(PlaceLibraryBlockAction(name, px, py));
      case PointPick() || ActionPick():
        final action = switch (entry) {
          ActionPick(:final node, action: final name) =>
            nodes.detail[node]?.actions
                .where((a) => a.name == name)
                .firstOrNull,
          _ => null,
        };
        final made = blockOfEntry(
          entry,
          write: write,
          action: action,
          caps: flowEditor.caps,
        );
        if (made != null) {
          dispatchSync(
            AddBlockAction(
              made.type.type,
              px,
              py,
              cfg: made.cfg,
              pins: made.pins,
            ),
          );
        }
    }
    return null;
  }

  /// Starts [action] and does not wait for it: it brings its own state
  /// (and its own waiting state, where it has one).
  void _start(ReduxAction<AppState> action) => dispatch(action);
}
