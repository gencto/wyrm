import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/status_dot.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One recent gateway under the gateway field (docs/design/specs/login.md
/// §3.2): its short name and the last probe's result.
final class RecentChipVm extends Equatable {
  const RecentChipVm({
    required this.id,
    required this.label,
    required this.tone,
    this.current = false,
  });

  /// The gateway text the chip fills the field with.
  final String id;

  /// Its short name (`plant`, `127.0.0.1`).
  final String label;

  /// The last probe: good (answered), bad (no answer), neutral (not probed).
  final Tone tone;

  /// The gateway in the field: ember.
  final bool current;

  @override
  List<Object?> get props => [id, label, tone, current];
}

/// A chip 28 high, radius 14, mono 12, with a 6 px dot of the last result;
/// the current one in ember (`emberNew` on `emberFill`, border `emberLine`).
class RecentChip extends StatelessWidget {
  const RecentChip({required this.vm, this.onTap, super.key});

  final RecentChipVm vm;

  /// Fills the field with [RecentChipVm.id].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = switch (vm.tone) {
      .good => c.good,
      .bad => c.bad,
      _ => c.muted,
    };
    return Semantics(
      button: true,
      selected: vm.current,
      child: Material(
        color: vm.current ? c.emberFill : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: vm.current ? c.emberLine : c.line2),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: .min,
              spacing: 6,
              children: [
                StatusDot(color: dot, size: 6),
                Text(
                  vm.label,
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: vm.current ? c.emberNew : c.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
