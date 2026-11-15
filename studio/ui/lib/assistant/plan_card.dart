import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/section_label.dart';
import '../indicators/app_icon.dart';
import '../indicators/level_badge.dart';
import '../indicators/quality_mark.dart';
import '../indicators/tag_chip.dart';
import '../models/tone.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'model_words.dart';
import 'suggestion_tile.dart';
import 'task_badge.dart';

/// What a secret argument of a plan step is shown as.
const secretMask = '••••••';

/// One argument row of a step: its name and the value as it is sent, or
/// the mask. A masked value never reaches this model: only that it is
/// masked.
final class StepArgVm extends Equatable {
  /// An argument shown whole, as it is sent.
  const StepArgVm.shown(this.name, String this.value)
    : masked = false,
      timeout = null;

  /// An argument that is not shown (a secret, or a schema not known).
  const StepArgVm.masked(this.name)
    : masked = true,
      value = null,
      timeout = null;

  /// The step's timeout (`wait`, `expect`), in seconds.
  const StepArgVm.timeout(double this.timeout)
    : name = 'timeout',
      masked = false,
      value = null;

  final String name;
  final String? value;
  final bool masked;
  final double? timeout;

  /// What the row shows.
  String get text => masked
      ? secretMask
      : switch (timeout) {
          final t? => S.current.planSleep(plainNumber(t)),
          null => value ?? '',
        };

  @override
  List<Object?> get props => [name, value, masked, timeout];
}

/// When a step that changes something was checked.
enum StepCheckVm {
  now,
  atRun;

  String get label => switch (this) {
    now => S.current.checkNow,
    atRun => S.current.checkAtRun,
  };
}

/// Why a step's arguments carry a note.
enum ArgsNote {
  /// Its schema is not known: every argument is masked.
  masked,

  /// A secret argument is not shown.
  secret;

  String get label => switch (this) {
    masked => S.current.argsMasked,
    secret => S.current.planSecretNote,
  };
}

/// The line under a step that says how the approval treats it.
sealed class StepNoteVm extends Equatable {
  const StepNoteVm();

  String get text;

  @override
  List<Object?> get props => [];
}

/// It is skipped: a step it needs is left out.
final class StepNeeds extends StepNoteVm {
  const StepNeeds(this.step);

  final int step;

  @override
  String get text => S.current.stepSkippedNeeds(step);

  @override
  List<Object?> get props => [step];
}

/// The person unticked it.
final class StepLeftOut extends StepNoteVm {
  const StepLeftOut();

  @override
  String get text => S.current.stepLeftOut;
}

/// It runs with the agent's own key; it cannot be left out.
final class StepByAgent extends StepNoteVm {
  const StepByAgent();

  @override
  String get text => S.current.stepByAgent;
}

/// It runs after the steps [steps].
final class StepAfter extends StepNoteVm {
  const StepAfter(this.steps);

  final List<int> steps;

  @override
  String get text => steps.map(S.current.planNeedsStep).join(' · ');

  @override
  List<Object?> get props => [steps];
}

/// One step of a plan, as the person reads it before approving: what is
/// sent (the verb, the action, the full key, every argument), the level it
/// needs, how far it was checked, and the model's reason last and in grey.
final class PlanStepVm extends Equatable {
  const PlanStepVm({
    required this.n,
    required this.verb,
    required this.level,
    this.node = '',
    this.sleep,
    this.action,
    this.args = const [],
    this.check,
    this.argsNote,
    this.revealed,
    this.why,
    this.warn,
    this.modelWarn,
    this.fixes = const [],
    this.ticked,
    this.lacks,
    this.note,
    this.outcome,
    this.message = '',
  });

  /// Its number in the plan, from 1.
  final int n;
  final StepVerb verb;

  /// `invoke`: the action.
  final String? action;

  /// The node's full key; empty for a sleep.
  final String node;

  /// A sleep: how long, in seconds.
  final double? sleep;

  /// `read`, `write` or `config`.
  final String level;

  /// Every argument, as it is sent, or masked.
  final List<StepArgVm> args;

  /// How far it was checked; null when it changes nothing.
  final StepCheckVm? check;

  /// What the arguments' note says; null: none.
  final ArgsNote? argsNote;

  /// Masked arguments the person may look at: shown now (true) or masked
  /// (false); null when none can be shown.
  final bool? revealed;

  /// The model's reason.
  final String? why;

  /// The link's own finding about the step.
  final String? warn;

  /// The model's words about a risk of the step.
  final String? modelWarn;

  /// The fixes the model offers for this step.
  final List<SuggestionTileVm> fixes;

  /// Its tick; null when the person signs nothing for it.
  final bool? ticked;

  /// Why the tick cannot be set: the level the user lacks.
  final String? lacks;

  /// How the approval treats it.
  final StepNoteVm? note;

  /// How it ended in the run; null before.
  final StepOutcome? outcome;

  /// The responder's answer when it ended.
  final String message;

  /// The step changes the plant.
  bool get changes => verb.changes;

  /// `INVOKE`.
  String get verbLabel => verb.label;

  /// The full key, or the length of a sleep.
  String get target => switch (sleep) {
    final s? => S.current.planSleep(plainNumber(s)),
    null => node,
  };

  bool get checked => check != StepCheckVm.atRun;

  String? get revealLabel => switch (revealed) {
    true => S.current.hideArgs,
    false => S.current.showArgs,
    null => null,
  };

  ModelWordsVm? get modelWords => switch (modelWarn) {
    final w? when w.isNotEmpty => ModelWordsVm(
      kind: ModelWordsKind.says,
      text: w,
    ),
    _ => null,
  };

  /// Why the tick is locked: the level lacked, or the step it needs.
  String? get tickReason =>
      lacks ??
      switch (note) {
        StepNeeds(:final step) when ticked != null =>
          S.current.stepSkippedNeeds(step),
        _ => null,
      };

  /// `ok · added ahu2`.
  String? get result => switch (outcome) {
    final o? => '${o.word} · $message',
    null => null,
  };

  Tone get resultTone => outcome?.tone ?? Tone.neutral;

  @override
  List<Object?> get props => [
    n,
    verb,
    action,
    node,
    sleep,
    level,
    args,
    check,
    argsNote,
    revealed,
    why,
    warn,
    modelWarn,
    fixes,
    ticked,
    lacks,
    note,
    outcome,
    message,
  ];
}

/// The state line of a plan.
sealed class PlanLineVm extends Equatable {
  const PlanLineVm();

  String get text;

  @override
  List<Object?> get props => [];
}

/// It waits for approval: how many changes were checked now, and how many
/// only when they run.
final class PlanChecked extends PlanLineVm {
  const PlanChecked({required this.now, required this.atRun});

  final int now;
  final int atRun;

  @override
  String get text => atRun == 0
      ? S.current.planChecked
      : S.current.planCheckedPartly(now, atRun);

  @override
  List<Object?> get props => [now, atRun];
}

/// Another task took its place.
final class PlanReplaced extends PlanLineVm {
  const PlanReplaced(this.by);

  /// The task that replaced it.
  final String by;

  @override
  String get text => S.current.taskReplaced('tasks/$by');

  @override
  List<Object?> get props => [by];
}

/// Who approved it: the record's own line.
final class PlanApproved extends PlanLineVm {
  const PlanApproved(this.line);

  final String line;

  @override
  String get text => line;

  @override
  List<Object?> get props => [line];
}

/// Where the task stands, when nobody approved it.
final class PlanState extends PlanLineVm {
  const PlanState(this.badge);

  final TaskBadge badge;

  @override
  String get text => badge.label;

  @override
  List<Object?> get props => [badge];
}

/// What [PlanCard] draws.
final class PlanCardVm extends Equatable {
  const PlanCardVm({
    required this.line,
    required this.badge,
    required this.steps,
    this.open = true,
  });

  final PlanLineVm line;

  /// The task's state: the colour of [line].
  final TaskBadge badge;
  final List<PlanStepVm> steps;

  /// The steps are shown at first.
  final bool open;

  /// `Plan · 3 steps`.
  String get title => S.current.planSteps(steps.length);
  String get state => line.text;
  Tone get stateTone => badge.tone;
  String get note => S.current.planWhyNote;
  String get showLabel => S.current.showSteps;
  String get hideLabel => S.current.hideSteps;

  @override
  List<Object?> get props => [line, badge, steps, open];
}

/// Board *Assistant*: the plan of a task, one [PlanStepVm] per step. With
/// [onTick] the steps that have a tick can be ticked; without it the plan is
/// only shown.
class PlanCard extends StatefulWidget {
  const PlanCard({
    required this.vm,
    this.onTick,
    this.onFix,
    this.onReveal,
    super.key,
  });

  final PlanCardVm vm;

  /// A step (by its number) was ticked or unticked.
  final Toggled<int>? onTick;

  /// A fix (a suggestion, by its id) was picked.
  final ValueChanged<String>? onFix;

  /// The masked arguments of a step (by its number) are to be shown or
  /// masked again.
  final ValueChanged<int>? onReveal;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  late bool _open = widget.vm.open;

  @override
  void didUpdateWidget(PlanCard old) {
    super.didUpdateWidget(old);
    // the plan went from waiting to its run (or back): its own default
    if (old.vm.open != widget.vm.open) {
      _open = widget.vm.open;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final onTick = widget.onTick;
    final toggle = _open ? vm.hideLabel : vm.showLabel;
    final open = _open;
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
            // a long state line (how far it was checked) wraps beside the
            // toggle instead of pushing it out
            child: LayoutBuilder(
              builder: (context, box) => Row(
                spacing: 10,
                children: [
                  Expanded(child: SectionLabel(vm.title)),
                  // never wider than the row leaves beside the title and
                  // the toggle (the drawer is narrow)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(
                        0,
                        math.min(box.maxWidth * 0.6, box.maxWidth - 150),
                      ),
                    ),
                    child: Text(
                      vm.state,
                      textAlign: .right,
                      style: TextStyle(
                        fontSize: FontSizes.sm,
                        color: vm.stateTone == .neutral
                            ? c.text3
                            : toneColor(c, vm.stateTone),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _open = !_open),
                    child: Text(
                      toggle,
                      style: TextStyle(
                        fontSize: FontSizes.sm,
                        color: c.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            for (final s in vm.steps)
              _Step(
                vm: s,
                onTick: onTick,
                onFix: widget.onFix,
                onReveal: widget.onReveal,
              ),
          if (open)
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
                  color: c.text3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.vm,
    required this.onTick,
    required this.onFix,
    required this.onReveal,
  });

  final PlanStepVm vm;
  final Toggled<int>? onTick;
  final ValueChanged<String>? onFix;
  final ValueChanged<int>? onReveal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(
      fontSize: FontSizes.sm,
      height: 1.45,
      color: c.text3,
    );
    final can = onTick != null && vm.tickReason == null;
    return Container(
      padding: Insets.cardRow,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Row(
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: .center,
            decoration: BoxDecoration(
              shape: .circle,
              border: Border.all(color: vm.changes ? c.ember : c.line3),
            ),
            child: Text(
              '${vm.n}',
              style: mono(size: 11, color: vm.changes ? c.ember : c.text3),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 6,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: .center,
                  children: [
                    TagChip(
                      vm: TagChipVm(
                        label: vm.verbLabel,
                        tone: vm.changes ? .ember : .neutral,
                        monospace: true,
                      ),
                    ),
                    if (vm.action case final a?)
                      Text(a, style: mono(size: 13, color: c.text1)),
                    // the badge centres its text: keep it as wide as the text
                    IntrinsicWidth(child: LevelBadge(level: vm.level)),
                  ],
                ),
                // the key and the arguments are what is approved: whole
                SelectableText(
                  vm.target,
                  style: mono(size: 12, color: c.text1),
                ),
                for (final StepArgVm(:name, :text) in vm.args)
                  Row(
                    crossAxisAlignment: .start,
                    spacing: 10,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          name,
                          style: mono(size: 12, color: c.text3),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          text,
                          style: mono(size: 12, color: c.text1),
                        ),
                      ),
                    ],
                  ),
                if (vm.argsNote case final n?) Text(n.label, style: small),
                if (vm.revealLabel case final r?)
                  InkWell(
                    onTap: onReveal == null ? null : () => onReveal!(vm.n),
                    child: Text(r, style: small.copyWith(color: c.text2)),
                  ),
                if (vm.check?.label case final k?)
                  Row(
                    spacing: 6,
                    children: [
                      // an icon of the set: a glyph may be missing in a font
                      AppIcon(
                        vm.checked ? 'ui_check' : 'action_hist',
                        size: 14,
                        color: vm.checked ? c.good : c.text3,
                      ),
                      Expanded(
                        child: Text(
                          k,
                          style: small.copyWith(
                            color: vm.checked ? c.good : c.text3,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (vm.warn case final w?)
                  Container(
                    padding: Insets.band,
                    decoration: BoxDecoration(
                      color: c.warnTint,
                      border: Border.all(color: c.warnLine),
                      borderRadius: Radii.control,
                    ),
                    child: Text(w, style: small.copyWith(color: c.warn)),
                  ),
                if (vm.modelWords case final m?) ModelWords(vm: m),
                for (final f in vm.fixes)
                  SuggestionTile(
                    vm: f,
                    onTap: onFix == null ? null : () => onFix!(f.id),
                  ),
                if (vm.why case final w?) Text('why: $w', style: small),
                if (vm.note case final n?) Text(n.text, style: small),
                if (vm.result case final r?)
                  SelectableText(
                    r,
                    style: mono(
                      size: 12,
                      color: vm.resultTone == .neutral
                          ? c.text3
                          : toneColor(c, vm.resultTone),
                    ),
                  ),
              ],
            ),
          ),
          if (vm.ticked case final t?)
            Tooltip(
              message: vm.tickReason ?? '',
              child: Checkbox(
                value: t,
                onChanged: can ? (v) => onTick!(vm.n, on: v ?? false) : null,
              ),
            ),
        ],
      ),
    );
  }
}
