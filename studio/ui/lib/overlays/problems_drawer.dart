import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/shades.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// One failure in the Problems drawer.
final class ProblemVm extends Equatable {
  const ProblemVm({
    required this.id,
    required this.title,
    required this.time,
    this.tone = Tone.warn,
    this.where = '',
    this.said = '',
    this.retry = false,
    this.shown = false,
  });

  final int id;

  /// `warn` (rights, reach), `neutral` (busy, gone), `bad` (broker, studio):
  /// the colour of the dot.
  final Tone tone;
  final String title;

  /// `11:52:06`.
  final String time;

  /// The key and the call, in mono.
  final String where;

  /// `timeout: the device did not answer within 2 s.`
  final String said;

  /// It has a *Try again* link.
  final bool retry;

  /// It was opened as a dialog: the card says so and is drawn quieter.
  final bool shown;

  @override
  List<Object?> get props => [id, tone, title, time, where, said, retry, shown];
}

/// The words of the drawer, localized by the connector.
final class ProblemsLabels {
  const ProblemsLabels({
    this.title = 'Problems · this session',
    this.clear = 'Clear all',
    this.close = 'Close problems',
    this.note =
        'Failures of things Studio did on its own (reads, refreshes, live '
        'values) and every dialog you closed. Kept until Studio quits; '
        'newest first.',
    this.empty = 'No problems in this session.',
    this.details = 'Details',
    this.retry = 'Try again',
    this.shown = 'shown as a dialog',
  });

  final String title;
  final String clear;
  final String close;
  final String note;
  final String empty;
  final String details;
  final String retry;
  final String shown;
}

/// The Problems drawer (board `ErrorProblems`,
/// docs/design/specs/errors.md §4): 400 wide on the right, every failure of
/// this session, newest first, with *Details* and, where the call can be
/// repeated, *Try again*.
class ProblemsDrawer extends StatelessWidget {
  const ProblemsDrawer({
    required this.problems,
    required this.onClose,
    required this.onClear,
    required this.onDetails,
    required this.onRetry,
    this.labels = const ProblemsLabels(),
    super.key,
  });

  /// Newest first.
  final List<ProblemVm> problems;
  final VoidCallback onClose;
  final VoidCallback onClear;
  final ValueChanged<int> onDetails;
  final ValueChanged<int> onRetry;
  final ProblemsLabels labels;

  static const width = 400.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: labels.title,
      child: Material(
        type: .transparency,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: c.ground1,
            border: Border(left: BorderSide(color: c.line1)),
            boxShadow: const [
              BoxShadow(
                color: Shades.drawerShadow,
                offset: Offset(-24, 0),
                blurRadius: 48,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              Container(
                padding: Insets.problemsHead,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line1)),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: Text(
                        labels.title,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: boardText(
                          size: FontSizes.sectionTitle,
                          weight: .w600,
                          color: c.text1,
                        ),
                      ),
                    ),
                    InkWell(
                      key: const ValueKey('problems-clear'),
                      onTap: problems.isEmpty ? null : onClear,
                      borderRadius: Radii.segment,
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
                        decoration: BoxDecoration(
                          border: .all(color: c.line2),
                          borderRadius: Radii.segment,
                        ),
                        alignment: .center,
                        child: Text(
                          labels.clear,
                          style: boardText(
                            size: FontSizes.sm,
                            color: problems.isEmpty ? c.muted : c.text3,
                          ),
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: labels.close,
                      child: InkWell(
                        key: const ValueKey('problems-close'),
                        onTap: onClose,
                        borderRadius: Radii.segment,
                        child: SizedBox.square(
                          dimension: AppSizes.problemsClose,
                          child: Center(
                            child: AppIconView(
                              AppIcon.errClose,
                              size: IconSizes.sm,
                              color: c.text4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: Insets.problemsLabel,
                child: Text(
                  labels.note,
                  style: boardText(
                    size: FontSizes.sm,
                    height: LineHeights.body,
                    color: c.text4,
                  ),
                ),
              ),
              Expanded(
                child: problems.isEmpty
                    ? Padding(
                        padding: Insets.emptyNote,
                        child: Text(
                          labels.empty,
                          style: boardText(size: FontSizes.md, color: c.text3),
                        ),
                      )
                    : ListView.separated(
                        padding: Insets.problemsList,
                        itemCount: problems.length,
                        separatorBuilder: (_, _) => Gaps.sm,
                        itemBuilder: (context, i) => _card(c, problems[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(AppColors c, ProblemVm p) {
    final dot = switch (p.tone) {
      .bad => c.bad,
      .neutral => c.text4,
      .good => c.good,
      .ember => c.emberSoft,
      .warn => c.warn,
    };
    Widget link(String label, VoidCallback onTap, Key key) => InkWell(
      key: key,
      onTap: onTap,
      child: Text(
        label,
        style: boardText(size: FontSizes.sm, color: c.emberSoft).copyWith(
          decoration: .underline,
          decorationColor: c.emberSoft,
        ),
      ),
    );
    return Opacity(
      // One already seen as a dialog, or a grey one, is drawn quieter.
      opacity: p.shown || p.tone == .neutral ? 0.72 : 1,
      child: Container(
        key: ValueKey('problem-${p.id}'),
        padding: Insets.box,
        decoration: BoxDecoration(
          color: c.ground2,
          border: .all(color: c.line1),
          borderRadius: Radii.control,
        ),
        child: Row(
          crossAxisAlignment: .start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: Insets.problemDot,
              decoration: BoxDecoration(color: dot, shape: .circle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Row(
                    crossAxisAlignment: .baseline,
                    textBaseline: .alphabetic,
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Text(
                          p.title,
                          style: boardText(
                            size: FontSizes.md,
                            weight: .w600,
                            color: c.text1,
                          ),
                        ),
                      ),
                      Text(
                        p.time,
                        style: boardText(size: FontSizes.xs, color: c.text4),
                      ),
                    ],
                  ),
                  if (p.where.isNotEmpty)
                    Text(
                      p.where,
                      style: boardText(
                        size: FontSizes.xs,
                        color: c.text4,
                        code: true,
                      ),
                    ),
                  if (p.said.isNotEmpty)
                    Text(
                      p.said,
                      maxLines: 4,
                      overflow: .ellipsis,
                      style: boardText(
                        size: FontSizes.sm,
                        height: LineHeights.row,
                        color: c.text3,
                      ),
                    ),
                  Padding(
                    padding: Insets.messageLinks,
                    child: Wrap(
                      spacing: 14,
                      children: [
                        link(
                          labels.details,
                          () => onDetails(p.id),
                          ValueKey('problem-details-${p.id}'),
                        ),
                        if (p.retry)
                          link(
                            labels.retry,
                            () => onRetry(p.id),
                            ValueKey('problem-retry-${p.id}'),
                          ),
                        if (p.shown)
                          Text(
                            labels.shown,
                            style: boardText(
                              size: FontSizes.sm,
                              color: c.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
