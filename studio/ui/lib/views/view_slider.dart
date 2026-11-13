import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// What [ViewSlider] draws: the label, the point's value now (null when it
/// has none), the range and the step.
final class ViewSliderVm extends Equatable {
  const ViewSliderVm({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step,
    this.unit = '',
    this.decimals = 1,
    this.enabled = true,
  });

  final String label;
  final double? value;
  final double min;
  final double max;
  final double? step;
  final String unit;
  final int decimals;
  final bool enabled;

  @override
  List<Object?> get props => [
    label,
    value,
    min,
    max,
    step,
    unit,
    decimals,
    enabled,
  ];
}

/// The `Slider` part of a view. While the thumb is dragged it shows the
/// value under the finger; on release it reports the value once
/// ([onCommit]) and goes back to the point's own value, so what it shows
/// afterwards is what the device read back, never an optimistic copy.
class ViewSlider extends StatefulWidget {
  const ViewSlider({required this.vm, required this.onCommit, super.key});

  final ViewSliderVm vm;

  /// The value the user let go of, already on a step.
  final ValueChanged<double> onCommit;

  @override
  State<ViewSlider> createState() => _ViewSliderState();
}

class _ViewSliderState extends State<ViewSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ViewScope.densityOf(context);
    final vm = widget.vm;
    final enabled = vm.enabled && vm.value != null && vm.max > vm.min;
    final shown = (_drag ?? vm.value ?? vm.min).clamp(vm.min, vm.max);
    final step = vm.step;
    final divisions = step != null && step > 0 && vm.max > vm.min
        ? ((vm.max - vm.min) / step).round()
        : null;
    final figures = _drag == null && vm.value == null
        ? '—'
        : shown.toStringAsFixed(vm.decimals);
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                vm.label,
                maxLines: 1,
                overflow: .ellipsis,
                style: boardText(size: d.label, color: c.text3),
              ),
            ),
            Text(
              vm.unit.isEmpty ? figures : '$figures ${vm.unit}',
              style: boardText(
                size: d.label,
                weight: .w500,
                color: _drag == null ? c.text1 : c.emberSoft,
                code: true,
              ),
            ),
          ],
        ),
        SizedBox(
          height: d.button,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: c.ember,
              inactiveTrackColor: c.ground4,
              disabledActiveTrackColor: c.muted,
              disabledInactiveTrackColor: c.ground3,
              thumbColor: c.ember,
              disabledThumbColor: c.muted,
              overlayColor: c.ember.withValues(alpha: 0.12),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
              showValueIndicator: .never,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: d.button / 5,
              ),
            ),
            child: Slider(
              value: shown,
              min: vm.min,
              max: vm.max > vm.min ? vm.max : vm.min + 1,
              divisions: divisions,
              onChanged: enabled ? (v) => setState(() => _drag = v) : null,
              onChangeEnd: enabled
                  ? (v) {
                      setState(() => _drag = null);
                      if (v != vm.value) {
                        widget.onCommit(v);
                      }
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
