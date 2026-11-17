import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/section_label.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'task_badge.dart';

/// One key a finished plan touched, with its value now.
final class ResultFactVm extends Equatable {
  const ResultFactVm(this.key, this.value);

  /// The full key.
  final String key;

  /// Its value now, as text; null: none was read.
  final String? value;

  @override
  List<Object?> get props => [key, value];
}

/// What [ResultCard] draws.
final class ResultCardVm extends Equatable {
  const ResultCardVm({required this.facts});

  /// The keys the plan touched (full keys) and their values now, as text;
  /// a null value: none was read.
  final List<ResultFactVm> facts;

  /// `Result`.
  String get title => S.current.resultTitle;

  /// The line under the facts (the values are read live).
  String get note => S.current.resultNote;

  @override
  List<Object?> get props => [facts];
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
      margin: Insets.assistantCard,
      padding: Insets.card,
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
          for (final ResultFactVm(:key, :value) in vm.facts)
            Row(
              crossAxisAlignment: .start,
              spacing: 12,
              children: [
                Expanded(
                  flex: 3,
                  child: SelectableText(
                    belowSection(key),
                    style: mono(size: 12, color: c.text2),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    value ?? S.current.resultNoValue,
                    textAlign: .right,
                    style: mono(size: 13, color: c.text1),
                  ),
                ),
              ],
            ),
          Text(
            vm.note,
            style: TextStyle(
              fontSize: FontSizes.sm,
              height: 1.45,
              color: c.text3,
            ),
          ),
        ],
      ),
    );
  }
}
