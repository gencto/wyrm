import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/section_label.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// One option of a question: its label, the detail under it, and whether
/// it is picked.
final class ChoiceOptionVm extends Equatable {
  const ChoiceOptionVm({
    required this.id,
    required this.label,
    this.detail = '',
    this.picked = false,
  });

  final String id;
  final String label;
  final String detail;
  final bool picked;

  @override
  List<Object?> get props => [id, label, detail, picked];
}

/// One question of [ChoicesCard]. With [answer] it was answered and is
/// drawn as one line (`from the card: …`); else as its options.
final class ChoiceQuestionVm extends Equatable {
  const ChoiceQuestionVm({
    required this.id,
    required this.text,
    this.options = const [],
    this.multiple = false,
    this.answer,
  });

  final String id;
  final String text;
  final List<ChoiceOptionVm> options;

  /// Several options may be picked (ticks); else one (a radio mark).
  final bool multiple;
  final String? answer;

  @override
  List<Object?> get props => [id, text, options, multiple, answer];
}

/// What [ChoicesCard] draws.
final class ChoicesCardVm extends Equatable {
  const ChoicesCardVm({
    required this.title,
    required this.questions,
    this.confirm,
    this.confirmReason,
    this.note,
  });

  /// `The assistant asks`.
  final String title;
  final List<ChoiceQuestionVm> questions;

  /// `Write the plan`; null when every question was answered.
  final String? confirm;

  /// Why [confirm] cannot be pressed (nothing picked, no write on the
  /// agent).
  final String? confirmReason;

  /// `Or answer in your own words below.`
  final String? note;

  @override
  List<Object?> get props => [title, questions, confirm, confirmReason, note];
}

/// Board *AssistantAsk*: the assistant asks back. Each open question is a
/// group of option tiles; an answered one is one line.
class ChoicesCard extends StatelessWidget {
  const ChoicesCard({
    required this.vm,
    required this.onPick,
    required this.onConfirm,
    super.key,
  });

  final ChoicesCardVm vm;

  /// An option of a question was tapped.
  final void Function(String question, String option) onPick;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 12, height: 1.45, color: c.text3);
    return Container(
      margin: const EdgeInsets.only(left: 42, bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.line2),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          SectionLabel(vm.title),
          for (final q in vm.questions) ...[
            Text(
              q.text,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.text1),
            ),
            if (q.answer case final a?)
              Text(a, style: small.copyWith(color: c.text2))
            else
              for (final o in q.options)
                _Option(
                  vm: o,
                  multiple: q.multiple,
                  onTap: () => onPick(q.id, o.id),
                ),
          ],
          if (vm.confirm case final label?)
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Text(vm.note ?? '', style: small),
                ),
                Button.primary(
                  label: label,
                  disabledReason: vm.confirmReason,
                  onPressed: vm.confirmReason == null ? onConfirm : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.vm,
    required this.multiple,
    required this.onTap,
  });

  final ChoiceOptionVm vm;
  final bool multiple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.control,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: vm.picked ? c.emberTint : null,
          border: Border.all(color: vm.picked ? c.ember : c.line2),
          borderRadius: Radii.control,
        ),
        child: Row(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                shape: multiple ? .rectangle : .circle,
                borderRadius: multiple ? BorderRadius.circular(3) : null,
                color: vm.picked ? c.ember : null,
                border: Border.all(color: vm.picked ? c.ember : c.line3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text(
                    vm.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: .w500,
                      color: c.text1,
                    ),
                  ),
                  if (vm.detail.isNotEmpty)
                    Text(
                      vm.detail,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: c.text3,
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
