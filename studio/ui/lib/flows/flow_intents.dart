import 'package:equatable/equatable.dart';

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
