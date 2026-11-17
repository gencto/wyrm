import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../charts/trend.dart';
import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'task_badge.dart';

/// How a row of [FoundCard] is marked: from the node's live value as the
/// viewer reads it, never from the model's words.
enum FoundMark {
  good,
  bad,

  /// A value of uncertain quality: drawn as [none].
  uncertain,

  /// No value read.
  none;

  /// The mark's tooltip.
  String get label => switch (this) {
    good => S.current.foundGood,
    bad => S.current.foundBad,
    uncertain => S.current.foundUncertain,
    none => S.current.foundNoValue,
  };
}

/// One row of *What I found*: a node the model read and what it says about
/// it.
final class FoundRowVm extends Equatable {
  const FoundRowVm({
    required this.label,
    required this.detail,
    required this.node,
    required this.mark,
  });

  /// The model's words, as plain text.
  final String label;
  final String detail;

  /// The node's full key.
  final String node;
  final FoundMark mark;

  String get markLabel => mark.label;

  @override
  List<Object?> get props => [label, detail, node, mark];
}

/// Why the agent link did not note findings.
enum FoundRefusal {
  rightsExpired,
  rightsUnknown,
  outsideRights,
  limit,
  invalid,
}

/// [count] findings the agent link did not note, for [why].
final class FoundMissingVm extends Equatable {
  const FoundMissingVm(this.why, this.count);

  final FoundRefusal why;
  final int count;

  String get text => switch (why) {
    FoundRefusal.rightsExpired => S.current.foundRefusedExpired('$count'),
    FoundRefusal.rightsUnknown => S.current.foundRefusedUnknown('$count'),
    FoundRefusal.outsideRights => S.current.foundRefusedOutside('$count'),
    FoundRefusal.limit => S.current.foundRefusedLimit('$count'),
    FoundRefusal.invalid => S.current.foundRefusedInvalid('$count'),
  };

  @override
  List<Object?> get props => [why, count];
}

/// One `sys/audit` record on the point: who did what, when.
final class FoundAuditVm extends Equatable {
  const FoundAuditVm({
    required this.time,
    required this.who,
    required this.op,
    required this.key,
    this.bad = false,
  });

  final DateTime time;
  final String who;
  final String op;

  /// The request key's full key.
  final String key;

  /// The call was refused.
  final bool bad;

  /// `user:ivan · invoke modbus/tcp/plc1/valve/~act/edit`.
  String get text => S.current.timelineAuditLine(who, op, shortKey(key));

  @override
  List<Object?> get props => [time, who, op, key, bad];
}

/// What the audit tail says beside its lines.
enum AuditNote {
  /// It needs `config` on `sys/audit`: nothing was read.
  needsConfig,

  /// It was read and holds nothing about the point.
  none;

  String get text => switch (this) {
    needsConfig => S.current.auditNeeds,
    none => S.current.timelineAuditNone,
  };
}

/// What [FoundCard] draws.
final class FoundCardVm extends Equatable {
  const FoundCardVm({
    this.rows = const [],
    this.missing = const [],
    this.point,
    this.range = '',
    this.timeline,
    this.audit = const [],
    this.auditNote,
  });

  final List<FoundRowVm> rows;

  /// The findings not noted, by why.
  final List<FoundMissingVm> missing;

  /// The name of the point of the timeline.
  final String? point;

  /// The range of its history (`1h`).
  final String range;

  /// The point's compact trend, without its marks: the card adds the audit
  /// records as marks.
  final TrendVm? timeline;

  /// The newest audit records first.
  final List<FoundAuditVm> audit;
  final AuditNote? auditNote;

  String get title => S.current.foundTitle;
  String get note => S.current.foundNote;
  String? get timelineLabel => switch (point) {
    final p? => S.current.timelineLabel(p, range),
    null => null,
  };
  String get auditLabel => S.current.timelineAudit;

  /// The newest five records, as lines.
  Iterable<FoundAuditVm> get auditLines => audit.take(5);

  bool get isEmpty => rows.isEmpty && missing.isEmpty && timeline == null;

  @override
  List<Object?> get props => [
    rows,
    missing,
    point,
    range,
    timeline,
    audit,
    auditNote,
  ];
}

/// [t] with each audit record as a mark, the oldest first, and the words
/// of an empty history.
TrendVm _marked(TrendVm t, List<FoundAuditVm> audit) => TrendVm(
  series: t.series,
  rangeStart: t.rangeStart,
  rangeEnd: t.rangeEnd,
  windowStart: t.windowStart,
  windowEnd: t.windowEnd,
  rollup: t.rollup,
  format: t.format,
  title: t.title,
  step: t.step,
  minWindow: t.minWindow,
  endsNow: t.endsNow,
  live: t.live,
  following: t.following,
  loading: t.loading,
  refining: t.refining,
  card: t.card,
  legend: t.legend,
  hint: t.hint,
  plotHeight: t.plotHeight,
  brush: t.brush,
  marks: [
    for (final a in audit.reversed)
      TrendMark(a.time.microsecondsSinceEpoch, a.text),
  ],
  empty: S.current.noHistory,
);

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
  final RangeChanged<int> onWindow;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: FontSizes.xs, color: c.text3);
    return Container(
      margin: Insets.assistantCard,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.line2),
        borderRadius: Radii.card,
      ),
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (vm.rows.isNotEmpty || vm.missing.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: Row(
                spacing: 6,
                children: [
                  AppIconView(
                    AppIcon.wsAssistant,
                    size: IconSizes.xs,
                    color: c.ember,
                  ),
                  Expanded(
                    child: Text(
                      vm.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: FontSizes.xs,
                        fontWeight: .w600,
                        letterSpacing: Trackings.smallLabel,
                        color: c.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                12,
                10,
                12,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 7,
                children: [for (final r in vm.rows) _row(c, r)],
              ),
            ),
            if (vm.missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  6,
                  12,
                  AppSpacing.none,
                ),
                child: Column(
                  crossAxisAlignment: .stretch,
                  spacing: 2,
                  children: [
                    for (final m in vm.missing)
                      Text(
                        m.text,
                        style: TextStyle(
                          fontSize: FontSizes.xs,
                          color: c.warn,
                        ),
                      ),
                  ],
                ),
              ),
            if (vm.rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  2,
                  12,
                  10,
                ),
                child: Text(vm.note, style: small),
              )
            else
              const SizedBox(height: 10),
          ],
          if (vm.timeline case final t?) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 6),
              decoration: BoxDecoration(
                border: vm.rows.isEmpty && vm.missing.isEmpty
                    ? null
                    : Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(vm.timelineLabel ?? '', style: small),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.none,
                12,
                AppSpacing.sm,
              ),
              child: Trend(
                vm: _marked(t, vm.audit),
                onWindow: onWindow,
                onReset: onReset,
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                12,
                AppSpacing.sm,
                12,
                10,
              ),
              decoration: BoxDecoration(
                color: c.ground2,
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 4,
                children: [
                  Text(vm.auditLabel, style: small),
                  for (final a in vm.auditLines)
                    Row(
                      crossAxisAlignment: .start,
                      spacing: 8,
                      children: [
                        Text(
                          // as the timeline says its times
                          t.format.clock(a.time),
                          style: mono(size: FontSizes.sm, color: c.text2),
                        ),
                        Expanded(
                          child: Text(
                            a.text,
                            style: mono(
                              size: FontSizes.sm,
                              color: a.bad ? c.badText : c.text2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (vm.auditNote case final n?) Text(n.text, style: small),
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
      .uncertain || .none => c.text4,
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
                  .good => AppIconView(
                    AppIcon.uiCheck,
                    size: IconSizes.xs,
                    color: color,
                  ),
                  .bad => AppIconView(
                    AppIcon.uiClose,
                    size: IconSizes.inline,
                    color: color,
                  ),
                  .uncertain || .none => Container(
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
                  style: TextStyle(fontSize: FontSizes.md, color: c.text1),
                  children: [
                    if (r.detail.isNotEmpty)
                      TextSpan(
                        text: '  ${r.detail}',
                        style: TextStyle(
                          fontSize: FontSizes.sm,
                          color: c.text2,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                shortKey(r.node),
                style: mono(size: FontSizes.xs, color: c.text4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
