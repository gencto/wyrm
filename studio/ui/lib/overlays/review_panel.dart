import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../alerts/notice.dart';
import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One staged change as the review card shows it.
final class ChangeCardVm extends Equatable {
  const ChangeCardVm({
    required this.id,
    required this.op,
    required this.key_,
    required this.field,
    required this.from,
    required this.to,
    required this.levelText,
    required this.allowed,
  });

  final String id;

  /// `Edit`, `Add`, `Remove`.
  final String op;

  /// The key, shortened (`…/plc1/t2`).
  final String key_;
  final String field;
  final String from;
  final String to;

  /// `Needs write · you have it`.
  final String levelText;

  /// The user has the level it needs.
  final bool allowed;

  @override
  List<Object?> get props => [
    id,
    op,
    key_,
    field,
    from,
    to,
    levelText,
    allowed,
  ];
}

/// Board *Design system* §06 change card: the op tag, the key, the field
/// with the old value struck through and the new one in ember/new, the level
/// it needs.
class ChangeCard extends StatelessWidget {
  const ChangeCard({required this.vm, this.onRemove, super.key});

  final ChangeCardVm vm;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.ground2,
        border: .all(color: vm.allowed ? c.line1 : c.badLine),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 10,
        children: [
          Row(
            spacing: 10,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: c.ground4,
                  borderRadius: Radii.chip,
                ),
                child: Text(
                  vm.op.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: .w600,
                    letterSpacing: 0.55,
                    color: c.text2,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  vm.key_,
                  overflow: .ellipsis,
                  style: mono(color: c.text1),
                ),
              ),
              if (onRemove != null)
                InkWell(
                  onTap: () => onRemove!(vm.id),
                  child: AppIcon('ui_close', size: 16, color: c.text4),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: .center,
            children: [
              Text(vm.field, style: mono(color: c.text4)),
              Text(
                vm.from,
                style: mono(color: c.text3).copyWith(
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              Text('→', style: mono(color: c.text4)),
              Text(vm.to, style: mono(color: c.emberNew)),
            ],
          ),
          QualityMark(
            size: 12,
            vm: QualityMarkVm(
              label: vm.levelText,
              tone: vm.allowed ? Tone.good : Tone.bad,
            ),
          ),
        ],
      ),
    );
  }
}

/// The words of the review panel, localized by the connector.
final class ReviewLabels {
  const ReviewLabels({
    required this.title,
    required this.apply,
    required this.discard,
    required this.empty,
    required this.note,
    required this.refused,
  });

  /// `3 staged changes`.
  final String title;
  final String apply;
  final String discard;
  final String empty;

  /// One line under the title.
  final String note;

  /// The title of a refusal (`The broker refused a change`).
  final String refused;
}

/// The right panel of Review and apply.
class ReviewPanel extends StatelessWidget {
  const ReviewPanel({
    required this.cards,
    required this.labels,
    required this.onApply,
    required this.onDiscard,
    required this.onClose,
    required this.onRemove,
    this.error,
    this.applying = false,
    super.key,
  });

  final List<ChangeCardVm> cards;
  final ReviewLabels labels;
  final VoidCallback onApply;
  final VoidCallback onDiscard;
  final VoidCallback onClose;
  final ValueChanged<String> onRemove;

  /// The broker's refusal of the last apply.
  final String? error;
  final bool applying;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocked = cards.any((x) => !x.allowed);
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(left: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labels.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: AppIcon('ui_close', size: 18, color: c.text3),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              labels.note,
              style: TextStyle(fontSize: 13, color: c.text3),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                if (error case final e?) ...[
                  Notice(
                    vm: NoticeVm(
                      message: labels.refused,
                      detail: e,
                      tone: .bad,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (cards.isEmpty)
                  Text(
                    labels.empty,
                    style: TextStyle(fontSize: 13, color: c.text4),
                  ),
                for (final card in cards) ...[
                  ChangeCard(vm: card, onRemove: onRemove),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line1)),
            ),
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Button.primary(
                    label: labels.apply,
                    size: .commit,
                    expand: true,
                    onPressed: cards.isEmpty || blocked || applying
                        ? null
                        : onApply,
                  ),
                ),
                Button.quiet(
                  label: labels.discard,
                  size: .commit,
                  onPressed: cards.isEmpty ? null : onDiscard,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
