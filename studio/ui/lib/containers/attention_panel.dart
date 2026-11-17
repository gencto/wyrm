import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// One card of the attention panel.
final class AttentionItemVm extends Equatable {
  const AttentionItemVm({
    required this.id,
    required this.title,
    required this.detail,
    required this.go,
    this.tone = Tone.warn,
  });

  /// What the composer gets back when the card is tapped.
  final String id;
  final String title;
  final String detail;

  /// Where the card leads (`Open in Links ›`).
  final String go;

  /// Bad for a failure, warn for waiting or behind, neutral for information.
  final Tone tone;

  @override
  List<Object?> get props => [id, title, detail, go, tone];
}

/// One row of the facts at the foot of the panel.
final class BrokerFactVm extends Equatable {
  const BrokerFactVm({
    required this.label,
    required this.value,
    this.mono = false,
    this.dot,
  });

  final String label;
  final String value;
  final bool mono;

  /// A 6 px dot before the value (the liveliness token: good while present).
  final Tone? dot;

  @override
  List<Object?> get props => [label, value, mono, dot];
}

/// What [AttentionPanel] draws.
final class AttentionPanelVm extends Equatable {
  const AttentionPanelVm({
    required this.heading,
    required this.note,
    required this.empty,
    required this.factsTitle,
    this.items = const [],
    this.facts = const [],
  });

  /// `Needs a look · 3`.
  final String heading;
  final String note;

  /// Shown under the heading when there is no card.
  final String empty;
  final List<AttentionItemVm> items;
  final String factsTitle;
  final List<BrokerFactVm> facts;

  @override
  List<Object?> get props => [heading, note, empty, items, factsTitle, facts];
}

/// The right panel of System, the same on every tab: what needs a look, one
/// card each, every card a link to the screen where it is fixed; the
/// broker's facts at the foot.
///
/// With [fill] the panel takes the height it is given and the facts sit at
/// its foot; without, it is as tall as its content (below the main column
/// on a narrow window).
class AttentionPanel extends StatelessWidget {
  const AttentionPanel({
    required this.vm,
    required this.onItem,
    this.fill = true,
    super.key,
  });

  final AttentionPanelVm vm;
  final ValueChanged<String> onItem;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = TextStyle(
      fontSize: FontSizes.sm,
      fontWeight: .w600,
      letterSpacing: Trackings.label,
      color: c.text4,
    );
    final head = Container(
      padding: Insets.attentionHead,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          Text(vm.heading.toUpperCase(), style: label),
          Text(
            vm.note,
            style: TextStyle(
              fontSize: FontSizes.md,
              height: LineHeights.body,
              color: c.text3,
            ),
          ),
        ],
      ),
    );
    final cards = Padding(
      padding: Insets.listPanel,
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          if (vm.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(
                vm.empty,
                style: TextStyle(fontSize: FontSizes.md, color: c.text4),
              ),
            ),
          for (final a in vm.items) _card(c, a),
        ],
      ),
    );
    final facts = Container(
      padding: Insets.attentionFacts,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Text(vm.factsTitle.toUpperCase(), style: label),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
              for (final (i, f) in vm.facts.indexed)
                TableRow(
                  children: [
                    Padding(
                      padding: i == 0
                          ? Insets.attentionLabel
                          : Insets.attentionLabelNext,
                      child: Text(
                        f.label,
                        style: TextStyle(
                          fontSize: FontSizes.md,
                          color: c.text4,
                        ),
                      ),
                    ),
                    Padding(
                      padding: i == 0 ? EdgeInsets.zero : Insets.factValueNext,
                      child: _fact(c, f),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ground1,
        border: fill
            ? Border(left: BorderSide(color: c.line1))
            : Border(top: BorderSide(color: c.line1)),
      ),
      child: fill
          ? Column(
              crossAxisAlignment: .stretch,
              children: [
                head,
                Expanded(child: SingleChildScrollView(child: cards)),
                facts,
              ],
            )
          : Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [head, cards, facts],
            ),
    );
  }

  Widget _card(AppColors c, AttentionItemVm a) => Material(
    color: c.ground2,
    shape: RoundedRectangleBorder(
      borderRadius: Radii.control,
      side: BorderSide(color: c.line1),
    ),
    clipBehavior: .antiAlias,
    child: InkWell(
      onTap: () => onItem(a.id),
      hoverColor: c.text1.withValues(alpha: 0.04),
      child: Padding(
        padding: Insets.smallCard,
        child: Row(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: Insets.rowDot,
              decoration: BoxDecoration(
                color: toneColor(c, a.tone),
                shape: .circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 3,
                children: [
                  Text(
                    a.title,
                    style: TextStyle(
                      fontSize: FontSizes.md,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  if (a.detail.isNotEmpty)
                    Text(
                      a.detail,
                      maxLines: 4,
                      overflow: .ellipsis,
                      style: TextStyle(
                        fontSize: FontSizes.sm,
                        height: LineHeights.row,
                        color: c.text3,
                      ),
                    ),
                  Text(
                    a.go,
                    style: TextStyle(
                      fontSize: FontSizes.sm,
                      color: c.emberSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _fact(AppColors c, BrokerFactVm f) {
    final text = Text(
      f.value,
      maxLines: 1,
      overflow: .ellipsis,
      style: f.mono
          ? TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: FontSizes.md,
              color: f.dot == null ? c.text1 : c.text2,
            )
          : TextStyle(fontSize: FontSizes.md, color: c.text1),
    );
    final dot = f.dot;
    if (dot == null) {
      return text;
    }
    return Row(
      spacing: 6,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: toneColor(c, dot),
            shape: .circle,
          ),
        ),
        Flexible(child: text),
      ],
    );
  }
}
