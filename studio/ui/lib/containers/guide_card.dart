import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../indicators/code_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// What [GuideCard] says.
final class GuideCardVm extends Equatable {
  const GuideCardVm({
    required this.title,
    required this.body,
    required this.stepsTitle,
    required this.steps,
    this.link,
  });

  final String title;
  final String body;
  final String stepsTitle;

  /// The steps, numbered by the caller; code between backticks.
  final List<String> steps;

  /// The link at the foot (`Guide: docs/operations.md › Warm standby ›`).
  final String? link;

  @override
  List<Object?> get props => [title, body, stepsTitle, steps, link];
}

/// An empty state that says what is missing and how it is set up elsewhere:
/// a dashed card with the steps (board `SystemAvailNone`). It offers no
/// control: the steps are done on the hosts.
class GuideCard extends StatelessWidget {
  const GuideCard({required this.vm, this.onLink, super.key});

  final GuideCardVm vm;
  final VoidCallback? onLink;

  static const _pair = '''
<svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.6"
  stroke-linecap="round" stroke-linejoin="round">
  <rect x="2" y="5" width="8" height="14" rx="2"/>
  <rect x="14" y="5" width="8" height="14" rx="2" stroke-dasharray="3 3"/>
  <path d="M10 12h4"/>
</svg>''';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: CustomPaint(
        painter: _Dashed(color: c.line3, fill: c.ground1),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 16,
            children: [
              Row(
                spacing: 12,
                children: [
                  SvgPicture.string(
                    _pair,
                    width: 28,
                    height: 28,
                    colorFilter: ColorFilter.mode(c.text4, BlendMode.srcIn),
                  ),
                  Expanded(
                    child: Text(
                      vm.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: .w600,
                        color: c.text1,
                      ),
                    ),
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: CodeText(
                  vm.body,
                  style: TextStyle(fontSize: 14, height: 1.6, color: c.text2),
                ),
              ),
              Column(
                crossAxisAlignment: .start,
                spacing: 8,
                children: [
                  Text(
                    vm.stepsTitle,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: .w600,
                      color: c.text1,
                    ),
                  ),
                  for (final s in vm.steps)
                    CodeText(
                      s,
                      codeColor: c.text1,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: c.text3,
                      ),
                    ),
                ],
              ),
              if (vm.link case final l?)
                InkWell(
                  onTap: onLink,
                  child: Text(
                    l,
                    style: TextStyle(fontSize: 13, color: c.emberSoft),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  const _Dashed({required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(AppRadii.panel),
    );
    canvas.drawRRect(box, Paint()..color = fill);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in (Path()..addRRect(box)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color || old.fill != fill;
}
