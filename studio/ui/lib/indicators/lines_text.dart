import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// A text on one line that says when it holds more (owner's finding
/// 2026-11-11: a two-line CSV read as one line): the first line, cut with
/// an ellipsis, then a small mark `↲ +N` with the count of the lines after
/// it. The whole text (at most 20 lines and 2 000 characters,
/// [clipTip]) is the tooltip of the mark, and of the line when it is cut;
/// a click on the mark calls [onOpen] (the value viewer).
class LinesText extends StatelessWidget {
  const LinesText(
    this.text, {
    required this.style,
    this.textAlign = TextAlign.start,
    this.onOpen,
    super.key,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  /// Opens the whole text; null: the mark only says it.
  final VoidCallback? onOpen;

  /// How many lines [text] has after its first.
  static int moreLines(String text) => '\n'.allMatches(text).length;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nl = text.indexOf('\n');
    final first = nl < 0 ? text : text.substring(0, nl);
    final more = nl < 0 ? 0 : moreLines(text);
    final line = LayoutBuilder(
      builder: (context, box) {
        final shown = Text(
          first,
          maxLines: 1,
          overflow: .ellipsis,
          textAlign: textAlign,
          style: style,
        );
        // No glyph is wider than its size: a short line fits unmeasured
        // (canvas rows are built on every frame of a drag).
        final size = style.fontSize ?? 14;
        if (more > 0 ||
            !box.maxWidth.isFinite ||
            first.length * size <= box.maxWidth) {
          return shown;
        }
        // A line that is cut shows the whole of it in a tooltip.
        final p = TextPainter(
          text: TextSpan(
            text: first,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: box.maxWidth);
        final cut = p.didExceedMaxLines;
        p.dispose();
        return cut
            ? Tooltip(
                message: clipTip(text),
                waitDuration: const Duration(milliseconds: 500),
                child: shown,
              )
            : shown;
      },
    );
    if (more == 0) {
      return line;
    }
    // In a narrow cell the mark is `+N` alone, so the line keeps room.
    Widget mark({required bool narrow}) => Tooltip(
      message: clipTip(text),
      waitDuration: const Duration(milliseconds: 300),
      child: Semantics(
        button: onOpen != null,
        label: S.current.moreLines(more),
        child: MouseRegion(
          cursor: onOpen == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('lines-mark'),
            onTap: onOpen,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: narrow ? 3 : 5),
              decoration: BoxDecoration(
                color: c.ground4,
                border: .all(color: c.line2),
                borderRadius: Radii.chip,
              ),
              child: Text(
                narrow ? '+$more' : '↲ +$more',
                maxLines: 1,
                style: mono(size: 10, color: c.text2).copyWith(height: 1.4),
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 120;
        return Row(
          spacing: narrow ? 3 : 5,
          mainAxisAlignment: textAlign == TextAlign.right ? .end : .start,
          children: [
            Flexible(child: line),
            mark(narrow: narrow),
          ],
        );
      },
    );
  }
}

/// [s] cut for a tooltip: at most 20 lines and 2 000 characters, `…` after
/// what is cut. A tooltip of 512 KiB would hang the frame that lays it out.
String clipTip(String s) {
  var t = s.length > 2000 ? s.substring(0, 2000) : s;
  final lines = t.split('\n');
  if (lines.length > 20) {
    t = lines.take(20).join('\n');
  }
  return t.length < s.length ? '$t\n…' : t;
}
