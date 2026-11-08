import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/panel_slot.dart';
import 'package:ui/containers/side_panels.dart';

/// The two side panels of one workspace, as slots of `PanelsState.widths`:
/// the connector reads them through `panels.widths` and stores a change with
/// `SetPanelWidthAction(<workspace>.slot(side), width)`.
final class WorkspacePanels {
  const WorkspacePanels(this.left, this.right);

  static const explorer = WorkspacePanels(
    PanelSlot.explorerTree,
    PanelSlot.explorerInspector,
  );
  static const flowEditor = WorkspacePanels(
    PanelSlot.flowPalette,
    PanelSlot.flowInspector,
  );
  static const history = WorkspacePanels(
    PanelSlot.historyGroups,
    PanelSlot.historyInspector,
  );

  final PanelSlot left;
  final PanelSlot right;

  /// The stored widths; a panel with none draws its default.
  SidePanelWidths widths(IMap<PanelSlot, double> stored) =>
      SidePanelWidths(left: stored[left], right: stored[right]);

  /// The slot of one side.
  PanelSlot slot(PanelSide side) => side == .left ? left : right;
}
