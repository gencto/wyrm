import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One segment of [PillTabs].
final class PillTabVm extends Equatable {
  const PillTabVm({required this.id, required this.label, this.dot});

  final String id;
  final String label;

  /// A 6 px dot after the label: something on that tab needs a look.
  final Tone? dot;

  @override
  List<Object?> get props => [id, label, dot];
}

/// A segmented switch in a boxed track: the System tab bar, the traffic
/// measure switch and the broker log level (boards `System`, `SystemLog`).
///
/// One of the segments is always selected. [inset] is the darker track of a
/// switch that sits inside a card; [equal] gives every segment the same
/// width; [mono] sets code names. With [disabledReason] the segments do not
/// react and the reason is the tooltip.
class PillTabs extends StatelessWidget {
  const PillTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.label,
    this.height = 34,
    this.fontSize = 13,
    this.inset = false,
    this.equal = false,
    this.mono = false,
    this.disabledReason,
    super.key,
  });

  final List<PillTabVm> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  /// What the group is, for assistive technology.
  final String? label;
  final double height;
  final double fontSize;
  final bool inset;
  final bool equal;
  final bool mono;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gap = inset ? 3.0 : 4.0;
    final track = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: inset ? c.ground3 : c.ground2,
        border: .all(color: c.line1),
        borderRadius: Radii.control,
      ),
      child: Row(
        mainAxisSize: equal ? .max : .min,
        spacing: gap,
        children: [
          for (final t in tabs)
            if (equal) Expanded(child: _segment(c, t)) else _segment(c, t),
        ],
      ),
    );
    final group = Semantics(container: true, label: label, child: track);
    return switch (disabledReason) {
      final r? => Tooltip(message: r, child: group),
      null => group,
    };
  }

  Widget _segment(AppColors c, PillTabVm t) {
    final on = t.id == selected;
    final enabled = disabledReason == null;
    final color = on ? c.text1 : (enabled ? c.text3 : c.muted);
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? c.line2 : Colors.transparent,
        borderRadius: Radii.segment,
        child: InkWell(
          onTap: enabled && !on ? () => onSelect(t.id) : null,
          borderRadius: Radii.segment,
          hoverColor: c.text1.withValues(alpha: 0.05),
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: equal ? 4 : (inset ? 10 : 12),
            ),
            child: Row(
              mainAxisSize: .min,
              spacing: 8,
              children: [
                Flexible(
                  child: Text(
                    t.label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: mono
                        ? TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: fontSize,
                            fontWeight: on ? .w600 : .w400,
                            color: color,
                          )
                        : TextStyle(fontSize: fontSize, color: color),
                  ),
                ),
                if (t.dot case final d?)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: toneColor(c, d),
                      shape: .circle,
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
