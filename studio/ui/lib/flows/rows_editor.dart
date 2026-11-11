import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One column of a [RowsEditor]: the key it writes in each row, its label,
/// and its choices (a dropdown) or none (a text).
final class RowsColumnVm extends Equatable {
  const RowsColumnVm(this.key, this.label, {this.choices = const []});

  final String key;
  final String label;
  final List<String> choices;

  @override
  List<Object?> get props => [key, label, choices];
}

/// What [RowsEditor] draws: a list parameter of maps (`table_map_columns`
/// `mapping`: `{name, from}`; `aggregates`: `{column, method, as}`) as rows
/// of [columns].
final class RowsEditorVm extends Equatable {
  const RowsEditorVm({
    required this.id,
    required this.columns,
    required this.rows,
    this.addLabel = 'Add a row',
    this.removeLabel = 'Remove this row',
    this.emptyLabel = 'No rows yet',
  });

  final String id;
  final List<RowsColumnVm> columns;

  /// Each row: a text per column key.
  final List<Map<String, String>> rows;
  final String addLabel;
  final String removeLabel;
  final String emptyLabel;

  @override
  List<Object?> get props => [
    id,
    columns,
    rows,
    addLabel,
    removeLabel,
    emptyLabel,
  ];
}

/// The list editor of the flow inspector (flow-editor.md §6): a header of
/// the column labels, then one line per row with a field per column and a
/// remove button, then `Add a row`. Every change hands the whole list to
/// [onChanged]; a row whose fields are all empty is still a row until it
/// is removed.
class RowsEditor extends StatefulWidget {
  const RowsEditor({
    required this.vm,
    required this.decoration,
    required this.onChanged,
    super.key,
  });

  final RowsEditorVm vm;
  final BoxDecoration decoration;
  final ValueChanged<List<Map<String, String>>> onChanged;

  @override
  State<RowsEditor> createState() => _RowsEditorState();
}

class _RowsEditorState extends State<RowsEditor> {
  late List<Map<String, String>> _rows = _copy(widget.vm.rows);

  /// One controller per cell, by row and column key.
  final _cells = <(int, String), TextEditingController>{};
  final _focus = FocusScopeNode();

  static List<Map<String, String>> _copy(List<Map<String, String>> r) => [
    for (final x in r) {...x},
  ];

  @override
  void didUpdateWidget(RowsEditor old) {
    super.didUpdateWidget(old);
    // It keeps what is typed while one of its fields has the focus, else
    // follows the value.
    if (!_focus.hasFocus && old.vm.rows != widget.vm.rows) {
      _rows = _copy(widget.vm.rows);
      for (final MapEntry(key: (r, k), value: ctl) in _cells.entries) {
        final v = r < _rows.length ? _rows[r][k] ?? '' : '';
        if (ctl.text != v) {
          ctl.text = v;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _cells.values) {
      c.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _set(int row, String key, String value) {
    setState(() => _rows[row][key] = value);
    widget.onChanged(_copy(_rows));
  }

  void _add() {
    setState(() => _rows.add({for (final c in widget.vm.columns) c.key: ''}));
    widget.onChanged(_copy(_rows));
  }

  void _remove(int row) {
    setState(() {
      _rows.removeAt(row);
      // The cells below move up: their controllers take the new texts.
      for (final MapEntry(key: (r, k), value: ctl) in _cells.entries) {
        final v = r < _rows.length ? _rows[r][k] ?? '' : '';
        if (ctl.text != v) {
          ctl.text = v;
        }
      }
    });
    widget.onChanged(_copy(_rows));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cols = widget.vm.columns;
    Widget cell(int row, RowsColumnVm col) {
      final v = _rows[row][col.key] ?? '';
      if (col.choices.isNotEmpty) {
        return Container(
          height: 32,
          decoration: widget.decoration,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: ValueKey('rows-${widget.vm.id}-$row-${col.key}'),
              value: col.choices.contains(v) ? v : null,
              isExpanded: true,
              isDense: true,
              dropdownColor: c.ground3,
              icon: AppIcon('ui_chevron_down', size: 14, color: c.text4),
              style: mono(size: 12, color: c.text1),
              items: [
                for (final ch in col.choices)
                  DropdownMenuItem(
                    value: ch,
                    child: Text(ch, maxLines: 1, overflow: .ellipsis),
                  ),
              ],
              onChanged: (x) => _set(row, col.key, x ?? ''),
            ),
          ),
        );
      }
      final ctl = _cells.putIfAbsent(
        (row, col.key),
        () => TextEditingController(text: v),
      );
      return Container(
        height: 32,
        decoration: widget.decoration,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: .centerLeft,
        child: TextField(
          key: ValueKey('rows-${widget.vm.id}-$row-${col.key}'),
          controller: ctl,
          onChanged: (x) => _set(row, col.key, x),
          autocorrect: false,
          enableSuggestions: false,
          style: mono(size: 12, color: c.text1),
          decoration: const InputDecoration.collapsed(hintText: '').copyWith(
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
      );
    }

    return FocusScope(
      node: _focus,
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          if (_rows.isEmpty)
            Text(
              widget.vm.emptyLabel,
              style: TextStyle(fontSize: 12, color: c.text4),
            )
          else
            Row(
              spacing: 6,
              children: [
                for (final col in cols)
                  Expanded(
                    child: Text(
                      col.label,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(fontSize: 11, color: c.text4),
                    ),
                  ),
                const SizedBox(width: 24),
              ],
            ),
          for (var r = 0; r < _rows.length; r++)
            Row(
              spacing: 6,
              children: [
                for (final col in cols) Expanded(child: cell(r, col)),
                SizedBox(
                  width: 24,
                  height: 32,
                  child: Tooltip(
                    message: widget.vm.removeLabel,
                    child: InkWell(
                      key: ValueKey('rows-${widget.vm.id}-remove-$r'),
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                      onTap: () => _remove(r),
                      child: Center(
                        child: AppIcon('ui_close', size: 14, color: c.text4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          Align(
            alignment: .centerLeft,
            child: TextButton.icon(
              key: ValueKey('rows-${widget.vm.id}-add'),
              onPressed: _add,
              icon: Text('+', style: mono(color: c.ember)),
              label: Text(
                widget.vm.addLabel,
                style: TextStyle(fontSize: 12, color: c.ember),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
