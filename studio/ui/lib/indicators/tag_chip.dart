import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'quality_mark.dart';

/// A small tag: a run mode (`Process`), a count, a role (`IN`, `OUT`).
final class TagChipVm extends Equatable {
  const TagChipVm({
    required this.label,
    this.tone = Tone.neutral,
    this.monospace = false,
  });

  final String label;

  /// Neutral is ground/4 with text/2; a tone uses its tint and colour.
  final Tone tone;
  final bool monospace;

  @override
  List<Object?> get props => [label, tone, monospace];
}

/// 22 high, radius 4, 12 px (board *Design system* §05 run mode).
class TagChip extends StatelessWidget {
  const TagChip({required this.vm, super.key});

  final TagChipVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final neutral = vm.tone == .neutral;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: .center,
      decoration: BoxDecoration(
        color: neutral ? c.ground4 : toneTint(c, vm.tone),
        borderRadius: Radii.chip,
      ),
      child: Text(
        vm.label,
        style: vm.monospace
            ? mono(
                size: 11,
                weight: .w600,
                color: neutral ? c.text2 : toneColor(c, vm.tone),
              )
            : TextStyle(
                fontSize: 12,
                color: neutral ? c.text2 : toneColor(c, vm.tone),
              ),
      ),
    );
  }
}
