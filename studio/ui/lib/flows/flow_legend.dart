import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';

/// The words of the canvas legend (spec §5).
final class FlowLegendVm extends Equatable {
  const FlowLegendVm({
    required this.reads,
    required this.writes,
    required this.free,
    required this.readOnly,
  });

  /// `reads a value` (teal line).
  final String reads;

  /// `writes to a device` (ember line).
  final String writes;

  /// `free field` (grey ring).
  final String free;

  /// `no left port = read-only point`.
  final String readOnly;

  @override
  List<Object?> get props => [reads, writes, free, readOnly];
}

/// The legend pinned bottom-left over the flow canvas: what a teal and an
/// ember wire mean, what a grey ring is, and what a missing left port says.
class FlowLegend extends StatelessWidget {
  const FlowLegend({required this.vm, super.key});

  final FlowLegendVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontSize: 12, color: c.text3);
    Widget line(Color color, String label) => Row(
      mainAxisSize: .min,
      spacing: 6,
      children: [
        Container(width: 18, height: 2, color: color),
        Text(label, style: style),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.ground1.withValues(alpha: 0.92),
        border: .all(color: c.line1),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: .center,
        children: [
          line(c.good, vm.reads),
          line(c.ember, vm.writes),
          Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: .circle,
                  border: .all(color: c.muted, width: 2),
                ),
              ),
              Text(vm.free, style: style),
            ],
          ),
          Text(vm.readOnly, style: style),
        ],
      ),
    );
  }
}
