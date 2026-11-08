import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'app_icon.dart';

/// The full key of the node on screen in mono 13, its last segment in
/// text/1, and a 28 × 28 Copy key button (docs/design/specs/explorer.md
/// §3.1).
class KeyLine extends StatelessWidget {
  const KeyLine({
    required this.keyName,
    this.onCopy,
    this.copyLabel = 'Copy key',
    super.key,
  });

  /// `wy/<site>/downstream/…`.
  final String keyName;
  final VoidCallback? onCopy;
  final String copyLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cut = keyName.lastIndexOf('/') + 1;
    return Row(
      spacing: 8,
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              text: keyName.substring(0, cut),
              children: [
                TextSpan(
                  text: keyName.substring(cut),
                  style: TextStyle(color: c.text1),
                ),
              ],
            ),
            maxLines: 1,
            overflow: .ellipsis,
            style: mono(color: c.text4),
          ),
        ),
        if (onCopy != null)
          Tooltip(
            message: copyLabel,
            child: InkWell(
              onTap: onCopy,
              borderRadius: Radii.segment,
              child: SizedBox.square(
                dimension: 28,
                child: Center(
                  child: AppIcon('ui_copy', size: 14, color: c.text4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
