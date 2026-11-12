import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import 'app_icon.dart';

/// One step of a wizard: its title and what was answered in it.
final class StepVm extends Equatable {
  const StepVm({required this.title, this.sub = ''});

  final String title;

  /// `now` for the current step, the answer for a done one.
  final String sub;

  @override
  List<Object?> get props => [title, sub];
}

/// The vertical steps of Add a link (left column): a numbered ring, done
/// ones ticked in teal, the current one in ember on the ember tint.
class StepRail extends StatelessWidget {
  const StepRail({
    required this.steps,
    required this.current,
    this.onStep,
    super.key,
  });

  final List<StepVm> steps;

  /// 1-based.
  final int current;

  /// Back to a done step; null when no step can be picked (after install).
  final ValueChanged<int>? onStep;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 4,
      children: [
        for (var i = 1; i <= steps.length; i++)
          Opacity(
            opacity: i > current ? 0.55 : 1,
            child: InkWell(
              onTap: onStep != null && i < current ? () => onStep!(i) : null,
              borderRadius: Radii.control,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: i == current ? c.emberTint : null,
                  borderRadius: Radii.control,
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: .center,
                      decoration: BoxDecoration(
                        shape: .circle,
                        color: i < current ? c.goodTint : null,
                        border: .all(
                          color: i < current
                              ? c.good
                              : (i == current ? c.ember : c.line3),
                          width: 1.5,
                        ),
                      ),
                      child: i < current
                          ? AppIcon('ui_check', size: 14, color: c.good)
                          : Text(
                              '$i',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: .w600,
                                color: i < current
                                    ? c.good
                                    : (i == current ? c.emberSoft : c.text4),
                              ),
                            ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            steps[i - 1].title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: i == current ? .w600 : .w400,
                              color: i <= current ? c.text1 : c.text3,
                            ),
                          ),
                          if (steps[i - 1].sub.isNotEmpty)
                            Text(
                              steps[i - 1].sub,
                              overflow: .ellipsis,
                              style: TextStyle(fontSize: 12, color: c.text4),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
