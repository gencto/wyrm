import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';

/// `Find on this network` beside the gateway field
/// (docs/design/specs/unlock-discover.md §4): 46 high, radius 10, a radar
/// icon 16 and the label 13. While the panel is [open] it is ember
/// (`emberNew` on `emberFill`, border `emberLine`); a tap toggles the panel.
class FindNetworkButton extends StatelessWidget {
  const FindNetworkButton({
    required this.onPressed,
    this.open = false,
    super.key,
  });

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// The panel is open.
  final bool open;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = open ? c.emberNew : c.text1;
    const shape = BorderRadius.all(Radius.circular(10));
    return Semantics(
      button: true,
      toggled: open,
      child: Material(
        color: open ? c.emberFill : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: BorderSide(color: open ? c.emberLine : c.line2),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: shape,
          child: SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: .min,
                spacing: 8,
                children: [
                  CustomPaint(
                    size: const Size.square(16),
                    painter: _Radar(ink),
                  ),
                  Text(
                    S.current.findOnNetwork,
                    style: TextStyle(fontSize: 13, color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The board's radar: a circle r 2 at the centre and two pairs of arcs
/// (`M16.24 7.76a6 6 0 0 1 0 8.49`, `M19.07 4.93a10 10 0 0 1 0 14.14` and
/// their mirrors), stroke 2, round.
class _Radar extends CustomPainter {
  _Radar(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas
      ..save()
      ..scale(k)
      ..drawPath(
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 2))
          ..moveTo(16.24, 7.76)
          ..arcToPoint(
            const Offset(16.24, 16.25),
            radius: const Radius.circular(6),
          )
          ..moveTo(7.76, 16.24)
          ..arcToPoint(
            const Offset(7.76, 7.75),
            radius: const Radius.circular(6),
          )
          ..moveTo(19.07, 4.93)
          ..arcToPoint(
            const Offset(19.07, 19.07),
            radius: const Radius.circular(10),
          )
          ..moveTo(4.93, 19.07)
          ..arcToPoint(
            const Offset(4.93, 4.93),
            radius: const Radius.circular(10),
          ),
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = 2
          ..strokeCap = .round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_Radar old) => old.color != color;
}
