import 'package:material_ui/material_ui.dart';

import '../indicators/arc_spinner.dart';
import '../indicators/biometric_icon.dart';
import '../theme/extensions/colors.dart';

/// The round unlock button of the boards `Unlock` (104) and `UnlockLock`
/// (92): the platform's glyph in `emberSoft` on `emberFill`, a 1.5 ring in
/// `emberLine`, `ember` and a turning arc while the gateway checks the key.
class UnlockButton extends StatelessWidget {
  const UnlockButton({
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.size = 104,
    this.focusNode,
    super.key,
  });

  final BiometricGlyph glyph;

  /// `Unlock with <name>`, for the semantics.
  final String label;

  /// Null disables it (the gateway does not answer).
  final VoidCallback? onPressed;
  final bool busy;
  final double size;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The board's arc: r 10.5 of a 24 box drawn 116 wide (size + 12),
    // stroke 0.8; ArcSpinner's circle is r 9 of its box.
    final ring = size + 12;
    final spinner = ring * 10.5 / 9;
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: .none,
          alignment: .center,
          children: [
            Material(
              color: c.emberFill,
              shape: CircleBorder(
                side: BorderSide(
                  color: busy ? c.ember : c.emberLine,
                  width: 1.5,
                ),
              ),
              clipBehavior: .antiAlias,
              child: InkWell(
                focusNode: focusNode,
                onTap: busy ? null : onPressed,
                child: Center(
                  child: BiometricIcon(
                    glyph: glyph,
                    size: size / 2,
                    stroke: 1.5,
                    color: c.emberSoft,
                  ),
                ),
              ),
            ),
            if (busy)
              Positioned(
                left: (size - spinner) / 2,
                top: (size - spinner) / 2,
                child: IgnorePointer(
                  child: ArcSpinner(
                    color: c.ember,
                    size: spinner,
                    // 0.8 of the board's box in ArcSpinner's own box.
                    strokeWidth: 0.8 * ring / spinner,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
