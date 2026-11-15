import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/section_label.dart';
import '../indicators/arc_spinner.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'model_words.dart';
import 'suggestion_tile.dart';
import 'task_badge.dart';

/// What [StoppedCard] draws.
final class StoppedCardVm extends Equatable {
  const StoppedCardVm({
    required this.step,
    this.code,
    this.message,
    this.reviewing = false,
    this.review,
    this.ways = const [],
    this.offered = false,
    this.unattended,
  });

  /// The step the run stopped at.
  final int step;

  /// The fixed word the refusal starts with (`out_of_range`), if any.
  final String? code;

  /// Why it stopped, as the link said it; null when it said nothing.
  final String? message;

  /// The model reads why it stopped.
  final bool reviewing;

  /// What the model read about it.
  final String? review;
  final List<SuggestionTileVm> ways;

  /// The model offered suggestions (some may be on other cards).
  final bool offered;

  /// The agent's mode when a pick's plan may write without a person.
  final AgentModeVm? unattended;

  /// `Stopped at step 2 · out_of_range`.
  String get title => switch (code) {
    final c? => S.current.stoppedAtCode(step, c),
    null => S.current.stoppedAt(step),
  };

  /// What it said, and that what was done stays done.
  String get text => S.current.stoppedNote(message ?? S.current.failedNote);

  String? get reviewingNote => reviewing ? S.current.reviewingNote : null;

  ModelWordsVm? get reviewWords => switch (review) {
    final r? when !reviewing => ModelWordsVm(
      kind: ModelWordsKind.reviewed,
      text: r,
    ),
    _ => null,
  };

  String get waysLabel => S.current.waysOut;

  /// The caution of a mode that lets a pick's plan write at once.
  String? get caution => switch (unattended) {
    final m? => S.current.waysCaution(m.word),
    null => null,
  };

  String? get note => offered ? S.current.waysNote : null;

  @override
  List<Object?> get props => [
    step,
    code,
    message,
    reviewing,
    review,
    ways,
    offered,
    unattended,
  ];
}

/// Board *AssistantFailed*: where the run stopped and what the step
/// answered, what the assistant read about it (a spinner while it reads),
/// and the ways out it offers as tiles. Each tile is a follow-up ask.
class StoppedCard extends StatelessWidget {
  const StoppedCard({required this.vm, this.onPick, super.key});

  final StoppedCardVm vm;

  /// A way out (by its id) was picked.
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(
      fontSize: FontSizes.sm,
      height: 1.45,
      color: c.text3,
    );
    return Container(
      margin: Insets.assistantCard,
      padding: const EdgeInsets.fromLTRB(
        14,
        12,
        14,
        14,
      ),
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.badLine),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Text(
            vm.title,
            style: TextStyle(fontSize: FontSizes.sm, color: c.bad),
          ),
          SelectableText(
            vm.text,
            style: TextStyle(
              fontSize: FontSizes.lg,
              height: 1.5,
              color: c.text1,
            ),
          ),
          if (vm.reviewingNote case final r?)
            Row(
              spacing: 8,
              children: [
                ArcSpinner(color: c.ember, size: 14, label: r),
                Expanded(child: Text(r, style: small)),
              ],
            ),
          if (vm.reviewWords case final r?) ModelWords(vm: r),
          if (vm.ways.isNotEmpty) ...[
            SectionLabel(vm.waysLabel),
            if (vm.caution case final w?)
              Container(
                padding: Insets.band,
                decoration: BoxDecoration(
                  color: c.warnTint,
                  border: Border.all(color: c.warnLine),
                  borderRadius: Radii.control,
                ),
                child: Text(w, style: small.copyWith(color: c.warn)),
              ),
            for (final w in vm.ways)
              SuggestionTile(
                vm: w,
                onTap: onPick == null ? null : () => onPick!(w.id),
              ),
          ],
          if (vm.note case final n?) Text(n, style: small),
        ],
      ),
    );
  }
}
