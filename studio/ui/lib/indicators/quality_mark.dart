import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import 'app_icon.dart';

/// A state word with its mark, inline (a table cell, a tree row, a header).
final class QualityMarkVm extends Equatable {
  const QualityMarkVm({
    required this.label,
    required this.tone,
    this.mark = Mark.dot,
  });

  final String label;
  final Tone tone;
  final Mark mark;

  @override
  List<Object?> get props => [label, tone, mark];
}

/// `● good`, `○ uncertain`, `○ not applied`: the word in the tone's colour,
/// the mark differing in shape.
class QualityMark extends StatelessWidget {
  const QualityMark({required this.vm, this.size = 13, super.key});

  final QualityMarkVm vm;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context.colors, vm.tone);
    return Row(
      mainAxisSize: .min,
      spacing: 6,
      children: [
        StateMark(mark: vm.mark, color: color),
        if (vm.label.isNotEmpty)
          Flexible(
            child: Text(
              vm.label,
              overflow: .ellipsis,
              style: TextStyle(fontSize: size, color: color),
            ),
          ),
      ],
    );
  }
}

/// The foreground colour of [tone].
Color toneColor(AppColors c, Tone tone) => switch (tone) {
  .good => c.good,
  .warn => c.warn,
  .bad => c.bad,
  .ember => c.emberSoft,
  .neutral => c.text4,
};

/// The tinted ground of [tone].
Color toneTint(AppColors c, Tone tone) => switch (tone) {
  .good => c.goodTint,
  .warn => c.warnTint,
  .bad => c.badTint,
  .ember => c.emberTint,
  .neutral => c.ground4,
};

/// The border of a block in [tone].
Color toneLine(AppColors c, Tone tone) => switch (tone) {
  .good => c.goodLine,
  .warn => c.warnLine,
  .bad => c.badLine,
  .ember => c.emberLine,
  .neutral => c.line2,
};

/// The mark alone, 8 px.
class StateMark extends StatelessWidget {
  const StateMark({
    required this.mark,
    required this.color,
    this.size = 8,
    super.key,
  });

  final Mark mark;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => switch (mark) {
    .none => const SizedBox.shrink(),
    .cross => AppIcon('ui_close', size: size + 4, color: color),
    .check => AppIcon('ui_check', size: size + 4, color: color),
    .dot || .ring || .dashed => CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(mark, color),
    ),
  };
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.mark, this.color);

  final Mark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    switch (mark) {
      case .dot:
        canvas.drawCircle(center, r, Paint()..color = color);
      case .ring:
        canvas.drawCircle(
          center,
          r - 1,
          Paint()
            ..color = color
            ..style = .stroke
            ..strokeWidth = 2,
        );
      case .dashed:
        final paint = Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = 2;
        const n = 6;
        for (var i = 0; i < n; i++) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: r - 1),
            i * 2 * 3.14159 / n,
            3.14159 / n,
            false,
            paint,
          );
        }
      case .cross || .check || .none:
        break;
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.color != color;
}
