import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';

/// The uppercase label of a group (`REGISTER`, `POLLING`): 12/600, +6 %.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.trailing, super.key});

  final String text;

  /// Right-aligned beside it (`● staged · was 1 s`).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: .w600,
            letterSpacing: 0.72,
            color: context.colors.text3,
          ),
        ),
      ),
      ?trailing,
    ],
  );
}
