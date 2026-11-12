import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../indicators/fail_chip.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// What [ReadFail] draws: the reads of one node that failed.
///
/// [id] is the key of the node; the composer passes it back to its own
/// callback.
final class ReadFailVm extends Equatable {
  const ReadFailVm({
    required this.id,
    required this.chip,
    required this.lines,
    required this.retry,
  });

  final String id;

  /// `read failed`.
  final FailChipVm chip;

  /// One sentence per read that failed: `Reading the value failed: timeout.
  /// Details in Problems.`
  final List<String> lines;

  /// `Read again`.
  final String retry;

  @override
  List<Object?> get props => [id, chip, lines, retry];
}

/// The mark in the inspector of a node whose read failed
/// (docs/design/specs/errors.md §4): the `read failed` chip, what failed in
/// words (the same as the chip's tooltip on the row), and `Read again`.
/// A card in `ground2` with the `badLine`; the Explorer's inspector composes
/// it above the node's sections.
class ReadFail extends StatelessWidget {
  const ReadFail({required this.vm, this.onRetry, super.key});

  final ReadFailVm vm;

  /// Reads the node [ReadFailVm.id] again; no button without it.
  final ValueChanged<String>? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.ground2,
          border: .all(color: c.badLine),
          borderRadius: Radii.button,
        ),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            FailChip(vm: FailChipVm(label: vm.chip.label)),
            for (final line in vm.lines)
              Text(
                line,
                style: TextStyle(fontSize: 12, height: 1.5, color: c.text2),
              ),
            if (onRetry case final retry?)
              Button.secondary(
                key: const ValueKey('read-again'),
                label: vm.retry,
                size: .small,
                onPressed: () => retry(vm.id),
              ),
          ],
        ),
      ),
    );
  }
}
