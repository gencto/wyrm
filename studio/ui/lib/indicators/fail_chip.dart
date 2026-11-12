import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'app_icon.dart';

/// What [FailChip] draws: the mark on the thing whose read failed.
final class FailChipVm extends Equatable {
  const FailChipVm({required this.label, this.tip});

  /// `read failed`, `history unavailable`.
  final String label;

  /// `Reading the value failed: timeout. Details in Problems.`
  final String? tip;

  @override
  List<Object?> get props => [label, tip];
}

/// The chip beside a row's name when reading its value failed (board
/// `ErrorQuiet`, docs/design/specs/errors.md §4): 20 high, `badTint` /
/// `badText`, with the reason as its tooltip. The value beside it is `—`.
class FailChip extends StatelessWidget {
  const FailChip({required this.vm, super.key});

  final FailChipVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chip = Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: c.badTint, borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: .min,
        spacing: 4,
        children: [
          AppIcon('err_mark', size: 11, color: c.badText),
          Text(
            vm.label,
            maxLines: 1,
            softWrap: false,
            style: boardText(size: 11, color: c.badText),
          ),
        ],
      ),
    );
    return switch (vm.tip) {
      final tip? => Tooltip(message: tip, child: chip),
      null => chip,
    };
  }
}
