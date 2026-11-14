import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// What [TrustCard] says (docs/design/specs/unlock-discover.md §4, *Trust*).
final class TrustCardVm extends Equatable {
  const TrustCardVm({
    required this.title,
    required this.why,
    required this.code,
    required this.where,
    required this.command,
    required this.trust,
    this.refused,
    this.busy = false,
  });

  /// `First time on <site> · check its certificate`.
  final String title;

  /// Why the code is to be compared.
  final String why;

  /// The CA code in 8 groups of 4.
  final List<String> code;

  /// Where the broker shows the code; [command] in it is set in mono.
  final String where;
  final String command;

  /// `It matches · trust <site>`.
  final String trust;

  /// Why the last trust was refused; nothing was pinned.
  final String? refused;

  /// The trust is being checked.
  final bool busy;

  @override
  List<Object?> get props => [
    title,
    why,
    code,
    where,
    command,
    trust,
    refused,
    busy,
  ];
}

/// The amber card that takes the panel's place for a gateway whose CA this
/// computer does not know: the title with a shield, one line on why, the
/// code in a 4 × 2 grid of mono groups, where to find it on the broker,
/// `It matches · trust <site>` (ember) and `Cancel`.
class TrustCard extends StatelessWidget {
  const TrustCard({
    required this.vm,
    required this.onTrust,
    required this.onCancel,
    super.key,
  });

  final TrustCardVm vm;
  final VoidCallback onTrust;
  final VoidCallback onCancel;

  /// The board's fill and border (`#1A1810`, `#6A5A2A`): amber, darker than
  /// `warnTint` and lighter than `warnLine`.
  static const fill = Color(0xFF1A1810);
  static const border = Color(0xFF6A5A2A);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(
      fontSize: 12,
      height: 1.5,
      leadingDistribution: .even,
      color: c.text4,
    );
    final at = vm.where.indexOf(vm.command);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: .all(color: border),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 14,
          children: [
            Row(
              spacing: 8,
              children: [
                CustomPaint(
                  size: const Size.square(16),
                  painter: _Shield(c.warn),
                ),
                Expanded(
                  child: Text(
                    vm.title,
                    style: TextStyle(fontSize: 14, color: c.warn),
                  ),
                ),
              ],
            ),
            Text(
              vm.why,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                leadingDistribution: .even,
                color: c.text2,
              ),
            ),
            Semantics(
              label: S.current.trustCode,
              value: vm.code.join(' '),
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.ground0,
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    border: .all(color: c.line1),
                  ),
                  child: Column(
                    spacing: 6,
                    children: [
                      for (var row = 0; row < vm.code.length; row += 4)
                        Row(
                          children: [
                            for (final g in vm.code.skip(row).take(4))
                              Expanded(
                                child: Text(
                                  g,
                                  textAlign: .center,
                                  style: TextStyle(
                                    fontFamily: AppFonts.mono,
                                    fontSize: 15,
                                    letterSpacing: 1.2,
                                    color: c.text1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Text.rich(
              TextSpan(
                children: at < 0
                    ? [TextSpan(text: vm.where)]
                    : [
                        TextSpan(text: vm.where.substring(0, at)),
                        TextSpan(
                          text: vm.command,
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            color: c.text2,
                          ),
                        ),
                        TextSpan(
                          text: vm.where.substring(at + vm.command.length),
                        ),
                      ],
              ),
              style: small,
            ),
            if (vm.refused case final r?)
              Text(r, style: TextStyle(fontSize: 13, color: c.badText)),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: _button(
                    context,
                    vm.trust,
                    vm.busy ? null : onTrust,
                    primary: true,
                  ),
                ),
                _button(context, S.current.cancel, onCancel),
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
    VoidCallback? onTap, {
    bool primary = false,
  }) {
    final c = context.colors;
    const shape = BorderRadius.all(Radius.circular(10));
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
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
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

/// The board's shield: `M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7z` and
/// `M12 9v4 M12 16h.01`, stroke 2, round.
class _Shield extends CustomPainter {
  _Shield(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas
      ..save()
      ..scale(k)
      ..drawPath(
        Path()
          ..moveTo(12, 3)
          ..lineTo(20, 7)
          ..lineTo(20, 12)
          ..cubicTo(20, 17, 16.5, 20, 12, 21)
          ..cubicTo(7.5, 20, 4, 17, 4, 12)
          ..lineTo(4, 7)
          ..close()
          ..moveTo(12, 9)
          ..lineTo(12, 13)
          ..moveTo(12, 16)
          ..lineTo(12.01, 16),
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = 2
          ..strokeCap = .round
          ..strokeJoin = .round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_Shield old) => old.color != color;
}
