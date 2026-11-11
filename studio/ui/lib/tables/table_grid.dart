import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../indicators/lines_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'table_edits.dart';

/// A cell's own text, given by the app (a date of the time column `t`);
/// null: the grid writes the cell itself.
typedef CellTextOf = String? Function(String column, Object? cell);

/// How a cell is drawn, by what it holds.
enum _Kind { text, number, flag, nil, nested }

/// A cell as the grid shows it: the `text` on its one line, how many `more`
/// lines a text has, and the whole value as a `tip` when the line does not
/// say it all.
typedef _Shown = ({String text, _Kind kind, int more, String? tip});

/// A table in a grid (docs/studio.md §6.8): a sticky header of the column
/// names, a row number in the gutter, cells by type (a number right-aligned,
/// `null` dimmed, a map or a list as compact JSON with the whole of it in a
/// tooltip), each column as wide as its content within 56–320 and dragged
/// wider or narrower by its header's right edge; a filter over the rows
/// above it, `N of M rows` beside it. Only the rows in view are built, so
/// 10 000 rows scroll as smoothly as ten.
///
/// With [onChanged] it edits (owner request 2026-11-11): a click selects a
/// cell, arrows and Tab move; a double click, Enter or a typed character
/// edits it in place, Enter, Tab or an arrow up or down keeps the edit and
/// moves, Esc drops it; Delete empties the cell (`null`; an empty text with
/// [textCells]). A typed cell keeps its type ([typedCell]). `Add row` and
/// `Add column` add after the selection; the menu renames and removes; a
/// double click on a header renames it. What would pass the bounds of a
/// table (ADR 0044 §2, [TableBounds]) is refused and said in coral.
class TableGrid extends StatefulWidget {
  const TableGrid({
    required this.table,
    this.onChanged,
    this.cellText,
    this.textCells = false,
    this.renamable = true,
    this.onSubmit,
    super.key,
  });

  final TableDataVm table;

  /// The table as an edit leaves it; null: the grid only shows it.
  final ValueChanged<TableDataVm>? onChanged;

  /// A cell's own text; null for the grid's.
  final CellTextOf? cellText;

  /// Every cell is a text (a CSV): a typed cell stays the text typed.
  final bool textCells;

  /// Whether a column can be renamed (a CSV without a header names none).
  final bool renamable;

  /// ⌘/Ctrl+Enter in a cell: the edit is kept, then this (the viewer's
  /// Save).
  final VoidCallback? onSubmit;

  @override
  State<TableGrid> createState() => TableGridState();
}

/// The state of a [TableGrid]; [commit] keeps an edit in progress (the
/// viewer calls it before it saves).
class TableGridState extends State<TableGrid> {
  static const _rowH = 26.0;
  static const _headH = 30.0;
  static const _minW = 56.0;
  static const _maxW = 320.0;

  /// Rows read to fit the column widths.
  static const _sample = 500;

  final _h = ScrollController();
  final _v = ScrollController();
  final _focus = FocusNode(debugLabel: 'TableGrid');
  final _filter = TextEditingController();
  final _text = TextEditingController();
  final _textFocus = FocusNode(debugLabel: 'TableGrid cell');

  List<String>? _measured;
  var _widths = <double>[];
  final _dragged = <String, double>{};
  var _shown = <int>[];

  /// The selected cell: its row (an index of the table, not of the
  /// filtered rows) and column.
  (int, int)? _sel;
  var _editing = false;

  /// The column whose name is edited.
  int? _naming;
  String? _message;

  bool get _editable => widget.onChanged != null;
  TableDataVm get _t => widget.table;

  @override
  void initState() {
    super.initState();
    _refilter();
    _textFocus.addListener(() {
      // A click elsewhere keeps what was typed.
      if (!_textFocus.hasFocus && (_editing || _naming != null)) {
        commit();
      }
    });
  }

  @override
  void didUpdateWidget(TableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.table, widget.table)) {
      _refilter();
      if (_sel case (final r, final c)) {
        _sel = _t.rows.isEmpty || _t.columns.isEmpty
            ? null
            : (
                r.clamp(0, _t.rows.length - 1),
                c.clamp(0, _t.columns.length - 1),
              );
      }
      if (_naming case final n? when n >= _t.columns.length) {
        _naming = null;
      }
    }
  }

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    _focus.dispose();
    _filter.dispose();
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  // ---------- reading ----------

  _Shown _show(int c, Object? v) {
    if (widget.cellText?.call(_t.columns[c], v) case final own?) {
      return (text: own, kind: .number, more: 0, tip: '$v');
    }
    switch (v) {
      case null:
        return (text: 'null', kind: .nil, more: 0, tip: null);
      case bool():
        return (text: '$v', kind: .flag, more: 0, tip: null);
      case num():
        return (text: '$v', kind: .number, more: 0, tip: null);
      case final String s:
        final nl = s.indexOf('\n');
        if (nl < 0) {
          return (text: s, kind: .text, more: 0, tip: s.length > 40 ? s : null);
        }
        return (
          text: s.substring(0, nl),
          kind: .text,
          more: '\n'.allMatches(s).length,
          tip: clipTip(s),
        );
      case final Uint8List b:
        final hex = [
          for (final x in b.take(16)) x.toRadixString(16).padLeft(2, '0'),
        ].join(' ');
        return (
          text: b.length > 16 ? '$hex …' : hex,
          kind: .nested,
          more: 0,
          tip: S.current.sizeBytes(b.length),
        );
      case Map<Object?, Object?>() || List<Object?>():
        return (
          text: cellEditText(v),
          kind: .nested,
          more: 0,
          tip: clipTip(_pretty(v)),
        );
      default:
        return (text: '$v', kind: .text, more: 0, tip: null);
    }
  }

  static String _pretty(Object v) =>
      const JsonEncoder.withIndent('  ').convert(jsonSafe(v));

  void _refilter() {
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty) {
      _shown = List<int>.generate(_t.rows.length, (i) => i);
      return;
    }
    _shown = [
      for (var r = 0; r < _t.rows.length; r++)
        if (_matches(r, q)) r,
    ];
  }

  bool _matches(int r, String q) {
    for (var c = 0; c < _t.columns.length; c++) {
      final v = _t.cell(r, c);
      final own = widget.cellText?.call(_t.columns[c], v);
      if ((own ?? cellEditText(v)).toLowerCase().contains(q)) {
        return true;
      }
    }
    return false;
  }

  /// The widths of the columns: the header or the widest of the first
  /// [_sample] rows (cells are mono, so by their length), within
  /// [_minW]–[_maxW]; a dragged one as dragged.
  void _measure(BuildContext context) {
    if (identical(_measured, _t.columns) &&
        _widths.length == _t.columns.length) {
      return;
    }
    _measured = _t.columns;
    final base = DefaultTextStyle.of(context).style;
    final digits = TextPainter(
      text: TextSpan(text: '0000000000', style: base.merge(mono(size: 12))),
      textDirection: .ltr,
    )..layout();
    _charW = digits.width / 10;
    digits.dispose();
    final head = base.merge(_headStyle(null));
    final rows = _t.rows.length < _sample ? _t.rows.length : _sample;
    _widths = [
      for (final (c, name) in _t.columns.indexed)
        _dragged[name] ??
            () {
              var chars = 0;
              var marked = false;
              for (var r = 0; r < rows; r++) {
                final shown = _show(c, _t.cell(r, c));
                if (shown.text.length > chars) {
                  chars = shown.text.length;
                }
                marked = marked || shown.more > 0;
              }
              final p = TextPainter(
                text: TextSpan(text: name, style: head),
                textDirection: .ltr,
                maxLines: 1,
              )..layout();
              final w = p.width + 26;
              p.dispose();
              // The padding, the selection's frame, a mark `↲ +N`.
              final cells =
                  (chars > 60 ? 60 : chars) * _charW + 24 + (marked ? 40 : 0);
              return (w > cells ? w : cells).clamp(_minW, _maxW);
            }(),
    ];
  }

  /// The width of a character of a cell (mono 12), measured with the
  /// widths.
  var _charW = 7.2;

  double get _gutter => 18 + '${_t.rows.length}'.length * _charW;

  TextStyle _headStyle(Color? color) =>
      TextStyle(fontSize: 12, fontWeight: .w600, color: color);

  // ---------- editing ----------

  void _apply(TableEdit e, {VoidCallback? then}) {
    if (e.refused case final why?) {
      setState(() => _message = refusalText(why));
      return;
    }
    setState(() {
      _message = null;
      then?.call();
    });
    widget.onChanged?.call(e.table!);
  }

  /// The words of a refused edit.
  static String refusalText(TableRefusal why) => switch (why) {
    .rows => S.current.tableRefusedRows,
    .columns => S.current.tableRefusedColumns,
    .bytes => S.current.tableRefusedBytes,
    .name => S.current.tableRefusedName,
    .nameTaken => S.current.tableRefusedNameTaken,
  };

  void _begin([String? typed]) {
    final sel = _sel;
    if (!_editable || sel == null) {
      return;
    }
    final (r, c) = sel;
    _text.text = typed ?? cellEditText(_t.cell(r, c));
    _text.selection = .collapsed(offset: _text.text.length);
    setState(() {
      _editing = true;
      _naming = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) {
        _textFocus.requestFocus();
      }
    });
  }

  void _beginName(int c) {
    if (!_editable || !widget.renamable) {
      return;
    }
    _text.text = _t.columns[c];
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
    setState(() {
      _editing = false;
      _naming = c;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _naming != null) {
        _textFocus.requestFocus();
      }
    });
  }

  /// Keeps an edit in progress (a cell's text, a column's name); true when
  /// nothing is left in progress.
  bool commit({int dr = 0, int dc = 0}) {
    if (_naming case final n?) {
      final name = _text.text.trim();
      if (name == _t.columns[n]) {
        setState(() => _naming = null);
        _focus.requestFocus();
        return true;
      }
      final e = renameColumn(_t, n, name);
      if (e.refused != null) {
        _apply(e);
        return false;
      }
      final was = _t.columns[n];
      _apply(
        e,
        then: () {
          if (_dragged.remove(was) case final w?) {
            _dragged[name] = w;
          }
          _naming = null;
        },
      );
      _focus.requestFocus();
      return true;
    }
    final sel = _sel;
    if (!_editing || sel == null) {
      return true;
    }
    final (r, c) = sel;
    final was = _t.cell(r, c);
    final v = typedCell(_text.text, was, textOnly: widget.textCells);
    _editing = false;
    if (v.runtimeType != was.runtimeType ||
        cellEditText(v) != cellEditText(was)) {
      _apply(setCell(_t, r, c, v));
    } else {
      setState(() {});
    }
    _move(dr, dc);
    _focus.requestFocus();
    return true;
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _naming = null;
    });
    _focus.requestFocus();
  }

  void _clear() {
    if (_sel case (final r, final c) when _editable) {
      _apply(setCell(_t, r, c, widget.textCells ? '' : null));
    }
  }

  void _addRow() {
    final at = switch (_sel) {
      (final r, _) => r + 1,
      null => _t.rows.length,
    };
    _apply(
      addRow(_t, at: at),
      then: () => _sel = (at, _sel?.$2 ?? 0),
    );
    if (_filter.text.isNotEmpty) {
      // A new row matches no filter: show it.
      _filter.clear();
    }
  }

  void _removeRow() {
    if (_sel case (final r, _)) {
      _apply(removeRow(_t, r));
    }
  }

  void _addColumn() {
    final at = switch (_sel) {
      (_, final c) => c + 1,
      null => _t.columns.length,
    };
    final e = addColumn(_t, newColumnName(_t), at: at);
    _apply(e);
    if (e.table != null && widget.renamable) {
      // Name it at once.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && at < _t.columns.length) {
          _beginName(at);
        }
      });
    }
  }

  void _removeColumn() {
    if (_sel case (_, final c)) {
      _apply(removeColumn(_t, c));
    }
  }

  // ---------- moving ----------

  void _select(int r, int c) {
    if (_editing && _sel == (r, c)) {
      // A click in the cell being edited moves the caret.
      return;
    }
    if (_editing || _naming != null) {
      commit();
    }
    setState(() => _sel = (r, c));
    _focus.requestFocus();
  }

  void _move(int dr, int dc) {
    if (_shown.isEmpty || _t.columns.isEmpty) {
      return;
    }
    final sel = _sel;
    if (sel == null) {
      setState(() => _sel = (_shown.first, 0));
      _reveal();
      return;
    }
    final (r, c) = sel;
    final at = _shown.indexOf(r);
    final pos = ((at < 0 ? 0 : at) + dr).clamp(0, _shown.length - 1);
    setState(
      () => _sel = (_shown[pos], (c + dc).clamp(0, _t.columns.length - 1)),
    );
    _reveal();
  }

  /// Scrolls the selected cell into view.
  void _reveal() {
    final sel = _sel;
    if (sel == null) {
      return;
    }
    final (r, c) = sel;
    if (_v.hasClients) {
      final top = _shown.indexOf(r) * _rowH;
      final view = _v.position.viewportDimension;
      if (top < _v.offset) {
        _v.jumpTo(top);
      } else if (top + _rowH > _v.offset + view) {
        _v.jumpTo(top + _rowH - view);
      }
    }
    if (_h.hasClients) {
      var left = _gutter;
      for (var i = 0; i < c; i++) {
        left += _widths[i];
      }
      final right = left + _widths[c];
      final view = _h.position.viewportDimension;
      if (left - _gutter < _h.offset) {
        _h.jumpTo((left - _gutter).clamp(0, _h.position.maxScrollExtent));
      } else if (right > _h.offset + view) {
        _h.jumpTo((right - view).clamp(0, _h.position.maxScrollExtent));
      }
    }
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return .ignored;
    }
    if (_editing || _naming != null) {
      return .ignored;
    }
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final mod =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (mod) {
      return .ignored;
    }
    switch (k) {
      case LogicalKeyboardKey.arrowUp:
        _move(-1, 0);
      case LogicalKeyboardKey.arrowDown:
        _move(1, 0);
      case LogicalKeyboardKey.arrowLeft:
        _move(0, -1);
      case LogicalKeyboardKey.arrowRight:
        _move(0, 1);
      case LogicalKeyboardKey.tab:
        _move(0, shift ? -1 : 1);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.f2
          when _editable && _sel != null:
        _begin();
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace
          when _editable && _sel != null:
        _clear();
      default:
        final ch = e.character;
        if (_editable &&
            _sel != null &&
            ch != null &&
            ch.isNotEmpty &&
            ch.codeUnitAt(0) >= 0x20 &&
            ch.codeUnitAt(0) != 0x7f) {
          _begin(ch);
          return .handled;
        }
        return .ignored;
    }
    return .handled;
  }

  // ---------- drawing ----------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    _measure(context);
    final s = S.current;
    final total = _gutter + _widths.fold<double>(0, (a, w) => a + w);
    final noScrollbars = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);
    final filtered = _filter.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            spacing: 8,
            children: [
              SizedBox(
                width: 200,
                height: 30,
                child: TextField(
                  key: const ValueKey('table-filter'),
                  controller: _filter,
                  onChanged: (_) => setState(_refilter),
                  style: mono(size: 12, color: c.text1),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: s.tableFilter,
                    hintStyle: TextStyle(fontSize: 12, color: c.text4),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      child: AppIcon('ui_search', size: 14, color: c.text4),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  // The counts: of the table, or of what the filter keeps.
                  filtered
                      ? s.tableFiltered(_shown.length, _t.rows.length)
                      : '${s.sizeRows(_t.rows.length)} · '
                            '${s.sizeColumns(_t.columns.length)}',
                  key: const ValueKey('table-count'),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: 12, color: c.text3),
                ),
              ),
              if (_editable) ...[
                Button.quiet(
                  key: const ValueKey('table-add-row'),
                  label: s.tableAddRow,
                  icon: 'ui_add',
                  size: ButtonSize.small,
                  fontSize: 12,
                  inset: 8,
                  onPressed: _t.columns.isEmpty ? null : _addRow,
                ),
                Button.quiet(
                  key: const ValueKey('table-add-column'),
                  label: s.tableAddColumn,
                  icon: 'ui_add',
                  size: ButtonSize.small,
                  fontSize: 12,
                  inset: 8,
                  onPressed: _addColumn,
                ),
                _menu(context),
              ],
            ],
          ),
        ),
        if (_message case final m?)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              m,
              key: const ValueKey('table-refused'),
              style: TextStyle(fontSize: 12, color: c.badText),
            ),
          ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line1)),
            ),
            child: _t.columns.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _editable ? s.tableNoColumnsEdit : s.tableNoColumns,
                      style: mono(color: c.text4),
                    ),
                  )
                : Focus(
                    focusNode: _focus,
                    onKeyEvent: _key,
                    child: ScrollConfiguration(
                      behavior: noScrollbars,
                      child: Scrollbar(
                        controller: _v,
                        notificationPredicate: (n) => n.depth == 1,
                        child: Scrollbar(
                          controller: _h,
                          child: SingleChildScrollView(
                            controller: _h,
                            scrollDirection: .horizontal,
                            child: SizedBox(
                              width: total,
                              child: Column(
                                crossAxisAlignment: .stretch,
                                children: [
                                  _header(context),
                                  Expanded(
                                    child: _shown.isEmpty
                                        ? Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Text(
                                              s.tableNoRows,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: c.text4,
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            key: const ValueKey('table-rows'),
                                            controller: _v,
                                            primary: false,
                                            itemExtent: _rowH,
                                            itemCount: _shown.length,
                                            itemBuilder: (context, i) =>
                                                _row(context, _shown[i]),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _menu(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    final sel = _sel;
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('table-menu'),
      tooltip: s.tableMore,
      color: c.ground3,
      position: .under,
      onSelected: (f) => f(),
      itemBuilder: (_) => [
        if (widget.renamable)
          PopupMenuItem(
            enabled: sel != null,
            value: () => _beginName(sel!.$2),
            child: Text(
              s.tableRenameColumn,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        PopupMenuItem(
          key: const ValueKey('table-remove-row'),
          enabled: sel != null,
          value: _removeRow,
          child: Text(s.tableRemoveRow, style: const TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          key: const ValueKey('table-remove-column'),
          enabled: sel != null,
          value: _removeColumn,
          child: Text(
            s.tableRemoveColumn,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
      child: SizedBox(
        width: 32,
        height: 32,
        child: Center(child: AppIcon('ui_more', size: 16, color: c.text3)),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    final selCol = _sel?.$2;
    return Container(
      height: _headH,
      decoration: BoxDecoration(
        color: c.ground3,
        border: Border(bottom: BorderSide(color: c.line2)),
      ),
      child: Row(
        children: [
          SizedBox(width: _gutter),
          for (final (i, name) in _t.columns.indexed)
            SizedBox(
              key: ValueKey('table-head-$i'),
              width: _widths[i],
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: .opaque,
                      onDoubleTap: () => _beginName(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: .centerLeft,
                        decoration: BoxDecoration(
                          border: Border(right: BorderSide(color: c.line1)),
                        ),
                        child: _naming == i
                            ? _editor(context, name: true)
                            : Tooltip(
                                message: name,
                                waitDuration: const Duration(milliseconds: 600),
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: _headStyle(
                                    selCol == i ? c.text1 : c.text2,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 7,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        key: ValueKey('table-resize-$i'),
                        behavior: .opaque,
                        onHorizontalDragUpdate: (d) => setState(() {
                          final w = (_widths[i] + d.delta.dx).clamp(
                            40.0,
                            800.0,
                          );
                          _widths[i] = w;
                          _dragged[name] = w;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int r) {
    final c = context.colors;
    final sel = _sel;
    final lit = sel?.$1 == r;
    return DecoratedBox(
      key: ValueKey('table-row-$r'),
      decoration: BoxDecoration(
        color: lit ? c.ground3.withValues(alpha: 0.5) : null,
        border: Border(bottom: BorderSide(color: c.line1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _gutter,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${r + 1}',
                textAlign: .right,
                style: mono(size: 11, color: lit ? c.text2 : c.text4),
              ),
            ),
          ),
          for (var i = 0; i < _t.columns.length; i++)
            _cell(context, r, i, selected: lit && sel?.$2 == i),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int r, int i, {required bool selected}) {
    final c = context.colors;
    final editing = selected && _editing;
    final shown = _show(i, _t.cell(r, i));
    Widget body;
    if (editing) {
      body = _editor(context);
    } else {
      final text = Text(
        shown.text,
        maxLines: 1,
        overflow: .ellipsis,
        textAlign: shown.kind == .number ? .right : .left,
        style: mono(
          size: 12,
          color: switch (shown.kind) {
            .text || .number => c.text1,
            .flag => c.warn,
            .nil => c.text4,
            .nested => c.text3,
          },
        ),
      );
      body = shown.more == 0
          ? text
          : Row(
              spacing: 4,
              children: [
                Expanded(child: text),
                Text(
                  '↲ +${shown.more}',
                  style: mono(size: 10, color: c.text4),
                ),
              ],
            );
      if (shown.tip case final tip?) {
        body = Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 500),
          child: body,
        );
      }
    }
    // Selected at once on the press (a tap would wait for the double
    // click); a double click edits.
    return Listener(
      key: ValueKey('table-cell-$r-$i'),
      onPointerDown: (_) => _select(r, i),
      child: GestureDetector(
        behavior: .opaque,
        onDoubleTap: _editable ? _begin : null,
        child: Container(
          width: _widths[i],
          height: _rowH,
          padding: EdgeInsets.symmetric(horizontal: editing ? 6 : 8),
          alignment: shown.kind == .number && !editing
              ? .centerRight
              : .centerLeft,
          decoration: BoxDecoration(
            color: editing ? c.ground1 : null,
            border: Border(right: BorderSide(color: c.line1)),
          ),
          foregroundDecoration: selected
              ? BoxDecoration(
                  border: .all(color: c.ember, width: 1.5),
                  borderRadius: Radii.chip,
                )
              : null,
          child: body,
        ),
      ),
    );
  }

  /// The text field of a cell or a header in place.
  Widget _editor(BuildContext context, {bool name = false}) {
    final c = context.colors;
    void submit() {
      if (commit()) {
        widget.onSubmit?.call();
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () => commit(dr: 1),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            commit(dr: 1),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): submit,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): submit,
        const SingleActivator(LogicalKeyboardKey.tab): () => commit(dc: 1),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
            commit(dc: -1),
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        if (!name) ...{
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              commit(dr: -1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              commit(dr: 1),
        },
      },
      child: TextField(
        key: ValueKey(name ? 'table-name-editor' : 'table-cell-editor'),
        controller: _text,
        focusNode: _textFocus,
        autocorrect: false,
        enableSuggestions: false,
        style: name ? _headStyle(c.text1) : mono(size: 12, color: c.text1),
        cursorHeight: 14,
        decoration: const InputDecoration.collapsed(hintText: '').copyWith(
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }
}
