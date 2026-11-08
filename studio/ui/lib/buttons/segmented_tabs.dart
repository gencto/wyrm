import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';

/// One tab: a label and an optional count.
final class TabItemVm extends Equatable {
  const TabItemVm({
    required this.id,
    required this.label,
    this.count,
    this.countTone = Tone.neutral,
  });

  final String id;
  final String label;
  final String? count;

  /// A tone for the count (Quarantine's waiting count is amber).
  final Tone countTone;

  @override
  List<Object?> get props => [id, label, count, countTone];
}

/// The underlined tab bar of the workspaces and inspectors: 40 high, the
/// current tab in text/1 with a 2 px ember line, the others in text/3.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<TabItemVm> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: .horizontal,
        child: Row(
          spacing: 4,
          children: [
            for (final t in tabs)
              InkWell(
                onTap: () => onSelect(t.id),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: t.id == selected ? c.ember : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: t.id == selected ? .w500 : .w400,
                          color: t.id == selected ? c.text1 : c.text3,
                        ),
                      ),
                      if (t.count case final n?)
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: t.countTone == .neutral
                                ? c.ground4
                                : toneTint(c, t.countTone),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              n,
                              style: TextStyle(
                                fontSize: 12,
                                color: t.countTone == .neutral
                                    ? c.text3
                                    : toneColor(c, t.countTone),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
