import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One option of a choice drawn as a card (the source, the broker, the run
/// mode).
final class ChoiceCardVm extends Equatable {
  const ChoiceCardVm({
    required this.id,
    required this.title,
    this.badge,
    this.detail,
    this.note,
    this.noteTone = Tone.good,
    this.selected = false,
    this.refused,
    this.monoTitle = false,
    this.dot = false,
    this.radio = false,
  });

  final String id;
  final String title;

  /// Grey text beside the title (`this broker`).
  final String? badge;

  /// One line under the title (mono when [monoTitle]).
  final String? detail;

  /// A line in [noteTone] at the bottom.
  final String? note;
  final Tone noteTone;
  final bool selected;

  /// Why it cannot be picked; the card is dimmed and says it.
  final String? refused;
  final bool monoTitle;

  /// A state dot before the title.
  final bool dot;

  /// A radio ring before the title.
  final bool radio;

  @override
  List<Object?> get props => [
    id,
    title,
    badge,
    detail,
    note,
    noteTone,
    selected,
    refused,
    monoTitle,
    dot,
    radio,
  ];
}

/// Selected: a 1.5 px ember border on the ember fill.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({required this.vm, this.onTap, super.key});

  final ChoiceCardVm vm;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final off = vm.refused != null;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: Material(
        color: vm.selected ? c.emberFill : c.ground2,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(
            color: vm.selected ? c.ember : c.line1,
            width: vm.selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: off || onTap == null ? null : () => onTap!(vm.id),
          borderRadius: Radii.card,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 4,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    if (vm.radio)
                      StateMark(
                        mark: vm.selected ? Mark.dot : Mark.ring,
                        color: vm.selected ? c.ember : c.text4,
                        size: 12,
                      ),
                    if (vm.dot)
                      StateMark(mark: Mark.dot, color: off ? c.muted : c.good),
                    Flexible(
                      child: Text(
                        vm.title,
                        style: vm.monoTitle
                            ? mono(size: 15, weight: .w600, color: c.text1)
                            : TextStyle(
                                fontSize: 16,
                                fontWeight: .w600,
                                color: c.text1,
                              ),
                      ),
                    ),
                    if (vm.badge case final b?)
                      Text(b, style: TextStyle(fontSize: 12, color: c.text4)),
                  ],
                ),
                if (vm.detail case final d?)
                  Text(
                    d,
                    style: vm.monoTitle
                        ? mono(size: 12, color: c.text4)
                        : TextStyle(fontSize: 13, height: 1.45, color: c.text3),
                  ),
                if (vm.refused ?? vm.note case final n?)
                  Text(
                    n,
                    style: TextStyle(
                      fontSize: 12,
                      color: off ? c.text3 : toneColor(c, vm.noteTone),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
