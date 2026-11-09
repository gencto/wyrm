import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// A key in mono, shortened in the middle when it does not fit (the start
/// says where, the end says what), copied on a long press.
class KeyText extends StatelessWidget {
  const KeyText(
    this.text, {
    this.size = 13,
    this.color,
    this.weight = FontWeight.w400,
    this.copyable = true,
    super.key,
  });

  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final style = mono(
      size: size,
      weight: weight,
      color: color ?? context.colors.text1,
    );
    final body = LayoutBuilder(
      builder: (context, box) => Text(
        middleEllipsis(text, style, box.maxWidth),
        maxLines: 1,
        softWrap: false,
        style: style,
      ),
    );
    if (!copyable) {
      return body;
    }
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onLongPress: () => Clipboard.setData(ClipboardData(text: text)),
        child: body,
      ),
    );
  }
}

/// [text] shortened with `…` in the middle to fit [width] in [style].
String middleEllipsis(String text, TextStyle style, double width) {
  if (!width.isFinite) {
    return text;
  }
  double measure(String s) => (TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: .ltr,
    maxLines: 1,
  )..layout()).width;
  if (measure(text) <= width) {
    return text;
  }
  var lo = 0;
  var hi = text.length;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    final head = (mid + 1) ~/ 2;
    final tail = mid ~/ 2;
    final s =
        '${text.substring(0, head)}…${text.substring(text.length - tail)}';
    if (measure(s) <= width) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  final head = (lo + 1) ~/ 2;
  final tail = lo ~/ 2;
  return '${text.substring(0, head)}…${text.substring(text.length - tail)}';
}
