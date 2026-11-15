import '../containers/side_panels.dart';

/// The side panel [side] was dragged to [width] (logical pixels).
typedef PanelResized = void Function(PanelSide side, double width);

/// What [PanelResized] reports, as one value: a view-model's callback
/// takes a `ValueChanged<PanelWidth>`.
final class PanelWidth {
  const PanelWidth(this.side, this.width);

  final PanelSide side;
  final double width;
}
