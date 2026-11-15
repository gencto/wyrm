import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/section_label.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'task_badge.dart';

/// Where a step of a run stands.
enum RunStatus {
  /// The run has not reached it yet.
  waiting,

  /// It runs now.
  running,
  ok,
  failed,
  skipped,
}

/// One row of [RunCard]: a step and what the run did with it.
final class RunRowVm extends Equatable {
  const RunRowVm({
    required this.n,
    required this.verb,
    required this.status,
    this.action,
    this.node = '',
    this.sleep,
    this.answer = '',
    this.ended = false,
  });

  /// The step's number in the plan, from 1.
  final int n;
  final StepVerb verb;
  final String? action;

  /// The node's full key; empty for a sleep.
  final String node;

  /// A sleep: how long, in seconds.
  final double? sleep;
  final RunStatus status;

  /// The answer of the step, why it failed or was skipped (`ok`, `failed`
  /// or `skipped`); empty when the link said nothing.
  final String answer;

  /// The run is over: a step it did not reach was not run.
  final bool ended;

  /// `INVOKE add_device modbus/tcp-line2`.
  String get step => [
    verb.label,
    ?action,
    switch (sleep) {
      final s? => S.current.planSleep(plainNumber(s)),
      null => belowSection(node),
    },
  ].join(' ');

  /// `running…`, the answer of the step, `waiting`, `not run`.
  String get text => switch (status) {
    // the link's own word when it said nothing more
    RunStatus.ok => answer.isEmpty ? StepOutcome.ok.word : answer,
    RunStatus.failed => answer.isEmpty ? StepOutcome.failed.word : answer,
    RunStatus.skipped => answer.isEmpty ? StepOutcome.skipped.word : answer,
    RunStatus.running => S.current.runRunning,
    RunStatus.waiting => ended ? S.current.runNotRun : S.current.runWaiting,
  };

  @override
  List<Object?> get props => [
    n,
    verb,
    action,
    node,
    sleep,
    status,
    answer,
    ended,
  ];
}

/// What [RunCard] draws.
final class RunCardVm extends Equatable {
  const RunCardVm({
    required this.badge,
    required this.rows,
    this.step = 0,
    this.leftOut = const [],
    this.kept = const [],
    this.seconds = 0,
  });

  /// Where the task stands.
  final TaskBadge badge;
  final List<RunRowVm> rows;

  /// The step the run is at (0 before it starts).
  final int step;

  /// The steps the run left out.
  final List<int> leftOut;

  /// The steps that changed something and ended `ok`: they stay done.
  final List<int> kept;

  /// How long the run took, first step to last.
  final int seconds;

  /// `Run · step 2 of 5`, `Run · 5 steps`.
  String get title => badge == TaskBadge.running && step > 0
      ? S.current.runTitle(step, rows.length)
      : S.current.runTitleEnded(rows.length);

  /// `stops at the first step that fails`, `all steps passed · 41 s`,
  /// `stopped · steps 1–2 stay done`.
  String get note => switch (badge) {
    TaskBadge.running => S.current.runStopsNote,
    TaskBadge.done when leftOut.isNotEmpty => S.current.runPassedLeftOut(
      leftOut.join(', '),
    ),
    TaskBadge.done when seconds > 0 => S.current.runPassedIn(seconds),
    TaskBadge.done => S.current.runPassed,
    _ when kept.isEmpty => S.current.runStoppedFirst,
    _ when kept.length == 1 => S.current.runStoppedOne(kept.single),
    _ => S.current.runStopped(kept.join(', ')),
  };

  Tone get noteTone => switch (badge) {
    TaskBadge.done => Tone.good,
    TaskBadge.failed => Tone.bad,
    _ => Tone.neutral,
  };

  @override
  List<Object?> get props => [badge, rows, step, leftOut, kept, seconds];
}

/// Board *AssistantRun*: the run of a plan, one row per step with its
/// result, and a line that says how the run ends or ended.
class RunCard extends StatelessWidget {
  const RunCard({required this.vm, super.key});

  final RunCardVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: Insets.assistantCard,
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.line2),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: Insets.cardHead,
            child: SectionLabel(vm.title),
          ),
          for (final r in vm.rows) _Row(vm: r),
          Container(
            padding: Insets.cardFoot,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line1)),
            ),
            child: Text(
              vm.note,
              style: TextStyle(
                fontSize: FontSizes.sm,
                height: 1.45,
                color: vm.noteTone == .neutral
                    ? c.text3
                    : toneColor(c, vm.noteTone),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.vm});

  final RunRowVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (vm.status) {
      .running => c.ember,
      .ok => c.good,
      .failed => c.bad,
      .waiting || .skipped => c.text3,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(
        14,
        AppSpacing.sm,
        14,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Row(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          SizedBox(
            width: 22,
            child: Text('${vm.n}', style: mono(size: 12, color: c.text3)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              vm.step,
              style: mono(
                size: 12,
                color: vm.status == .waiting || vm.status == .skipped
                    ? c.text3
                    : c.text1,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SelectableText(
              vm.text,
              textAlign: .right,
              style: mono(size: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
