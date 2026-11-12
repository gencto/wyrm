import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/sys_tile.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One record of a log, as [LogTable] draws it.
final class LogRowVm extends Equatable {
  const LogRowVm({
    required this.time,
    required this.level,
    required this.target,
    required this.message,
  });

  /// `02:01:44`.
  final String time;

  /// `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE`.
  final String level;
  final String target;
  final String message;

  @override
  List<Object?> get props => [time, level, target, message];
}

/// Board `SystemLog`: log records in four columns (time, level, target,
/// message), `ERROR` and `WARN` rows on their own ground.
///
/// A row is one line. Rows wider than the box scroll inside it, sideways,
/// and more rows than [maxHeight] holds scroll inside it too: the page
/// never scrolls for the log. With no rows it shows [message] (`No lines at
/// this level.`, or the broker's refusal in [bad] colour).
class LogTable extends StatefulWidget {
  const LogTable({
    required this.rows,
    this.message = '',
    this.bad = false,
    this.maxHeight = 560,
    super.key,
  });

  final List<LogRowVm> rows;
  final String message;
  final bool bad;
  final double maxHeight;

  static const double rowHeight = 30;

  @override
  State<LogTable> createState() => _LogTableState();
}

class _LogTableState extends State<LogTable> {
  final _across = ScrollController();
  final _down = ScrollController();

  @override
  void dispose() {
    _across.dispose();
    _down.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == .dark;
    final ground = Color.alphaBlend(
      Colors.black.withValues(alpha: dark ? 0.2 : 0.03),
      c.ground0,
    );
    final rows = widget.rows;
    final Widget body;
    if (rows.isEmpty || widget.bad) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: SelectableText(
          widget.message,
          style: mono(size: 12, color: widget.bad ? c.badText : c.text4),
        ),
      );
    } else {
      final longest = rows.fold(0, (n, r) => math.max(n, r.message.length));
      // Columns 80 · 56 · 170 · the message, 12 between, 16 on each side;
      // a mono 12 glyph is 7.2 wide.
      final wide = 32 + 80 + 56 + 170 + 36 + longest * 7.25 + 8;
      final height = math.min(
        rows.length * LogTable.rowHeight + 12,
        widget.maxHeight,
      );
      body = SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) => Scrollbar(
            controller: _across,
            child: SingleChildScrollView(
              controller: _across,
              scrollDirection: .horizontal,
              child: SizedBox(
                width: math.max(box.maxWidth, math.max(wide, 760)),
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _down,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemExtent: LogTable.rowHeight,
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _row(c, dark, rows[i]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        color: ground,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      child: body,
    );
  }

  Widget _row(AppColors c, bool dark, LogRowVm r) {
    final (Color level, Color? ground) = switch (r.level) {
      'ERROR' => (
        c.bad,
        dark ? const Color(0xFF1A1110) : c.badTint,
      ),
      'WARN' => (
        c.warn,
        dark ? const Color(0xFF16140C) : c.warnTint,
      ),
      'INFO' => (c.text3, null),
      _ => (SysTile.keyColor(c), null),
    };
    Text cell(String s, Color color, {FontWeight weight = .w400}) => Text(
      s,
      maxLines: 1,
      softWrap: false,
      overflow: .clip,
      style: mono(size: 12, color: color, weight: weight),
    );
    return Container(
      color: ground,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        spacing: 12,
        children: [
          SizedBox(width: 80, child: cell(r.time, c.text4)),
          SizedBox(width: 56, child: cell(r.level, level, weight: .w600)),
          SizedBox(width: 170, child: cell(r.target, c.text3)),
          Expanded(child: cell(r.message, c.text2)),
        ],
      ),
    );
  }
}
