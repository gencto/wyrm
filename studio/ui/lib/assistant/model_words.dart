import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What [ModelWords] draws: text the model wrote about a step or a run,
/// under a label that says so.
final class ModelWordsVm extends Equatable {
  const ModelWordsVm({required this.kind, required this.text});

  /// What the words are about: a step, or a run that stopped.
  final ModelWordsKind kind;

  /// The model's words, shown as plain text: no marks read, no links.
  final String text;

  /// `the assistant says`, `what the assistant read about it`.
  String get label => switch (kind) {
    ModelWordsKind.says => S.current.modelSays,
    ModelWordsKind.reviewed => S.current.modelReviewed,
  };

  @override
  List<Object?> get props => [kind, text];
}

/// What the model's words are about.
enum ModelWordsKind {
  /// A risk of a plan step (`model_warn`).
  says,

  /// Why a run stopped (`review`).
  reviewed,
}

/// The model's words in a card (a step's `model_warn`, the review after a
/// stopped run). Drawn as the model's lines in the conversation are (the
/// assistant's mark, plain text on the card's ground), never as a check or
/// a warning of the link: those have the warning tint, this has none.
class ModelWords extends StatelessWidget {
  const ModelWords({required this.vm, super.key});

  final ModelWordsVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        color: c.ground2,
        border: Border.all(color: c.line2),
        borderRadius: Radii.control,
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Row(
            spacing: 6,
            children: [
              AppIcon('ws_assistant', size: 12, color: c.ember),
              Text(
                vm.label,
                style: TextStyle(fontSize: FontSizes.xs, color: c.text3),
              ),
            ],
          ),
          SelectableText(
            vm.text,
            style: TextStyle(
              fontSize: FontSizes.md,
              height: 1.45,
              color: c.text2,
            ),
          ),
        ],
      ),
    );
  }
}
