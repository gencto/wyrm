import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/section_label.dart';
import '../indicators/arc_spinner.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import 'model_words.dart';
import 'suggestion_tile.dart';

/// What [StoppedCard] draws.
final class StoppedCardVm extends Equatable {
  const StoppedCardVm({
    required this.title,
    required this.message,
    this.review,
    this.reviewing,
    this.waysLabel,
    this.ways = const [],
    this.caution,
    this.note,
  });

  /// `Stopped at step 2 · out_of_range`.
  final String title;

  /// What the step answered (the link's words).
  final String message;

  /// What the model read about the failure.
  final ModelWordsVm? review;

  /// `the assistant reads why it stopped…`: shown with a spinner while
  /// the review runs; null when it does not.
  final String? reviewing;

  /// `Ways out`.
  final String? waysLabel;
  final List<SuggestionTileVm> ways;

  /// What a pick may do without a person (the agent's mode): before the
  /// tiles, on the warning tint.
  final String? caution;

  /// The line under the tiles.
  final String? note;

  @override
  List<Object?> get props => [
    title,
    message,
    review,
    reviewing,
    waysLabel,
    ways,
    caution,
    note,
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
    final small = TextStyle(fontSize: 12, height: 1.45, color: c.text3);
    return Container(
      margin: const EdgeInsets.only(left: 42, bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.badLine),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Text(vm.title, style: TextStyle(fontSize: 12, color: c.bad)),
          SelectableText(
            vm.message,
            style: TextStyle(fontSize: 14, height: 1.5, color: c.text1),
          ),
          if (vm.reviewing case final r?)
            Row(
              spacing: 8,
              children: [
                ArcSpinner(color: c.ember, size: 14, label: r),
                Expanded(child: Text(r, style: small)),
              ],
            ),
          if (vm.review case final r?) ModelWords(vm: r),
          if (vm.ways.isNotEmpty) ...[
            if (vm.waysLabel case final l?) SectionLabel(l),
            if (vm.caution case final w?)
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
