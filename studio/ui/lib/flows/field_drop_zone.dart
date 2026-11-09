import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'flow_block_view.dart';

/// A field outside the canvas (a row of the inspector) that takes a wire
/// dragged out of the canvas. The canvas follows the pointer with its own
/// events, not as a `Draggable`, so it finds a zone by a hit test of the
/// pointer's position (DGLux `field_drop.dart`).
final class FieldDrop {
  const FieldDrop(this.id, {required this.onDrop});

  /// The field's id within its block.
  final String id;

  /// Binds the field to the dragged output.
  final ValueChanged<FieldRefVm> onDrop;
}

/// The zone under the dragged wire, lit while the wire is over it.
final ValueNotifier<String?> fieldDropHover = ValueNotifier(null);

/// The zone at [global] in the view [viewId], if any.
FieldDrop? fieldDropAt(Offset global, int viewId) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, global, viewId);
  for (final e in result.path) {
    final t = e.target;
    if (t is RenderMetaData && t.metaData is FieldDrop) {
      return t.metaData as FieldDrop;
    }
  }
  return null;
}

/// Wraps a field that takes a wire dragged from the canvas; [builder] draws
/// it lit while the wire is over it.
class FieldDropZone extends StatelessWidget {
  const FieldDropZone({required this.drop, required this.builder, super.key});

  final FieldDrop drop;
  final Widget Function(BuildContext context, bool lit) builder;

  @override
  Widget build(BuildContext context) => MetaData(
    metaData: drop,
    behavior: .translucent,
    child: ValueListenableBuilder<String?>(
      valueListenable: fieldDropHover,
      builder: (context, hover, _) => builder(context, hover == drop.id),
    ),
  );
}
