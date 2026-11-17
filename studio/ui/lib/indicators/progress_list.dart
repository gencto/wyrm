import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/sizes.dart';
import '../theme/typography.dart';
import 'app_icon.dart';
import 'app_icon_view.dart';
import 'quality_mark.dart';

/// Where one row of a progress list is.
enum ProgressState { done, now, failed, waiting, skipped }

/// One row: what is done, being done, failed or still waiting.
final class ProgressRowVm extends Equatable {
  const ProgressRowVm({
    required this.label,
    required this.state,
    this.detail,
  });

  final String label;
  final ProgressState state;

  /// A mono line under the label (a key, the broker's answer).
  final String? detail;

  @override
  List<Object?> get props => [label, state, detail];
}

/// Installs and plan runs: one row per step with its state mark.
class ProgressList extends StatelessWidget {
  const ProgressList({required this.rows, super.key});

  final List<ProgressRowVm> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        for (final r in rows)
          Row(
            crossAxisAlignment: .start,
            spacing: 10,
            children: [
              SizedBox(
                width: 16,
                height: 20,
                child: Center(child: _mark(c, r.state)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      r.label,
                      style: TextStyle(
                        fontSize: FontSizes.md,
                        fontWeight: r.state == .now ? .w600 : .w400,
                        color: switch (r.state) {
                          .waiting || .skipped => c.text4,
                          .failed => c.badText,
                          _ => c.text1,
                        },
                      ),
                    ),
                    if (r.detail case final d?)
                      Text(
                        d,
                        style: mono(size: FontSizes.sm, color: c.text3),
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _mark(AppColors c, ProgressState s) => switch (s) {
    .done => AppIconView(AppIcon.uiCheck, size: IconSizes.md, color: c.good),
    .now => SizedBox.square(
      dimension: AppSizes.inlineSpinner,
      child: CircularProgressIndicator(strokeWidth: 2, color: c.ember),
    ),
    .failed => StateMark(mark: Mark.cross, color: c.bad),
    .waiting => StateMark(mark: Mark.ring, color: c.muted),
    .skipped => StateMark(mark: Mark.dashed, color: c.muted),
  };
}
