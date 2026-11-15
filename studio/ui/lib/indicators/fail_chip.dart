import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'app_icon.dart';

/// What [FailChip] draws: the mark on the thing whose read failed.
final class FailChipVm extends Equatable {
  const FailChipVm({required this.label, this.tip});

  /// `read failed`, the sentence of each [reads] as its tooltip.
  factory FailChipVm.reads(List<ReadFailed> reads, {bool tip = true}) =>
      FailChipVm(
        label: S.current.readFailed,
        tip: tip ? [for (final r in reads) r.line].join('\n') : null,
      );

  /// `history unavailable`, the reason as its tooltip.
  factory FailChipVm.history(String reason) => FailChipVm(
    label: S.current.historyUnavailable,
    tip: S.current.historyUnavailableTip(reason),
  );

  /// `read failed`, `history unavailable`.
  final String label;

  /// `Reading the value failed: timeout. Details in Problems.`
  final String? tip;

  @override
  List<Object?> get props => [label, tip];
}

/// What of a node could not be read (docs/design/specs/errors.md §4).
enum ReadWhat { value, list, meta }

/// A read that failed, and why (the status's wire name: `timeout`).
final class ReadFailed extends Equatable {
  const ReadFailed(this.what, this.reason);

  final ReadWhat what;
  final String reason;

  /// `Reading the value failed: timeout. Details in Problems.`
  String get line => switch (what) {
    ReadWhat.value => S.current.readFailedTip(reason),
    ReadWhat.list => S.current.listFailedTip(reason),
    ReadWhat.meta => S.current.metaFailedTip(reason),
  };

  @override
  List<Object?> get props => [what, reason];
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
