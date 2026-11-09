import 'package:flutter/material.dart';

import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';

/// A checkbox 16 in ember and its label (13, `text2`), 10 apart — the
/// log-in's `Remember the gateway and user on this computer`. The whole row
/// toggles.
class CheckRow extends StatelessWidget {
  const CheckRow({required this.vm, required this.label, super.key});

  final FieldVm<bool> vm;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = vm.value;
    return Semantics(
      checked: on,
      enabled: vm.enabled,
      child: InkWell(
        onTap: vm.enabled ? () => vm.onChanged(!on) : null,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 16,
              height: 16,
              // The system checkbox's own margin (3 px, 4 on the left).
              margin: const EdgeInsets.fromLTRB(4, 3, 3, 3),
              decoration: BoxDecoration(
                color: on ? c.ember : c.ground2,
                borderRadius: const BorderRadius.all(Radius.circular(3)),
                border: on ? null : .all(color: c.line3),
              ),
              child: on ? CustomPaint(painter: _Tick(c.onEmber)) : null,
            ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: c.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tick of a checked box, as the system draws it on an accent colour.
class _Tick extends CustomPainter {
  const _Tick(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 16;
    canvas.drawPath(
      Path()
        ..moveTo(3.5 * k, 8.2 * k)
        ..lineTo(6.6 * k, 11.2 * k)
        ..lineTo(12.5 * k, 4.8 * k),
      Paint()
        ..color = color
        ..style = .stroke
        ..strokeWidth = 2 * k
        ..strokeCap = .round
        ..strokeJoin = .round,
    );
  }

  @override
  bool shouldRepaint(_Tick old) => old.color != color;
}
