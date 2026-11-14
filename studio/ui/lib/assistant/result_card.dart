import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/section_label.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What [ResultCard] draws.
final class ResultCardVm extends Equatable {
  const ResultCardVm({
    required this.title,
    required this.facts,
    this.note,
  });

  /// `Result`.
  final String title;

  /// The keys the plan touched and their values now: `(key, value)`.
  final List<(String, String)> facts;

  /// The line under the facts (the values are read live).
  final String? note;

  @override
  List<Object?> get props => [title, facts, note];
}

/// Board *AssistantDone*: what a finished plan left behind, as the keys it
/// touched with their values now.
class ResultCard extends StatelessWidget {
  const ResultCard({required this.vm, super.key});

  final ResultCardVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
        spacing: 8,
        children: [
          SectionLabel(vm.title),
          for (final (key, value) in vm.facts)
            Row(
              crossAxisAlignment: .start,
              spacing: 12,
              children: [
                Expanded(
                  flex: 3,
                  child: SelectableText(
                    key,
                    style: mono(size: 12, color: c.text2),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    value,
                    textAlign: .right,
                    style: mono(size: 13, color: c.text1),
                  ),
                ),
              ],
            ),
          if (vm.note case final n?)
            Text(
              n,
              style: TextStyle(fontSize: 12, height: 1.45, color: c.text3),
            ),
        ],
      ),
    );
  }
}
