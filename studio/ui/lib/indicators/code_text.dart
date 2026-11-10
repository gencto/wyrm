import 'package:flutter/material.dart';

import '../theme/typography.dart';

/// A sentence with code in it: what stands between two backticks is set in
/// the mono family, at the sentence's size (`sys/log_level`, `data_dir`).
///
/// The text comes resolved from the connector; the backticks are its only
/// markup. A backtick without its pair is written as it is.
class CodeText extends StatelessWidget {
  const CodeText(
    this.text, {
    required this.style,
    this.codeColor,
    this.maxLines,
    super.key,
  });

  final String text;
  final TextStyle style;

  /// The colour of the code parts; the sentence's own when null.
  final Color? codeColor;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final parts = text.split('`');
    if (parts.length.isEven) {
      return Text(text, style: style, maxLines: maxLines);
    }
    return Text.rich(
      TextSpan(
        children: [
          for (final (i, p) in parts.indexed)
            if (p.isNotEmpty)
              TextSpan(
                text: p,
                style: i.isOdd
                    ? TextStyle(
                        fontFamily: AppFonts.mono,
                        color: codeColor ?? style.color,
                      )
                    : null,
              ),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
