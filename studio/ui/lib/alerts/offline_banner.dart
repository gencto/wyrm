import 'package:material_ui/material_ui.dart';

import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// Shown under the top bar while the gateway socket is gone: the client
/// reconnects by itself; values on screen are the last ones received.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: .infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.warnTint,
        border: Border(bottom: BorderSide(color: c.warnLine)),
      ),
      child: Row(
        spacing: 10,
        children: [
          StateMark(mark: Mark.ring, color: c.warn),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: FontSizes.md, color: c.warn),
            ),
          ),
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.warn),
          ),
        ],
      ),
    );
  }
}
