import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../indicators/quality_mark.dart';
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
}

/// What the viewer's Edit mode starts with: the value as its editor shows
/// it ([text]: a number, `true`, indented JSON, the text itself).
final class ViewerEditVm extends Equatable {
  const ViewerEditVm({
    required this.kind,
    required this.text,
    this.choices = const [],
  });

  final ViewerEditKind kind;
  final String text;
  final List<String> choices;

  @override
  List<Object?> get props => [kind, text, choices];
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
  });

  /// How the value is typed; null: the viewer only shows it.
  final ViewerEditVm? edit;

  /// Why the value cannot be typed (`a wire feeds this field`), shown
  /// under it; null: it can, or nothing is to be said (a point).
  final String? locked;

  /// The same value with how it is typed ([edit]) or why not ([locked]).
  ValueViewerVm typed({ViewerEditVm? edit, String? locked}) => ValueViewerVm(
    title: title,
    type: type,
    content: content,
    copy: copy,
    size: size,
    quality: quality,
    edit: edit,
    locked: locked,
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
class ValueViewer extends StatefulWidget {
  const ValueViewer({
    required this.vm,
    required this.onClose,
    this.onSave,
    this.validate,
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
  /// toggle, the choice picked).
  final ValueChanged<String>? onSave;

  /// What is wrong with a typed text (`Not a number`); null: it saves.
  final String? Function(String text)? validate;

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
  var _copied = false;
  Timer? _timer;
  var _editing = false;
  final _text = TextEditingController();
  final _field = FocusNode(debugLabel: 'ValueViewer editor');

  bool get _canEdit => widget.vm.edit != null && widget.onSave != null;

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
    // Another field, or one that got a wire: the editor closes.
    if (_editing && (old.vm.title != widget.vm.title || !_canEdit)) {
      _editing = false;
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

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.vm.copy)));
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;
    final error = _editing ? _error : null;
    return FloatingWindow(
      // Esc leaves the editor first, and closes the window next.
      onClose: widget.onClose,
      onEscape: _editing ? _cancel : null,
      closeLabel: widget.closeLabel,
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
                    [vm.type, if (vm.size.isNotEmpty) vm.size].join(' · '),
                    maxLines: 1,
                    style: mono(size: 11, color: c.text3),
                  ),
                ),
              ],
            ),
          ),
          if (_canEdit && !_editing)
            Button.quiet(
              key: const ValueKey('viewer-edit'),
              label: widget.editLabel,
              icon: 'action_edit',
              size: ButtonSize.small,
              onPressed: () => setState(_begin),
            ),
          Button.quiet(
            label: _copied ? widget.copiedLabel : widget.copyLabel,
            icon: _copied ? 'ui_check' : 'ui_copy',
            size: ButtonSize.small,
            onPressed: _copy,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: _editing
                ? CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        meta: true,
                      ): _save,
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): _save,
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      child: _editor(context, vm.edit!),
                    ),
                  )
                : Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                      child: _body(context, vm.content),
                    ),
                  ),
          ),
          if (_editing)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      error ?? widget.saveHint,
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: error == null ? c.text4 : c.badText,
                      ),
                    ),
                  ),
                  Button.quiet(
                    label: widget.cancelLabel,
                    size: ButtonSize.small,
                    onPressed: _cancel,
                  ),
                  Button.primary(
                    key: const ValueKey('viewer-save'),
                    label: widget.saveLabel,
                    size: ButtonSize.small,
                    onPressed: error == null ? _save : null,
                  ),
                ],
              ),
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
      case .text || .json:
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
