import 'package:material_ui/material_ui.dart';

/// The regions a screen is made of, as a failure names them.
enum FaultPanel {
  /// The tree of a workspace.
  tree,

  /// The inspector on the right.
  inspector,

  /// The canvas of the flow editor.
  canvas,

  /// A drawer over the right side (Problems, Review and apply).
  drawer,

  /// The workspace of a tab.
  workspace,
}

/// Names a region of a screen (the tree, the inspector, the editor canvas,
/// a drawer) for the card drawn when something inside it throws while
/// building (`PanelFault`, docs/design/specs/errors.md §5), and gives that
/// card its *Draw it again*: the boundary keys its [child] and bumps the
/// key, so only this subtree is built anew, with new state.
///
/// It adds no chrome and no layout of its own.
class FaultBoundary extends StatefulWidget {
  const FaultBoundary({required this.panel, required this.child, super.key});

  /// Which region this is; the card says it in the user's language (`The
  /// inspector could not be drawn`).
  final FaultPanel panel;

  final Widget child;

  /// The nearest boundary above [context], or null.
  static FaultBoundaryScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FaultBoundaryScope>();

  @override
  State<FaultBoundary> createState() => _FaultBoundaryState();
}

class _FaultBoundaryState extends State<FaultBoundary> {
  var _turn = 0;

  @override
  Widget build(BuildContext context) => FaultBoundaryScope(
    panel: widget.panel,
    redraw: () => setState(() => _turn++),
    child: KeyedSubtree(key: ValueKey(_turn), child: widget.child),
  );
}

/// What a [FaultBoundary] tells the widgets below it.
class FaultBoundaryScope extends InheritedWidget {
  const FaultBoundaryScope({
    required this.panel,
    required this.redraw,
    required super.child,
    super.key,
  });

  final FaultPanel panel;

  /// Builds the boundary's subtree again from nothing.
  final VoidCallback redraw;

  @override
  bool updateShouldNotify(FaultBoundaryScope oldWidget) =>
      panel != oldWidget.panel;
}
