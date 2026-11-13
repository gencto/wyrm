import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// What [ViewLamp] draws: a label, the word of its state, the state.
final class ViewLampVm extends Equatable {
  const ViewLampVm({
    required this.label,
    required this.text,
    this.state = ViewState.off,
  });

  final String label;

  /// `open`, `closed`, `warm`; empty for a lamp without words.
  final String text;
  final ViewState state;

  @override
  List<Object?> get props => [label, text, state];
}

/// The `Lamp` part of a view: a two-state point as a mark and a word. On
/// is a filled dot, off an empty ring, so the two read without colour.
class ViewLamp extends StatelessWidget {
  const ViewLamp({required this.vm, super.key});

  final ViewLampVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ViewScope.densityOf(context);
    final color = vm.state.of(c);
    final lit = vm.state != .off && vm.state != .normal;
    final dot = d.label * 0.9;
    return Row(
      mainAxisSize: .min,
      spacing: 10,
      children: [
        Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            shape: .circle,
            color: lit ? color : null,
            border: .all(color: lit ? color : c.muted, width: 1.5),
          ),
        ),
        Flexible(
          child: Text(
            vm.label,
            maxLines: 1,
            overflow: .ellipsis,
            style: boardText(size: d.label, color: c.text2),
          ),
        ),
        if (vm.text.isNotEmpty)
          Text(
            vm.text,
            style: boardText(size: d.label, weight: .w500, color: color),
          ),
      ],
    );
  }
}
