import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'flow_block_view.dart';

/// How a field of the inspector is edited (spec §6).
enum FieldEditorVm {
  /// Bound: a chip `← <block>.<field>`, read-only.
  bound,

  /// A choice: a dropdown of [InspectorRowVm.choices].
  choice,

  /// A bool: a toggle.
  toggle,

  /// A typed value: a text field.
  text,

  /// An output: its value and where it goes.
  output,

  /// An input with no typed value: its last sample.
  sample,
}

/// One field of the selected block.
final class InspectorRowVm extends Equatable {
  const InspectorRowVm({
    required this.id,
    required this.name,
    required this.editor,
    this.value = '',
    this.choices = const [],
    this.source = '',
    this.writes = false,
    this.targets = '',
    this.inPort,
    this.hint = '',
  });

  /// The field's id within its block.
  final String id;
  final String name;
  final FieldEditorVm editor;

  /// The typed value (text, choice, `true`/`false`) or the sample shown.
  final String value;
  final List<String> choices;

  /// A bound field's source, `tankInfo.state`.
  final String source;

  /// The binding writes to a device (ember chip).
  final bool writes;

  /// An output's `→ plc1.fan, …` or `not bound`.
  final String targets;

  /// The engine input a drop on this row binds; null: it takes none.
  final String? inPort;

  /// The parameter's description, as a tooltip.
  final String hint;

  @override
  List<Object?> get props => [
    id,
    name,
    editor,
    value,
    choices,
    source,
    writes,
    targets,
    inPort,
    hint,
  ];
}

/// One problem of the last validation; [block] selects its block.
final class ProblemVm extends Equatable {
  const ProblemVm(this.text, {this.block});

  final String text;
  final String? block;

  @override
  List<Object?> get props => [text, block];
}

/// The inspector with nothing selected: the flow itself.
final class FlowSummaryVm extends Equatable {
  const FlowSummaryVm({
    required this.label,
    required this.title,
    this.facts = const [],
    this.problemsLabel = '',
    this.problems = const [],
  });

  /// `FLOW`.
  final String label;

  /// The flow id.
  final String title;

  /// `Version` · `4`, `Deployed by` · `olena · 12 min ago`, `May write` · …
  final List<(String, String)> facts;
  final String problemsLabel;
  final List<ProblemVm> problems;

  @override
  List<Object?> get props => [label, title, facts, problemsLabel, problems];
}

/// The right column of the flow editor (spec §6): the selected block's kind,
/// id and note, then one row per field with its editor and link button; with
/// nothing selected, the flow's summary. A field dragged from the canvas and
/// dropped on a row binds it.
class FieldInspector extends StatelessWidget {
  const FieldInspector({
    required this.footer,
    required this.onChanged,
    required this.onUnbind,
    required this.onBind,
    required this.onProblem,
    this.kindLabel = '',
    this.title = '',
    this.note = '',
    this.rows = const [],
    this.summary,
    this.header,
    this.removeLabel = '',
    this.onRemove,
    this.unbindLabel = 'Unbind',
    this.bindLabel = 'Drag an output here to bind',
    super.key,
  });

  /// `LOGIC BLOCK`; with [summary] the flow is shown instead.
  final String kindLabel;
  final String title;
  final String note;
  final List<InspectorRowVm> rows;
  final FlowSummaryVm? summary;

  /// Shown above everything (the id field of a new flow).
  final Widget? header;
  final List<String> footer;
  final void Function(String id, String value) onChanged;
  final ValueChanged<String> onUnbind;
  final void Function(String id, FieldRefVm from) onBind;
  final ValueChanged<String> onProblem;
  final String removeLabel;
  final VoidCallback? onRemove;
  final String unbindLabel;
  final String bindLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = summary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(left: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          ?header,
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 4,
              children: [
                Text(
                  (s?.label ?? kindLabel).toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: .w600,
                    letterSpacing: 0.72,
                    color: c.text4,
                  ),
                ),
                Text(
                  s?.title ?? title,
                  style: mono(size: 18, weight: .w600, color: c.text1),
                ),
                if (s == null && note.isNotEmpty)
                  Text(note, style: TextStyle(fontSize: 12, color: c.text4)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              children: s != null
                  ? _summary(context, s)
                  : [
                      for (final r in rows)
                        _Row(
                          vm: r,
                          onChanged: onChanged,
                          onUnbind: onUnbind,
                          onBind: onBind,
                          unbindLabel: unbindLabel,
                          bindLabel: bindLabel,
                        ),
                      if (onRemove != null) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: .centerLeft,
                          child: Button.danger(
                            label: removeLabel,
                            size: ButtonSize.small,
                            onPressed: onRemove,
                          ),
                        ),
                      ],
                    ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line1)),
            ),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 6,
              children: [
                for (final f in footer)
                  Text(
                    f,
                    style: TextStyle(fontSize: 12, height: 1.5, color: c.text4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _summary(BuildContext context, FlowSummaryVm s) {
    final c = context.colors;
    return [
      for (final (k, v) in s.facts)
        Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.ground3)),
          ),
          child: Row(
            crossAxisAlignment: .start,
            children: [
              SizedBox(
                width: 104,
                child: Text(k, style: TextStyle(fontSize: 13, color: c.text4)),
              ),
              Expanded(
                child: Text(v, style: TextStyle(fontSize: 13, color: c.text1)),
              ),
            ],
          ),
        ),
      if (s.problems.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(
          s.problemsLabel.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: .w600,
            letterSpacing: 0.72,
            color: c.text4,
          ),
        ),
        const SizedBox(height: 6),
        for (final p in s.problems)
          InkWell(
            onTap: p.block == null ? null : () => onProblem(p.block!),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: .start,
                spacing: 8,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: .circle,
                        color: c.bad,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: p.block == null ? c.text2 : c.badText,
                        decoration: p.block == null ? null : .underline,
                        decorationColor: c.badLine,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ];
  }
}

/// One field: name · editor · link button (82 · 1fr · 32, min 44 high).
class _Row extends StatelessWidget {
  const _Row({
    required this.vm,
    required this.onChanged,
    required this.onUnbind,
    required this.onBind,
    required this.unbindLabel,
    required this.bindLabel,
  });

  final InspectorRowVm vm;
  final void Function(String id, String value) onChanged;
  final ValueChanged<String> onUnbind;
  final void Function(String id, FieldRefVm from) onBind;
  final String unbindLabel;
  final String bindLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bound = vm.editor == FieldEditorVm.bound;
    final takes = vm.inPort != null;
    Widget row(bool lit) => Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: lit ? c.ember.withValues(alpha: 0.12) : null,
        border: Border(bottom: BorderSide(color: c.ground3)),
      ),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 82,
            child: Tooltip(
              message: vm.hint,
              child: Text(
                vm.name,
                maxLines: 1,
                overflow: .ellipsis,
                style: mono(color: c.text2),
              ),
            ),
          ),
          Expanded(child: _editor(context)),
          SizedBox(
            width: 32,
            height: 32,
            child: Tooltip(
              message: bound ? unbindLabel : (takes ? bindLabel : ''),
              child: InkWell(
                onTap: bound ? () => onUnbind(vm.id) : null,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                child: Opacity(
                  opacity: takes ? 1 : 0.35,
                  child: Center(
                    child: AppIcon(
                      'ui_bind',
                      size: 16,
                      color: bound ? c.emberSoft : c.text4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!takes) {
      return row(false);
    }
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => d.data is FieldRefVm,
      onAcceptWithDetails: (d) => onBind(vm.id, d.data as FieldRefVm),
      builder: (context, candidates, _) => row(candidates.isNotEmpty),
    );
  }

  Widget _editor(BuildContext context) {
    final c = context.colors;
    final box = BoxDecoration(
      color: c.ground3,
      border: .all(color: c.line2),
      borderRadius: const BorderRadius.all(Radius.circular(6)),
    );
    switch (vm.editor) {
      case FieldEditorVm.bound:
        final (bg, line, ink) = vm.writes
            ? (c.emberTint, c.emberLine, c.emberNew)
            : (c.goodTint, const Color(0xFF2F5C52), const Color(0xFFC4EBE1));
        return Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: .centerLeft,
          decoration: BoxDecoration(
            color: bg,
            border: .all(color: line),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
          ),
          child: Text(
            '← ${vm.source}',
            maxLines: 1,
            overflow: .ellipsis,
            style: mono(size: 12, color: ink),
          ),
        );
      case FieldEditorVm.choice:
        return Container(
          height: 32,
          decoration: box,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: vm.choices.contains(vm.value) ? vm.value : null,
              isExpanded: true,
              isDense: true,
              dropdownColor: c.ground3,
              icon: AppIcon('ui_chevron_down', size: 16, color: c.text4),
              style: mono(size: 12, color: c.text1),
              items: [
                for (final ch in vm.choices)
                  DropdownMenuItem(value: ch, child: Text(ch)),
              ],
              onChanged: (v) => onChanged(vm.id, v ?? ''),
            ),
          ),
        );
      case FieldEditorVm.toggle:
        return Align(
          alignment: .centerLeft,
          child: SizedBox(
            height: 32,
            child: FittedBox(
              child: Switch(
                value: vm.value == 'true',
                onChanged: (v) => onChanged(vm.id, '$v'),
              ),
            ),
          ),
        );
      case FieldEditorVm.text:
        return _TextEditor(
          value: vm.value,
          decoration: box,
          onChanged: (v) => onChanged(vm.id, v),
        );
      case FieldEditorVm.output:
        return SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              spacing: 8,
              children: [
                Text(vm.value, style: mono(size: 12, color: c.text1)),
                Expanded(
                  child: Text(
                    vm.targets,
                    maxLines: 1,
                    overflow: .ellipsis,
                    textAlign: .right,
                    style: mono(size: 12, color: c.text4),
                  ),
                ),
              ],
            ),
          ),
        );
      case FieldEditorVm.sample:
        return SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: .centerLeft,
              child: Text(
                vm.value,
                maxLines: 1,
                overflow: .ellipsis,
                style: mono(size: 12, color: c.text3),
              ),
            ),
          ),
        );
    }
  }
}

/// A text field 32 high, mono 12, that keeps what is typed while it has the
/// focus and follows the value otherwise.
class _TextEditor extends StatefulWidget {
  const _TextEditor({
    required this.value,
    required this.decoration,
    required this.onChanged,
  });

  final String value;
  final BoxDecoration decoration;
  final ValueChanged<String> onChanged;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_TextEditor old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 32,
      decoration: widget.decoration,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: .centerLeft,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onChanged: widget.onChanged,
        style: mono(size: 12, color: c.text1),
        decoration:
            const InputDecoration.collapsed(
              hintText: '',
            ).copyWith(
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
      ),
    );
  }
}
