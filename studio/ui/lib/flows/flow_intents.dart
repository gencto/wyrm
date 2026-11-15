import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart' show Offset;

import 'flow_block_view.dart';
import 'shortcut_card.dart';

/// Where a palette entry is placed (spec §2, §18): one intent, carried by
/// a `ValueChanged<Place>`.
sealed class Place extends Equatable {
  const Place();
}

/// Tapped in the palette: where the editor puts a new block.
final class PlaceTapped extends Place {
  const PlaceTapped();

  @override
  List<Object?> get props => [];
}

/// Let go on the canvas at ([x], [y]) (canvas units, on the grid);
/// [write]: a writable point placed as a block that writes it.
final class PlaceOnCanvas extends Place {
  const PlaceOnCanvas(this.x, this.y, {this.write = false});

  final double x;
  final double y;
  final bool write;

  @override
  List<Object?> get props => [x, y, write];
}

/// A point let go on input [port] of block [block]: a block that reads it,
/// wired into that input.
final class PlaceOnInput extends Place {
  const PlaceOnInput(this.block, this.port);

  final String block;
  final String port;

  @override
  List<Object?> get props => [block, port];
}

// ---------- the canvas (spec §3–§5, §12–§14) ----------

/// A row of a block as the canvas draws it: the block, and the row's place
/// among its rows (0 is the first). The canvas reports a row this way; the
/// app knows which field stands there.
final class RowRef extends Equatable {
  const RowRef(this.block, this.row);

  final String block;
  final int row;

  @override
  List<Object?> get props => [block, row];
}

/// The input end of a wire: engine input [port] of block [block].
final class PortRefVm extends Equatable {
  const PortRefVm(this.block, this.port);

  final String block;
  final String port;

  @override
  List<Object?> get props => [block, port];
}

/// A wire dragged from [from] let go on input [port] of block [block]:
/// binds it.
final class WireDropped extends Equatable {
  const WireDropped(this.from, this.block, this.port);

  final FieldRefVm from;
  final String block;
  final String port;

  @override
  List<Object?> get props => [from, block, port];
}

/// The wire into [from], picked up and let go on input [to]: moves it.
final class WireMoved extends Equatable {
  const WireMoved(this.from, this.to);

  final PortRefVm from;
  final PortRefVm to;

  @override
  List<Object?> get props => [from, to];
}

/// Whether row [to] (drawn as [row]) takes a wire from [from]: the question
/// a dragged wire asks of the row it is over. [replacing] is the input a
/// picked-up wire leaves.
final class BindAsk extends Equatable {
  const BindAsk(this.from, this.to, this.row, {this.replacing});

  final FieldRefVm from;
  final RowRef to;
  final FieldRowVm row;
  final PortRefVm? replacing;

  @override
  List<Object?> get props => [from, to, row, replacing];
}

/// Blocks let go at their new top-left corners, by block id: a drag of the
/// selection, or ([nudge]) a step of the arrow keys.
final class BlocksMoved extends Equatable {
  const BlocksMoved(this.to, {required this.nudge});

  final Map<String, Offset> to;
  final bool nudge;

  @override
  List<Object?> get props => [to, nudge];
}

/// A marquee or Select all: the blocks [ids] alone, added ([add]) or
/// switched in and out ([toggle]).
final class BlocksSelected extends Equatable {
  const BlocksSelected(this.ids, {required this.add, required this.toggle});

  final Set<String> ids;
  final bool add;
  final bool toggle;

  @override
  List<Object?> get props => [ids, add, toggle];
}

/// A command the canvas does not do by itself (copy, paste, delete, undo,
/// deploy, …), from a key or from its menu; [at] is where a paste lands
/// (canvas coordinates).
final class CanvasCommand extends Equatable {
  const CanvasCommand(this.command, {this.at});

  final FlowCommand command;
  final Offset? at;

  @override
  List<Object?> get props => [command, at];
}

/// − ([add] false) or + of block [block]'s variable inputs.
final class BlockResized extends Equatable {
  const BlockResized(this.block, {required this.add});

  final String block;
  final bool add;

  @override
  List<Object?> get props => [block, add];
}
