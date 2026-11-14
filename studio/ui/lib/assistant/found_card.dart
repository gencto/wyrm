import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../charts/trend.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// How a row of [FoundCard] is marked: from the node's live value as the
/// viewer reads it, never from the model's words.
enum FoundMark { good, bad, none }

/// One row of *What I found*: a node the model read and what it says about
/// it.
final class FoundRowVm extends Equatable {
  const FoundRowVm({
    required this.label,
    required this.detail,
    required this.node,
    required this.mark,
    required this.markLabel,
  });

  /// The model's words (`plc1`, `4 of 5 points good`): plain text.
  final String label;
  final String detail;

  /// The node's key as shown (below the site, without `downstream/`).
  final String node;

  final FoundMark mark;

  /// What the mark says, for a screen reader and the tooltip (`good now`,
  /// `bad now`, `no value read`).
  final String markLabel;

  @override
  List<Object?> get props => [label, detail, node, mark, markLabel];
}

/// One audit record under the timeline: `03:05` and `ivan · invoke
/// …/valve/~act/edit`.
final class FoundAuditVm extends Equatable {
  const FoundAuditVm({
    required this.time,
    required this.text,
    this.bad = false,
  });

  final String time;
  final String text;

  /// The record is a refusal.
  final bool bad;

  @override
  List<Object?> get props => [time, text, bad];
}

/// What [FoundCard] draws: the rows of *What I found* (none before the
/// model noted any) and the mini timeline of the selected point with the
/// audit records on it (none without a point).
final class FoundCardVm extends Equatable {
  const FoundCardVm({
    required this.title,
    required this.note,
    this.rows = const [],
    this.timelineLabel,
    this.timeline,
    this.auditLabel = '',
    this.audit = const [],
    this.auditNote,
  });

  /// `What I found · read only`.
  final String title;

  /// Under the rows: the marks are live values, the words the model's.
  final String note;
  final List<FoundRowVm> rows;

  /// `valve · last 1h`; null: no timeline.
  final String? timelineLabel;

  /// The point's compact trend, the audit records as its marks.
  final TrendVm? timeline;

  /// `From sys/audit`.
  final String auditLabel;
  final List<FoundAuditVm> audit;

  /// Why there are no audit records (no `config` on `sys/audit`, none).
  final String? auditNote;

  bool get isEmpty => rows.isEmpty && timeline == null;

  @override
  List<Object?> get props => [
    title,
    note,
    rows,
    timelineLabel,
    timeline,
    auditLabel,
    audit,
    auditNote,
  ];
}

/// Board *AssistantDrawer*, section *What I found*: the nodes the model read,
/// each with its words as plain text and a mark from the node's live value,
/// then the mini timeline of the selected point and the audit records on it.
/// Nothing on it is a link or a button: it is read only.
class FoundCard extends StatelessWidget {
  const FoundCard({
    required this.vm,
    required this.onWindow,
    this.onReset,
    super.key,
  });

  final FoundCardVm vm;

  /// The timeline's window, as [Trend.onWindow].
  final void Function(int start, int end) onWindow;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 11, color: c.text3);
    return Container(
      margin: const EdgeInsets.only(left: 42, bottom: 12),
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.line2),
        borderRadius: Radii.card,
      ),
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (vm.rows.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: Row(
                spacing: 6,
                children: [
                  AppIcon('ws_assistant', size: 12, color: c.ember),
                  Expanded(
                    child: Text(
                      vm.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: .w600,
                        letterSpacing: 0.66,
                        color: c.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 7,
                children: [for (final r in vm.rows) _row(c, r)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Text(vm.note, style: small),
            ),
          ],
          if (vm.timeline case final t?) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
              decoration: BoxDecoration(
                border: vm.rows.isEmpty
                    ? null
                    : Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(vm.timelineLabel ?? '', style: small),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
              child: Trend(vm: t, onWindow: onWindow, onReset: onReset),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: c.ground2,
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 4,
                children: [
                  Text(vm.auditLabel, style: small),
                  for (final a in vm.audit)
                    Row(
                      crossAxisAlignment: .start,
                      spacing: 8,
                      children: [
                        Text(a.time, style: mono(size: 12, color: c.text2)),
                        Expanded(
                          child: Text(
                            a.text,
                            style: mono(
                              size: 12,
                              color: a.bad ? c.badText : c.text2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (vm.auditNote case final n?) Text(n, style: small),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(AppColors c, FoundRowVm r) {
    final color = switch (r.mark) {
      .good => c.good,
      .bad => c.bad,
      .none => c.text4,
    };
    return Row(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        Tooltip(
          message: r.markLabel,
          child: Semantics(
            label: r.markLabel,
            child: SizedBox(
              width: 14,
              height: 18,
              child: Center(
                child: switch (r.mark) {
                  .good => AppIcon('ui_check', size: 12, color: color),
                  .bad => AppIcon('ui_close', size: 11, color: color),
                  .none => Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 1,
            children: [
              // the model's words: plain text, no marks read, no links
              Text.rich(
                TextSpan(
                  text: r.label,
                  style: TextStyle(fontSize: 13, color: c.text1),
                  children: [
                    if (r.detail.isNotEmpty)
                      TextSpan(
                        text: '  ${r.detail}',
                        style: TextStyle(fontSize: 12, color: c.text2),
                      ),
                  ],
                ),
              ),
              Text(r.node, style: mono(size: 11, color: c.text4)),
            ],
          ),
        ),
      ],
    );
  }
}
