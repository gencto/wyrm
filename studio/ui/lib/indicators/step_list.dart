import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import 'app_icon.dart';

/// The stepper of Add a link: numbered steps, the current one in ember,
/// the done ones ticked.
class StepList extends StatelessWidget {
  const StepList({
    required this.steps,
    required this.current,
    this.onStep,
    super.key,
  });

  final List<String> steps;

  /// 1-based.
  final int current;

  /// Going back to a done step; null when steps cannot be picked.
  final ValueChanged<int>? onStep;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: .center,
      children: [
        for (var i = 1; i <= steps.length; i++) ...[
          InkWell(
            onTap: onStep != null && i < current ? () => onStep!(i) : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: .min,
                spacing: 8,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: .center,
                    decoration: BoxDecoration(
                      shape: .circle,
                      color: i == current
                          ? c.ember
                          : (i < current ? c.goodTint : c.ground4),
                      border: i > current ? Border.all(color: c.line3) : null,
                    ),
                    child: i < current
                        ? AppIcon('ui_check', size: 14, color: c.good)
                        : Text(
                            '$i',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: .w600,
                              color: i == current ? c.onEmber : c.text3,
                            ),
                          ),
                  ),
                  Text(
                    steps[i - 1],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == current ? .w600 : .w400,
                      color: i == current ? c.text1 : c.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i < steps.length) Container(width: 24, height: 1, color: c.line2),
        ],
      ],
    );
  }
}
