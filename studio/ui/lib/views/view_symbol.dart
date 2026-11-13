import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// What [ViewSymbol] draws: the kind of equipment, its state, and one
/// figure beside it.
final class ViewSymbolVm extends Equatable {
  const ViewSymbolVm({
    required this.kind,
    required this.state,
    required this.word,
    this.value = '',
    this.unit = '',
    this.size = ViewSize.m,
  });

  /// `pump` is drawn; any other kind is a plain circle.
  final String kind;
  final ViewState state;

  /// `running`, `stopped`, `fault`, `no data`.
  final String word;
  final String value;
  final String unit;
  final ViewSize size;

  @override
  List<Object?> get props => [kind, state, word, value, unit, size];
}

/// The `Symbol` part of a view: a process symbol whose colour is its state
/// (running `good`, fault `bad`, stopped `muted`) with the state in words
/// beside it.
class ViewSymbol extends StatelessWidget {
  const ViewSymbol({required this.vm, super.key});

  final ViewSymbolVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ViewScope.densityOf(context);
    final color = vm.state.of(c);
    final side = d.value * 1.8 * vm.size.scale;
    return Row(
      mainAxisSize: .min,
      spacing: 12,
      children: [
        CustomPaint(
          size: Size.square(side),
          painter: _SymbolPainter(
            kind: vm.kind,
            color: color,
            filled: vm.state == .on || vm.state == .alarm,
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              Text(
                vm.word,
                style: boardText(size: d.label, weight: .w500, color: color),
              ),
              if (vm.value.isNotEmpty)
                Text(
                  vm.unit.isEmpty ? vm.value : '${vm.value} ${vm.unit}',
                  style: boardText(size: d.label, color: c.text3, code: true),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SymbolPainter extends CustomPainter {
  const _SymbolPainter({
    required this.kind,
    required this.color,
    required this.filled,
  });

  final String kind;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = size.width / 16;
    final center = size.center(.zero);
    final r = size.width / 2 - line.strokeWidth;
    canvas.drawCircle(center, r, line);
    if (kind != 'pump') {
      return;
    }
    // ISO 14617 pump: a circle with a triangle that points downstream.
    final tri = Path()
      ..moveTo(center.dx - r * 0.5, center.dy - r * 0.62)
      ..lineTo(center.dx + r * 0.78, center.dy)
      ..lineTo(center.dx - r * 0.5, center.dy + r * 0.62)
      ..close();
    canvas.drawPath(
      tri,
      filled ? (Paint()..color = color) : line,
    );
  }

  @override
  bool shouldRepaint(_SymbolPainter old) =>
      old.kind != kind || old.color != color || old.filled != filled;
}
