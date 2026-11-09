import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What the unreachable alert says (docs/design/specs/login.md §5).
final class UnreachableAlertVm extends Equatable {
  const UnreachableAlertVm({
    required this.detail,
    required this.advice,
    this.standby,
  });

  /// `<url> · <reason>`, in mono.
  final String detail;

  /// One line of advice.
  final String advice;

  /// The standby's `host:port`, when one is set: named in the advice and
  /// offered as `Use the standby`.
  final String? standby;

  @override
  List<Object?> get props => [detail, advice, standby];
}

/// The alert block above the log-in form when the gateway does not answer:
/// border `badLine`, fill `#1C1513`, radius 10, padding 14 × 16, gap 10 —
/// `Can’t reach this gateway`, the URL and the reason, the advice, and
/// `Try again` (ember) with `Use the standby` (outlined) when a standby is
/// set.
class UnreachableAlert extends StatelessWidget {
  const UnreachableAlert({
    required this.vm,
    required this.onRetry,
    this.onStandby,
    super.key,
  });

  final UnreachableAlertVm vm;
  final VoidCallback onRetry;
  final VoidCallback? onStandby;

  /// The alert's fill (the board's `#1C1513`, between `ground0` and
  /// `badTint`).
  static const fill = Color(0xFF1C1513);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mono = TextStyle(fontFamily: AppFonts.mono, color: c.text1);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          border: .all(color: c.badLine),
        ),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            Row(
              spacing: 8,
              children: [
                CustomPaint(
                  size: const Size.square(16),
                  painter: _WifiOff(c.badText),
                ),
                Text(
                  S.current.cantReachGateway,
                  style: TextStyle(fontSize: 14, color: c.badText),
                ),
              ],
            ),
            Text(
              vm.detail,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: c.text2,
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: vm.advice),
                  if (vm.standby case final s?) ...[
                    TextSpan(text: ' ${S.current.standbyAnswersAt} '),
                    TextSpan(text: s, style: mono),
                    const TextSpan(text: '.'),
                  ],
                ],
              ),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                leadingDistribution: .even,
                color: c.text3,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _button(
                  context,
                  S.current.tryAgain,
                  onRetry,
                  primary: true,
                ),
                if (vm.standby != null && onStandby != null)
                  _button(context, S.current.useStandby, onStandby!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool primary = false,
  }) {
    final c = context.colors;
    const shape = BorderRadius.all(Radius.circular(8));
    return Material(
      color: primary ? c.ember : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: shape,
        side: primary ? .none : BorderSide(color: c.line3),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: shape,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: primary ? .w600 : .w400,
                color: primary ? c.onEmber : c.text1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The board's wifi-off: `M2 8.8a15 15 0 0 1 20 0 M5 12.5a10 10 0 0 1 14 0
/// M8.5 16a5 5 0 0 1 7 0 M12 20h.01 M3 3l18 18`, stroke 2, round.
class _WifiOff extends CustomPainter {
  _WifiOff(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 2
      ..strokeCap = .round;
    canvas
      ..save()
      ..scale(k)
      ..drawPath(
        Path()
          ..moveTo(2, 8.8)
          ..arcToPoint(
            const Offset(22, 8.8),
            radius: const Radius.circular(15),
          )
          ..moveTo(5, 12.5)
          ..arcToPoint(
            const Offset(19, 12.5),
            radius: const Radius.circular(10),
          )
          ..moveTo(8.5, 16)
          ..arcToPoint(const Offset(15.5, 16), radius: const Radius.circular(5))
          ..moveTo(12, 20)
          ..lineTo(12.01, 20)
          ..moveTo(3, 3)
          ..lineTo(21, 21),
        paint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_WifiOff old) => old.color != color;
}
