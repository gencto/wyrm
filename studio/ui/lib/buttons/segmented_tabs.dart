import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

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
    this.disabledReason,
  });

  final String id;
  final String label;
  final String? count;

  /// A tone for the count (Quarantine's waiting count is amber).
  final Tone countTone;

  /// Shown, not selectable, with this tooltip (docs/studio.md §2 rule 8).
  final String? disabledReason;

  @override
  List<Object?> get props => [id, label, count, countTone, disabledReason];
}

/// The underlined tab bar of the workspaces and inspectors: 40 high, the
/// current tab in text/1 with a 2 px ember line, the others in text/3.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.plainCounts = false,
    this.height = 40,
    this.equal = false,
    super.key,
  });

  final List<TabItemVm> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  /// Counts as plain 12 text after the label, not pills (Explorer's device
  /// tabs, docs/design/specs/explorer.md §3.3).
  final bool plainCounts;
  final double height;

  /// Equal columns over the whole width, labels 13 (the flow palette).
  final bool equal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line1)),
      ),
      child: equal
          ? Row(
              children: [
                for (final t in tabs) Expanded(child: _tab(context, t)),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: .horizontal,
              child: Row(
                spacing: 4,
                children: [for (final t in tabs) _tab(context, t)],
              ),
            ),
    );
  }

  Widget _tab(BuildContext context, TabItemVm t) {
    final c = context.colors;
    final tab = InkWell(
      onTap: t.disabledReason == null ? () => onSelect(t.id) : null,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: equal ? 4 : (plainCounts ? 14 : 12),
        ),
        alignment: equal ? Alignment.center : null,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: t.id == selected ? c.ember : Colors.transparent,
              width: 2,
            ),
          ),
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
                style: TextStyle(
                  fontSize: equal ? 13 : 14,
                  fontWeight: t.id == selected ? .w500 : .w400,
                  color: t.disabledReason != null
                      ? c.muted
                      : (t.id == selected ? c.text1 : c.text3),
                ),
              ),
            ),
            if (t.count case final n? when plainCounts)
              Text(n, style: TextStyle(fontSize: 12, color: c.text3))
            else if (t.count case final n?)
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
    );
    return switch (t.disabledReason) {
      final r? => Tooltip(message: r, child: tab),
      null => tab,
    };
  }
}
