import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What [ProblemsPill] draws: the count of problems not yet looked at.
final class ProblemsPillVm extends Equatable {
  const ProblemsPillVm({
    required this.label,
    this.bad = false,
    this.open = false,
  });

  /// `3 problems`, already counted and localized.
  final String label;

  /// One of them is the broker's or Studio's fault: the dot is `bad`, else
  /// `warn`.
  final bool bad;

  /// The drawer is open: the pill is on the `bad` tint.
  final bool open;

  @override
  List<Object?> get props => [label, bad, open];
}

/// The pill of the top bar that opens the Problems drawer (boards
/// `ErrorQuiet`, `ErrorProblems`): 32 high, a dot and the count. The top
/// bar does not draw it at all when nothing is unread and the drawer is
/// closed.
class ProblemsPill extends StatelessWidget {
  const ProblemsPill({required this.vm, required this.onTap, super.key});

  final ProblemsPillVm vm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      expanded: vm.open,
      child: Material(
        color: vm.open ? c.badTint : c.ground3,
        shape: StadiumBorder(
          side: BorderSide(color: vm.open ? c.badLine : c.line2),
        ),
        child: InkWell(
          key: const ValueKey('problems-pill'),
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: .min,
              spacing: 8,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: vm.bad ? c.bad : c.warn,
                    shape: .circle,
                  ),
                ),
                Text(vm.label, style: boardText(size: 13, color: c.text1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
