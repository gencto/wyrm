import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// What [ViewValue] draws: a label, the figures already written with their
/// decimals, the unit, and what the value says about its point.
final class ViewValueVm extends Equatable {
  const ViewValueVm({
    required this.label,
    required this.value,
    this.unit = '',
    this.state = ViewState.normal,
    this.size = ViewSize.m,
    this.note = '',
  });

  final String label;

  /// The figures; `—` when there is no value.
  final String value;
  final String unit;
  final ViewState state;
  final ViewSize size;

  /// One line under the figures (`uncertain`, `no data`).
  final String note;

  @override
  List<Object?> get props => [label, value, unit, state, size, note];
}

/// The `Value` part of a view: one figure of a point. The size of the
/// figures follows the density of where it is shown, the colour follows the
/// state; a document chooses neither.
class ViewValue extends StatelessWidget {
  const ViewValue({required this.vm, super.key});

  final ViewValueVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ViewScope.densityOf(context);
    final figures = d.value * vm.size.scale;
    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      spacing: 4,
      children: [
        Text(
          vm.label,
          maxLines: 1,
          overflow: .ellipsis,
          style: boardText(size: d.label, color: c.text3),
        ),
        Row(
          crossAxisAlignment: .baseline,
          textBaseline: .alphabetic,
          mainAxisSize: .min,
          spacing: 6,
          children: [
            Flexible(
              child: Text(
                vm.value,
                maxLines: 1,
                overflow: .ellipsis,
                style: boardText(
                  size: figures,
                  weight: .w500,
                  color: vm.state.of(c),
                  code: true,
                ),
              ),
            ),
            if (vm.unit.isNotEmpty)
              Text(
                vm.unit,
                style: boardText(size: d.label, color: c.text4, code: true),
              ),
          ],
        ),
        if (vm.note.isNotEmpty)
          Text(
            vm.note,
            style: boardText(size: 12, color: vm.state.of(c)),
          ),
      ],
    );
  }
}
