import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/sweep_bar.dart';
import '../indicators/wyrm_loader.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// The log-in's button (docs/design/specs/login.md §3.6): 50 high, radius 10,
/// ember with `onEmber` 16/600 `Log in`. While [busy]: filled `#C9772F`,
/// disabled, the small crawl loader before `Signing in…`, and the bar along
/// the bottom edge (3 high, `onEmber` at 45 %).
class LogInButton extends StatelessWidget {
  const LogInButton({required this.onPressed, this.busy = false, super.key});

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// A log-in is in flight.
  final bool busy;

  /// The ember of a pressed, busy button (the board's `#C9772F`).
  static const busyFill = Color(0xFFC9772F);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: busy ? busyFill : c.ember,
      clipBehavior: .antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: InkWell(
        onTap: busy ? null : onPressed,
        child: SizedBox(
          height: 50,
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisSize: .min,
                  spacing: 12,
                  children: [
                    if (busy) const WyrmLoader(),
                    Text(
                      busy ? S.current.signingIn : S.current.logIn,
                      style: TextStyle(
                        fontFamily: AppFonts.sans,
                        fontSize: 16,
                        fontWeight: .w600,
                        color: c.onEmber,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SweepBar.strip(
                    color: c.onEmber.withValues(alpha: .45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
