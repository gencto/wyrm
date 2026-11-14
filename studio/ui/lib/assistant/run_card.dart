import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/section_label.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// Where a step of a run stands.
enum RunStatus { waiting, running, ok, failed, skipped }

/// One row of [RunCard]: a step and what the run did with it.
final class RunRowVm extends Equatable {
  const RunRowVm({
    required this.n,
    required this.step,
    required this.status,
    required this.text,
  });

  /// The step's number in the plan, from 1.
  final int n;

  /// `INVOKE add_device modbus/tcp-line2`.
  final String step;
  final RunStatus status;

  /// `running…`, the answer of the step, why it failed or was skipped,
  /// `waiting`.
  final String text;

  @override
  List<Object?> get props => [n, step, status, text];
}

/// What [RunCard] draws.
final class RunCardVm extends Equatable {
  const RunCardVm({
    required this.title,
    required this.rows,
    required this.note,
    this.noteTone = Tone.neutral,
  });

  /// `Run · step 2 of 5`.
  final String title;
  final List<RunRowVm> rows;

  /// `stops at the first step that fails`, `all steps passed · 41 s`,
  /// `stopped · steps 1–2 stay done`.
  final String note;
  final Tone noteTone;

  @override
  List<Object?> get props => [title, rows, note, noteTone];
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
            child: SectionLabel(vm.title),
          ),
          for (final r in vm.rows) _Row(vm: r),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line1)),
            ),
            child: Text(
              vm.note,
              style: TextStyle(
                fontSize: 12,
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
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
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
