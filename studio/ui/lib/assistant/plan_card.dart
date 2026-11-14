import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/section_label.dart';
import '../indicators/app_icon.dart';
import '../indicators/level_badge.dart';
import '../indicators/quality_mark.dart';
import '../indicators/tag_chip.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One step of a plan, as the person reads it before approving: what is
/// sent (the verb, the action, the full key, every argument), the level it
/// needs, how far it was checked, and the model's reason last and in grey.
final class PlanStepVm extends Equatable {
  const PlanStepVm({
    required this.n,
    required this.verb,
    required this.target,
    required this.level,
    this.action,
    this.args = const [],
    this.changes = false,
    this.check,
    this.checked = true,
    this.argsNote,
    this.why,
    this.warn,
    this.ticked,
    this.tickReason,
    this.note,
    this.result,
    this.resultTone = Tone.neutral,
  });

  /// Its number in the plan, from 1.
  final int n;

  /// `SET`, `INVOKE`, `WAIT`, `EXPECT`, `SLEEP`.
  final String verb;
  final String? action;

  /// The full node key (or the length of a sleep).
  final String target;

  /// `read`, `write`, `config`.
  final String level;

  /// `name` and its value, each shown whole.
  final List<(String, String)> args;

  /// The step changes the site (its number is drawn in ember).
  final bool changes;

  /// The check line (`checked against the live tree`).
  final String? check;

  /// The check was made now (a tick); else it is made when the step runs.
  final bool checked;

  /// A line under the arguments (some are secret and not shown).
  final String? argsNote;

  /// The model's reason.
  final String? why;

  /// What the person must see before approving.
  final String? warn;

  /// The step's tick: null when the step has none (it needs no approval, or
  /// the plan is only shown).
  final bool? ticked;

  /// Why the tick cannot be changed (the level the user lacks).
  final String? tickReason;

  /// `skipped: needs step 2`.
  final String? note;

  /// What the run did with it (`ok`, `failed`, `skipped`, its message).
  final String? result;
  final Tone resultTone;

  @override
  List<Object?> get props => [
    n,
    verb,
    action,
    target,
    level,
    args,
    changes,
    check,
    checked,
    argsNote,
    why,
    warn,
    ticked,
    tickReason,
    note,
    result,
    resultTone,
  ];
}

/// What [PlanCard] draws.
final class PlanCardVm extends Equatable {
  const PlanCardVm({
    required this.title,
    required this.state,
    required this.steps,
    this.stateTone = Tone.warn,
    this.note,
  });

  /// `Plan · 5 steps`.
  final String title;

  /// `awaiting approval · checked`, `approved by olena`.
  final String state;
  final Tone stateTone;
  final List<PlanStepVm> steps;

  /// The line under the steps (the model's reasons are in grey: read the
  /// keys and the arguments).
  final String? note;

  @override
  List<Object?> get props => [title, state, stateTone, steps, note];
}

/// Board *Assistant*: the plan of a task, one [PlanStepVm] per step. With
/// [onTick] the steps that have a tick can be ticked; without it the plan is
/// only shown.
class PlanCard extends StatelessWidget {
  const PlanCard({required this.vm, this.onTick, super.key});

  final PlanCardVm vm;

  /// A step (by its number) was ticked or unticked.
  final void Function(int n, {required bool ticked})? onTick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(left: 42, bottom: 12),
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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              spacing: 10,
              children: [
                Expanded(child: SectionLabel(vm.title)),
                Text(
                  vm.state,
                  style: TextStyle(
                    fontSize: 12,
                    color: vm.stateTone == .neutral
                        ? c.text3
                        : toneColor(c, vm.stateTone),
                  ),
                ),
              ],
            ),
          ),
          for (final s in vm.steps) _Step(vm: s, onTick: onTick),
          if (vm.note case final n?)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(
                n,
                style: TextStyle(fontSize: 12, height: 1.45, color: c.text3),
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.vm, required this.onTick});

  final PlanStepVm vm;
  final void Function(int n, {required bool ticked})? onTick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 12, height: 1.45, color: c.text3);
    final can = onTick != null && vm.tickReason == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
                        label: vm.verb,
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
                for (final (name, value) in vm.args)
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
                          value,
                          style: mono(size: 12, color: c.text1),
                        ),
                      ),
                    ],
                  ),
                if (vm.argsNote case final n?) Text(n, style: small),
                if (vm.check case final k?)
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.warnTint,
                      border: Border.all(color: c.warnLine),
                      borderRadius: Radii.control,
                    ),
                    child: Text(w, style: small.copyWith(color: c.warn)),
                  ),
                if (vm.why case final w?) Text('why: $w', style: small),
                if (vm.note case final n?) Text(n, style: small),
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
                onChanged: can
                    ? (v) => onTick!(vm.n, ticked: v ?? false)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
