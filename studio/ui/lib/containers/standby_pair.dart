import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/code_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What [StandbyPair] draws: the active broker, its warm standby and what
/// goes from one to the other.
final class StandbyPairVm extends Equatable {
  const StandbyPairVm({
    required this.activeLabel,
    required this.activeName,
    required this.activeNote,
    required this.flow,
    required this.every,
    required this.standbyLabel,
    required this.standbyName,
    required this.standbyNote,
    this.behind = false,
  });

  final String activeLabel;
  final String activeName;
  final String activeNote;

  /// What the standby pulls (`WAL, files, storage, history`).
  final String flow;
  final String every;
  final String standbyLabel;
  final String standbyName;
  final String standbyNote;

  /// The standby is behind or moved a fork aside: amber, a dashed line.
  final bool behind;

  @override
  List<Object?> get props => [
    activeLabel,
    activeName,
    activeNote,
    flow,
    every,
    standbyLabel,
    standbyName,
    standbyNote,
    behind,
  ];
}

/// Boards `SystemAvail` and `SystemAvailLag`: the pair of brokers of a warm
/// standby (ADR 0036). It shows; it changes nothing.
class StandbyPair extends StatelessWidget {
  const StandbyPair({required this.vm, super.key});

  final StandbyPairVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == .dark;
    final okLine = dark ? const Color(0xFF2E5A50) : c.goodLine;
    final okFill = dark ? const Color(0xFF10201C) : c.goodTint;
    final lagFill = dark ? const Color(0xFF211D10) : c.warnTint;
    final tone = vm.behind ? c.warn : c.good;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.panel,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final mid = (box.maxWidth * 0.2).clamp(140.0, 220.0);
          return Row(
            spacing: 16,
            children: [
              Expanded(
                child: _broker(
                  c,
                  line: okLine,
                  fill: okFill,
                  tone: c.good,
                  label: vm.activeLabel,
                  name: vm.activeName,
                  note: vm.activeNote,
                ),
              ),
              SizedBox(
                width: mid,
                child: Column(
                  spacing: 6,
                  children: [
                    SizedBox(
                      height: 24,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _Arrow(color: tone, dashed: vm.behind),
                      ),
                    ),
                    Text(
                      vm.flow,
                      textAlign: .center,
                      style: TextStyle(fontSize: 12, color: c.text3),
                    ),
                    Text(
                      vm.every,
                      textAlign: .center,
                      style: TextStyle(fontSize: 12, color: c.text4),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _broker(
                  c,
                  line: vm.behind ? c.warnLine : okLine,
                  fill: vm.behind ? lagFill : okFill,
                  tone: tone,
                  label: vm.standbyLabel,
                  name: vm.standbyName,
                  note: vm.standbyNote,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _broker(
    AppColors c, {
    required Color line,
    required Color fill,
    required Color tone,
    required String label,
    required String name,
    required String note,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: fill,
      border: .all(color: line),
      borderRadius: Radii.card,
    ),
    child: Column(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: .w600,
            letterSpacing: 0.72,
            color: tone,
          ),
        ),
        Text(
          name,
          maxLines: 1,
          overflow: .ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 16,
            color: c.text1,
          ),
        ),
        CodeText(
          note,
          style: TextStyle(fontSize: 13, height: 1.5, color: c.text3),
        ),
      ],
    ),
  );
}

class _Arrow extends CustomPainter {
  const _Arrow({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final y = size.height / 2;
    // The board draws it in a 200-wide box: from 4 to 190, the head at 184–192.
    final k = size.width / 200;
    final from = 4 * k;
    final to = 190 * k;
    if (dashed) {
      for (var x = from; x < to; x += 11) {
        canvas.drawLine(Offset(x, y), Offset((x + 6).clamp(0, to), y), p);
      }
    } else {
      canvas.drawLine(Offset(from, y), Offset(to, y), p);
    }
    canvas.drawPath(
      Path()
        ..moveTo(184 * k, y - 6)
        ..lineTo(192 * k, y)
        ..lineTo(184 * k, y + 6),
      p,
    );
  }

  @override
  bool shouldRepaint(_Arrow old) => old.color != color || old.dashed != dashed;
}
