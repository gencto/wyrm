import 'package:material_ui/material_ui.dart';

import '../inputs/switch_row.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// The `Switch` part of a view: a label and the toggle of the design
/// system, as tall as a button of the density. [value] is the point's own
/// value (null when it has none: the switch is off and does not react); a
/// tap reports the other value and changes nothing by itself.
class ViewSwitch extends StatelessWidget {
  const ViewSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool? value;

  /// Null when the switch cannot be used.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = ViewScope.densityOf(context);
    final enabled = onChanged != null && value != null;
    return SizedBox(
      height: d.button,
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: .ellipsis,
              style: boardText(
                size: d.label,
                color: enabled ? c.text2 : c.text4,
              ),
            ),
          ),
          AppSwitch(
            value: value ?? false,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
