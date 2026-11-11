import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../indicators/app_icon.dart';
import '../indicators/quality_mark.dart';
import '../tables/table_edits.dart';
import '../tables/table_grid.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import '../trees/json_tree.dart';
import 'floating_window.dart';

/// How the value of a [ValueViewerVm] is drawn, by its type.
sealed class ValueContentVm extends Equatable {
  const ValueContentVm();
}

/// A map or a list: a pretty tree.
final class JsonContentVm extends ValueContentVm {
  const JsonContentVm(this.root);

  final JsonNodeVm root;

  @override
  List<Object?> get props => [root];
}

/// A text: mono, wrapped, with line numbers.
final class TextContentVm extends ValueContentVm {
  const TextContentVm(this.lines);

  final List<String> lines;

  @override
  List<Object?> get props => [lines];
}

/// A number, already rounded for reading, with its unit.
final class NumberContentVm extends ValueContentVm {
  const NumberContentVm(this.number, {this.unit = ''});

  final String number;
  final String unit;

  @override
  List<Object?> get props => [number, unit];
}

/// A bool: a mark and its word (or the name a point gives it).
final class FlagContentVm extends ValueContentVm {
  const FlagContentVm({required this.value, required this.word});

  final bool value;
  final String word;

  @override
  List<Object?> get props => [value, word];
}

/// Binary data as a hex dump: rows of `offset  hex  text`.
final class BytesContentVm extends ValueContentVm {
  const BytesContentVm(this.rows);

  final List<String> rows;

  @override
  List<Object?> get props => [rows];
}

/// A table (ADR 0044 §2: `{columns, rows}`, or a list of maps): a grid of
/// all its rows ([TableGrid]). It compares by the table's identity: the app
/// keeps one [TableDataVm] per value.
final class TableContentVm extends ValueContentVm {
  const TableContentVm(this.table);

  final TableDataVm table;

  @override
  List<Object?> get props => [table];
}

/// No value (yet), or `null`.
final class EmptyContentVm extends ValueContentVm {
  const EmptyContentVm(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// The editor a [ValueViewer] opens for a value that can be typed.
enum ViewerEditKind {
  /// A text: a multi-line mono editor.
  text,

  /// A map or a list as JSON: the same editor, checked as it is typed.
  json,

  /// A number: one line.
  number,

  /// A bool: a toggle.
  toggle,

  /// One of [ViewerEditVm.choices]: a dropdown.
  choice,

  /// A table ([ViewerEditVm.table]): its grid edits in place; Edit opens
  /// [ViewerEditVm.text] (its JSON) in the multi-line editor.
  table,
}

/// What the viewer's Edit mode starts with: the value as its editor shows
/// it ([text]: a number, `true`, indented JSON, the text itself).
final class ViewerEditVm extends Equatable {
  const ViewerEditVm({
    required this.kind,
    required this.text,
    this.choices = const [],
    this.table,
  });

  final ViewerEditKind kind;
  final String text;
  final List<String> choices;

  /// The typed table a [ViewerEditKind.table] grid starts with.
  final TableDataVm? table;

  @override
  List<Object?> get props => [kind, text, choices, table];
}

/// How a CSV text is read as `table_from_csv` reads it: the block's
/// [delimiter] and [header] (`with_header`), and a [note] when a wire feeds
/// either (`The delimiter comes in on a wire: read with ","`).
final class ViewerCsvVm extends Equatable {
  const ViewerCsvVm({this.delimiter = ',', this.header = true, this.note = ''});

  final String delimiter;
  final bool header;
  final String note;

  @override
  List<Object?> get props => [delimiter, header, note];
}

/// How the viewer reads and writes tables, given by the app: a cell's own
/// text (a date), Copy as CSV, and the engine's own CSV rules for the "As
/// table" tab of a CSV text.
final class ViewerTables {
  const ViewerTables({
    this.cellText,
    this.copyCsv,
    this.readCsv,
    this.writeCsv,
  });

  final CellTextOf? cellText;

  /// The table as CSV with a comma and a header; null: no Copy CSV.
  final String Function(TableDataVm table)? copyCsv;

  /// A CSV text as the block reads it; null when it refuses it.
  final TableDataVm? Function(String text, ViewerCsvVm rules)? readCsv;

  /// A table as the CSV text the block reads back.
  final String Function(TableDataVm table, ViewerCsvVm rules)? writeCsv;
}

/// The value one viewer shows: whose it is ([title]: `concat1.out`, a
/// point key), its [type] and [size] (`map` · `3 keys`), how to draw it,
/// its quality when it is a sample, and the raw value as [copy] puts it on
/// the clipboard (JSON or the text itself).
final class ValueViewerVm extends Equatable {
  const ValueViewerVm({
    required this.title,
    required this.type,
    required this.content,
    required this.copy,
    this.size = '',
    this.quality,
    this.edit,
    this.locked,
    this.csv,
  });

  /// A CSV text that the viewer also shows "As table" by these rules;
  /// null: none (only a typed text of `table_from_csv` has them).
  final ViewerCsvVm? csv;

  /// How the value is typed; null: the viewer only shows it.
  final ViewerEditVm? edit;

  /// Why the value cannot be typed (`a wire feeds this field`), shown
  /// under it; null: it can, or nothing is to be said (a point).
  final String? locked;

  /// The same value with how it is typed ([edit]) or why not ([locked]).
  ValueViewerVm typed({
    ViewerEditVm? edit,
    String? locked,
    ViewerCsvVm? csv,
  }) => ValueViewerVm(
    title: title,
    type: type,
    content: content,
    copy: copy,
    size: size,
    quality: quality,
    edit: edit,
    locked: locked,
    csv: csv,
  );

  final String title;
  final String type;
  final String size;
  final ValueContentVm content;
  final QualityMarkVm? quality;
  final String copy;

  @override
  List<Object?> get props => [
    title,
    type,
    size,
    content,
    quality,
    copy,
    edit,
    locked,
    csv,
  ];
}

/// The floating window of a field's or a point's value (owner request
/// 2026-11-09): the title in mono with the type and size beside it, Copy,
/// close; the value styled by its type and redrawn as it changes. One is
/// open at a time; the page keeps it in a `Positioned.fill` of its stack.
///
/// A value that can be typed ([ValueViewerVm.edit], owner decision
/// 2026-11-09) has an Edit button: the body becomes an editor fit for the
/// type, with Save ([onSave], also ⌘/Ctrl+Enter) and Cancel under it; Esc
/// leaves the editor first and closes the window next. What cannot be
/// saved ([validate]) is said under the editor and Save is off. A value
/// that cannot be typed says why ([ValueViewerVm.locked]).
///
/// A table (owner request 2026-11-11) is a [TableGrid] with Copy CSV and
/// Copy JSON. A typed one ([ViewerEditKind.table]) edits in its grid: the
/// first change brings Discard and Save under it (Esc discards first), and
/// Save writes the table as `{columns, rows}` JSON through [onSave], as the
/// JSON editor does; Edit opens that JSON. A CSV text with
/// [ValueViewerVm.csv] has two tabs, Text and As table: the table is the
/// text read by the block's rules ([ViewerTables.readCsv]) and, when the
/// text is typed, its edits are saved as CSV ([ViewerTables.writeCsv]).
class ValueViewer extends StatefulWidget {
  const ValueViewer({
    required this.vm,
    required this.onClose,
    this.onSave,
    this.validate,
    this.tables,
    this.editing = false,
    this.copyLabel = 'Copy',
    this.copiedLabel = 'Copied',
    this.closeLabel = 'Close',
    this.editLabel = 'Edit',
    this.saveLabel = 'Save',
    this.cancelLabel = 'Cancel',
    this.saveHint = '',
    super.key,
  });

  final ValueViewerVm vm;
  final VoidCallback onClose;

  /// Save of the Edit mode: the text of the editor (`true`/`false` of a
  /// toggle, the choice picked, a table's JSON or CSV).
  final ValueChanged<String>? onSave;

  /// What is wrong with a typed text (`Not a number`); null: it saves.
  final String? Function(String text)? validate;

  /// How tables are read and written; null: by the grid alone (no Copy
  /// CSV, no "As table" tab).
  final ViewerTables? tables;

  /// Whether the viewer opens in its Edit mode.
  final bool editing;
  final String editLabel;
  final String saveLabel;
  final String cancelLabel;

  /// `⌘Enter saves · Esc cancels`, under the editor.
  final String saveHint;
  final String copyLabel;
  final String copiedLabel;
  final String closeLabel;

  @override
  State<ValueViewer> createState() => _ValueViewerState();
}

class _ValueViewerState extends State<ValueViewer> {
  /// Which Copy said `Copied` last (`copy`, `csv`, `json`).
  String? _copied;
  Timer? _timer;
  var _editing = false;
  final _text = TextEditingController();
  final _field = FocusNode(debugLabel: 'ValueViewer editor');
  final _grid = GlobalKey<TableGridState>();

  /// The table as the grid's edits left it; null: unchanged.
  TableDataVm? _draft;

  /// A CSV text shown as a table (the "As table" tab).
  var _asTable = false;

  bool get _canEdit => widget.vm.edit != null && widget.onSave != null;

  /// The rules of the "As table" tab, when the viewer has one.
  ViewerCsvVm? get _csv {
    final csv = widget.vm.csv;
    return csv != null &&
            widget.tables?.readCsv != null &&
            widget.vm.content is TextContentVm
        ? csv
        : null;
  }

  /// The CSV text the "As table" tab reads: the typed one, else the value.
  String get _csvText => widget.vm.edit?.text ?? widget.vm.copy;

  /// The table the grid shows: the draft, the CSV read, the typed table or
  /// the value; null when it has none (a CSV the block refuses).
  TableDataVm? get _table {
    if (_draft case final d?) {
      return d;
    }
    if (_csv case final rules? when _asTable) {
      return widget.tables!.readCsv!(_csvText, rules);
    }
    if (widget.vm.edit case ViewerEditVm(
      kind: .table,
      :final table?,
    ) when widget.onSave != null) {
      return table;
    }
    return switch (widget.vm.content) {
      TableContentVm(:final table) => table,
      _ => null,
    };
  }

  /// Whether the grid edits: a typed table, or a typed CSV text as a table.
  bool get _gridEdits =>
      widget.onSave != null &&
      switch (widget.vm.edit?.kind) {
        ViewerEditKind.table => !_asTable,
        ViewerEditKind.text => _asTable && _csv != null,
        _ => false,
      };

  /// Whether the body is a grid (not the editor, a text or a tree).
  bool get _showsGrid =>
      !_editing &&
      (_asTable && _csv != null ||
          widget.vm.content is TableContentVm ||
          widget.vm.edit?.kind == .table && widget.onSave != null);

  @override
  void initState() {
    super.initState();
    if (widget.editing && _canEdit) {
      _begin();
    }
  }

  @override
  void didUpdateWidget(ValueViewer old) {
    super.didUpdateWidget(old);
    // Another field, or one that got a wire: the editor closes, a draft
    // is dropped. A new sample of the same field keeps both.
    if (old.vm.title != widget.vm.title) {
      _editing = false;
      _draft = null;
      _asTable = false;
    } else if (!_canEdit) {
      _editing = false;
      _draft = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    _field.dispose();
    super.dispose();
  }

  void _begin() {
    final edit = widget.vm.edit;
    if (edit == null) {
      return;
    }
    _text.text = edit.text;
    _editing = true;
    _draft = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) {
        _field.requestFocus();
      }
    });
  }

  String? get _error => widget.validate?.call(_text.text);

  void _save() {
    if (!_editing || _error != null) {
      return;
    }
    widget.onSave?.call(_text.text);
    setState(() => _editing = false);
  }

  void _cancel() => setState(() => _editing = false);

  /// Save of the grid's draft: a table as JSON, the "As table" tab as CSV.
  void _saveTable() {
    if (_grid.currentState?.commit() == false) {
      return;
    }
    final d = _draft;
    if (d == null) {
      return;
    }
    final csv = _csv;
    final write = widget.tables?.writeCsv;
    final text = _asTable && csv != null && write != null
        ? write(d, csv)
        : d.toJsonText();
    widget.onSave?.call(text);
    setState(() => _draft = null);
  }

  void _discard() => setState(() => _draft = null);

  void _copy(String id, String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    _timer?.cancel();
    setState(() => _copied = id);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = null);
      }
    });
  }

  /// A Copy button; [dense] in the title row of a table, which holds
  /// three of them.
  Widget _copyButton(
    String id,
    String label,
    String Function() text, {
    bool dense = false,
  }) => Button.quiet(
    key: ValueKey('viewer-copy-$id'),
    label: _copied == id ? widget.copiedLabel : label,
    icon: _copied == id ? 'ui_check' : 'ui_copy',
    size: ButtonSize.small,
    fontSize: dense ? 12 : 14,
    inset: dense ? 10 : 16,
    onPressed: () => _copy(id, text()),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = S.current;
    final vm = widget.vm;
    final error = _editing ? _error : null;
    final grid = _showsGrid;
    final table = grid ? _table : null;
    final csv = _csv;
    final copyCsv = widget.tables?.copyCsv;
    return FloatingWindow(
      // Esc leaves the editor first (drops the grid's draft), and closes
      // the window next.
      onClose: widget.onClose,
      onEscape: _editing ? _cancel : (_draft != null ? _discard : null),
      closeLabel: widget.closeLabel,
      initialSize:
          vm.content is TableContentVm || csv != null || vm.edit?.kind == .table
          ? const Size(640, 440)
          : const Size(440, 380),
      header: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Row(
              spacing: 10,
              children: [
                Flexible(
                  child: Tooltip(
                    message: vm.title,
                    waitDuration: const Duration(milliseconds: 600),
                    child: LayoutBuilder(
                      // A key loses its start, not its name: `…/plc1/level`.
                      builder: (context, box) {
                        final style = mono(weight: .w600, color: c.text1);
                        return Text(
                          _fitStart(vm.title, style, box.maxWidth),
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: style,
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.ground4,
                    borderRadius: Radii.chip,
                  ),
                  child: Text(
                    // A grid says its counts above its rows.
                    [
                      vm.type,
                      if (vm.size.isNotEmpty && table == null) vm.size,
                    ].join(' · '),
                    maxLines: 1,
                    style: mono(size: 11, color: c.text3),
                  ),
                ),
              ],
            ),
          ),
          if (_canEdit && !_editing && !(grid && _asTable))
            Button.quiet(
              key: const ValueKey('viewer-edit'),
              label: vm.edit?.kind == .table
                  ? s.viewerEditJson
                  : widget.editLabel,
              icon: 'action_edit',
              size: ButtonSize.small,
              fontSize: table != null ? 12 : 14,
              inset: table != null ? 10 : 16,
              onPressed: _draft != null ? null : () => setState(_begin),
            ),
          if (table != null) ...[
            if (copyCsv != null)
              _copyButton(
                'csv',
                s.viewerCopyCsv,
                () => copyCsv(table),
                dense: true,
              ),
            _copyButton(
              'json',
              s.viewerCopyJson,
              () => _draft == null && !_asTable ? vm.copy : table.toJsonText(),
              dense: true,
            ),
          ] else
            _copyButton('copy', widget.copyLabel, () => vm.copy),
        ],
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _editing
              ? _save
              : _saveTable,
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _editing ? _save : _saveTable,
        },
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (csv != null && !_editing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SegmentedTabs(
                  key: const ValueKey('viewer-tabs'),
                  height: 34,
                  // Changes in the grid are saved or dropped first.
                  tabs: [
                    TabItemVm(
                      id: 'text',
                      label: s.viewerTabText,
                      disabledReason: _draft != null
                          ? s.viewerTableHint(_keys)
                          : null,
                    ),
                    TabItemVm(id: 'table', label: s.viewerTabTable),
                  ],
                  selected: _asTable ? 'table' : 'text',
                  onSelect: (t) {
                    if (_draft != null ||
                        _grid.currentState?.commit() == false) {
                      return;
                    }
                    setState(() {
                      _asTable = t == 'table';
                      _draft = null;
                    });
                  },
                ),
              ),
            if (csv != null && _asTable && !_editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Text(
                  [
                    s.viewerCsvRules(
                      csv.delimiter,
                      csv.header ? s.viewerCsvHeaderOn : s.viewerCsvHeaderOff,
                    ),
                    if (csv.note.isNotEmpty) csv.note,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: c.text4),
                ),
              ),
            Expanded(
              child: _editing
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      child: _editor(context, vm.edit!),
                    )
                  : grid
                  ? (table == null
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              s.viewerCsvRefused,
                              key: const ValueKey('viewer-csv-refused'),
                              style: mono(color: c.badText),
                            ),
                          )
                        : TableGrid(
                            key: _grid,
                            table: table,
                            cellText: widget.tables?.cellText,
                            textCells: _asTable,
                            renamable: !_asTable || (csv?.header ?? true),
                            onSubmit: _saveTable,
                            onChanged: _gridEdits
                                ? (t) => setState(() => _draft = t)
                                : null,
                          ))
                  : Scrollbar(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                        child: _body(context, vm.content),
                      ),
                    ),
            ),
            if (_editing)
              _foot(
                context,
                text: error ?? widget.saveHint,
                bad: error != null,
                onCancel: _cancel,
                cancelLabel: widget.cancelLabel,
                onSave: error == null ? _save : null,
              )
            else if (_draft != null)
              _foot(
                context,
                text: s.viewerTableHint(_keys),
                bad: false,
                onCancel: _discard,
                cancelLabel: s.viewerDiscard,
                onSave: _saveTable,
              )
            else if (vm.locked case final why?)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line1)),
                ),
                child: Row(
                  crossAxisAlignment: .start,
                  spacing: 8,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: AppIcon('action_lock', size: 14, color: c.text4),
                    ),
                    Expanded(
                      child: Text(
                        why,
                        style: TextStyle(fontSize: 12, color: c.text4),
                      ),
                    ),
                  ],
                ),
              ),
            if (vm.quality case final q?)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line1)),
                ),
                child: QualityMark(vm: q, size: 12),
              ),
          ],
        ),
      ),
    );
  }

  /// `Cmd+Enter` on macOS, `Ctrl+Enter` elsewhere.
  static String get _keys => defaultTargetPlatform == TargetPlatform.macOS
      ? 'Cmd+Enter'
      : 'Ctrl+Enter';

  /// The row under an editor: the hint or what is wrong, Cancel, Save.
  Widget _foot(
    BuildContext context, {
    required String text,
    required bool bad,
    required VoidCallback onCancel,
    required String cancelLabel,
    required VoidCallback? onSave,
  }) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line1)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: .ellipsis,
              style: TextStyle(fontSize: 12, color: bad ? c.badText : c.text4),
            ),
          ),
          Button.quiet(
            key: const ValueKey('viewer-cancel'),
            label: cancelLabel,
            size: ButtonSize.small,
            onPressed: onCancel,
          ),
          Button.primary(
            key: const ValueKey('viewer-save'),
            label: widget.saveLabel,
            size: ButtonSize.small,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }

  /// The editor of the Edit mode, by the value's kind.
  Widget _editor(BuildContext context, ViewerEditVm edit) {
    final c = context.colors;
    final box = BoxDecoration(
      color: c.ground3,
      border: .all(color: _error == null ? c.line2 : c.badLine),
      borderRadius: Radii.segment,
    );
    InputDecoration plain() =>
        const InputDecoration.collapsed(hintText: '').copyWith(
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        );
    switch (edit.kind) {
      case .text || .json || .table:
        return Container(
          decoration: box,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: TextField(
            key: const ValueKey('viewer-editor'),
            controller: _text,
            focusNode: _field,
            maxLines: null,
            expands: true,
            textAlignVertical: .top,
            keyboardType: .multiline,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            style: mono(size: 12, color: c.text1).copyWith(height: 1.5),
            decoration: plain(),
          ),
        );
      case .number:
        return Align(
          alignment: .topLeft,
          child: Container(
            height: 44,
            decoration: box,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: .centerLeft,
            child: TextField(
              key: const ValueKey('viewer-editor'),
              controller: _text,
              focusNode: _field,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              style: mono(size: 20, color: c.text1),
              decoration: plain(),
            ),
          ),
        );
      case .toggle:
        final on = _text.text.trim() == 'true';
        return Align(
          alignment: .topLeft,
          child: Row(
            mainAxisSize: .min,
            spacing: 12,
            children: [
              Switch(
                key: const ValueKey('viewer-editor'),
                focusNode: _field,
                value: on,
                onChanged: (v) => setState(() => _text.text = '$v'),
              ),
              Text(
                '$on',
                style: mono(size: 20, color: on ? c.good : c.text2),
              ),
            ],
          ),
        );
      case .choice:
        return Align(
          alignment: .topLeft,
          child: Container(
            height: 40,
            decoration: box,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('viewer-editor'),
                focusNode: _field,
                value: edit.choices.contains(_text.text) ? _text.text : null,
                isExpanded: true,
                dropdownColor: c.ground3,
                icon: AppIcon('ui_chevron_down', size: 16, color: c.text4),
                style: mono(size: 14, color: c.text1),
                items: [
                  for (final ch in edit.choices)
                    DropdownMenuItem(
                      value: ch,
                      child: Text(ch, maxLines: 1, overflow: .ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _text.text = v ?? ''),
              ),
            ),
          ),
        );
    }
  }

  Widget _body(BuildContext context, ValueContentVm content) {
    final c = context.colors;
    return switch (content) {
      JsonContentVm(:final root) => JsonTree(root: root),
      TextContentVm(:final lines) => _Lines(lines: lines),
      NumberContentVm(:final number, :final unit) => SelectionArea(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: number,
                style: mono(size: 28, color: c.text1),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: '  $unit',
                  style: mono(size: 16, color: c.text3),
                ),
            ],
          ),
        ),
      ),
      FlagContentVm(:final value, :final word) => Row(
        spacing: 10,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: .circle,
              color: value ? c.good : null,
              border: .all(color: value ? c.good : c.text4, width: 1.6),
            ),
          ),
          Text(
            word,
            style: mono(size: 20, color: value ? c.good : c.text2),
          ),
        ],
      ),
      BytesContentVm(:final rows) => SelectionArea(
        child: Column(
          crossAxisAlignment: .start,
          children: [
            for (final r in rows)
              Text(r, style: mono(size: 12, color: c.text2)),
          ],
        ),
      ),
      EmptyContentVm(:final text) => Text(
        text,
        style: mono(size: 14, color: c.text4),
      ),
      // Drawn by the grid, not in the scrolled body.
      TableContentVm() => const SizedBox.shrink(),
    };
  }
}

/// [text] as it fits in [width]: whole, or its last `/` segments after
/// `…/`.
String _fitStart(String text, TextStyle style, double width) {
  bool fits(String t) {
    final p = TextPainter(
      text: TextSpan(text: t, style: style),
      maxLines: 1,
      textDirection: .ltr,
    )..layout();
    final w = p.width;
    p.dispose();
    return w <= width;
  }

  if (fits(text)) {
    return text;
  }
  final parts = text.split('/');
  for (var i = 1; i < parts.length; i++) {
    final t = '…/${parts.sublist(i).join('/')}';
    if (fits(t)) {
      return t;
    }
  }
  return text;
}

/// Text lines, numbered in a gutter on the left, each wrapped to the
/// width.
class _Lines extends StatelessWidget {
  const _Lines({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gutter = 10.0 + 7.5 * '${lines.length}'.length;
    return SelectionArea(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final (i, l) in lines.indexed)
            Row(
              crossAxisAlignment: .start,
              spacing: 10,
              children: [
                SizedBox(
                  width: gutter,
                  child: SelectionContainer.disabled(
                    child: Text(
                      '${i + 1}',
                      textAlign: .right,
                      style: mono(size: 12, color: c.text4),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    l,
                    softWrap: true,
                    style: mono(size: 12, color: c.text1),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
