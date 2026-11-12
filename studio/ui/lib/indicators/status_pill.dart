import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import 'quality_mark.dart';

/// A state as a pill: a mark and a word on the tone's tint.
final class StatusPillVm extends Equatable {
  const StatusPillVm({
    required this.label,
    required this.tone,
    this.mark = Mark.dot,
  });

  final String label;
  final Tone tone;
  final Mark mark;

  @override
  List<Object?> get props => [label, tone, mark];
}

/// Board *Design system* §05 value quality: 28 high, radius 14, 13 px;
/// [dense] is the 22 px pill of a page header (`Connected`).
class StatusPill extends StatelessWidget {
  const StatusPill({required this.vm, this.dense = false, super.key});

  final StatusPillVm vm;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = vm.tone == .neutral ? c.text3 : toneColor(c, vm.tone);
    return Container(
      height: dense ? 22 : 28,
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12),
      decoration: BoxDecoration(
        color: toneTint(c, vm.tone),
        borderRadius: Radii.pill,
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: dense ? 6 : 8,
        children: [
          StateMark(mark: vm.mark, color: fg, size: dense ? 6 : 8),
          Text(
            vm.label,
            style: TextStyle(
              fontSize: dense ? 12 : 13,
              fontWeight: dense ? .w500 : .w400,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
