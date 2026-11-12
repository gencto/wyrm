import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// One figure of a broker: a label, the value, one line under it.
final class MetricVm extends Equatable {
  const MetricVm({
    required this.label,
    required this.value,
    this.sub = '',
    this.tone = Tone.neutral,
  });

  final String label;
  final String value;
  final String sub;

  /// warn or bad colours the value.
  final Tone tone;

  @override
  List<Object?> get props => [label, value, sub, tone];
}

/// Board *Studio · System* figure card.
class MetricCard extends StatelessWidget {
  const MetricCard({required this.vm, super.key});

  final MetricVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          Text(vm.label, style: TextStyle(fontSize: 13, color: c.text3)),
          Text(
            vm.value,
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(
              fontSize: 22,
              color: vm.tone == .neutral ? c.text1 : toneColor(c, vm.tone),
            ),
          ),
          if (vm.sub.isNotEmpty)
            Text(
              vm.sub,
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(fontSize: 12, color: c.text4),
            ),
        ],
      ),
    );
  }
}
