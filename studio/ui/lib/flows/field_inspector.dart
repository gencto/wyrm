import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'field_drop_zone.dart';
import 'flow_block_view.dart';

/// How a field of the inspector is edited (spec §6).
enum FieldEditorVm {
  /// Bound: the value that comes in along its wire, read-only, in the
  /// accent colour in a frame, with a small `bound` mark; never the path
  /// (the wire and its source row show where it comes from).
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
    this.engine = '',
    this.value = '',
    this.choices = const [],
    this.sourceBlock,
    this.writes = false,
    this.targets = '',
    this.inPort,
    this.hint = '',
  });

  /// The field's id within its block.
  final String id;

  /// What the row reads: `Input min`.
  final String name;

  /// What the engine calls it (`input_min`, `in.0`), mono and small under
  /// [name]; empty when it reads the same.
  final String engine;
  final FieldEditorVm editor;

  /// The typed value (text, choice, `true`/`false`) or the sample shown.
  final String value;
  final List<String> choices;

  /// The block a bound field's wire comes from: `Go to source` selects
  /// it; it is not shown.
  final String? sourceBlock;

  /// The binding writes to a device (ember frame).
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
    engine,
    editor,
    value,
    choices,
    sourceBlock,
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
    this.onGoToSource,
    this.onView,
    this.viewLabel = 'View value',
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
    this.goToSourceLabel = 'Go to source',
    this.boundLabel = 'bound',
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

  /// `Go to source` of a bound field: selects the block its wire comes
  /// from.
  final ValueChanged<String>? onGoToSource;

  /// The eye at the end of a row: opens the field's value in the viewer;
  /// null: rows have none.
  final ValueChanged<String>? onView;
  final String viewLabel;
  final String removeLabel;
  final VoidCallback? onRemove;
  final String unbindLabel;
  final String bindLabel;
  final String goToSourceLabel;
  final String boundLabel;

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
                          onGoToSource: onGoToSource,
                          onView: onView,
                          viewLabel: viewLabel,
                          unbindLabel: unbindLabel,
                          bindLabel: bindLabel,
                          goToSourceLabel: goToSourceLabel,
                          boundLabel: boundLabel,
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

/// One field: label (engine name under it) · editor · link button · view
/// button (104 · 1fr · 28 · 28, min 44 high). Every value ellipsizes in
/// its cell; the viewer shows it whole.
class _Row extends StatelessWidget {
  const _Row({
    required this.vm,
    required this.onChanged,
    required this.onUnbind,
    required this.onBind,
    required this.onGoToSource,
    required this.onView,
    required this.viewLabel,
    required this.unbindLabel,
    required this.bindLabel,
    required this.goToSourceLabel,
    required this.boundLabel,
  });

  final InspectorRowVm vm;
  final ValueChanged<String>? onView;
  final String viewLabel;
  final void Function(String id, String value) onChanged;
  final ValueChanged<String> onUnbind;
  final void Function(String id, FieldRefVm from) onBind;
  final ValueChanged<String>? onGoToSource;
  final String unbindLabel;
  final String bindLabel;
  final String goToSourceLabel;
  final String boundLabel;

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
        children: [
          SizedBox(
            width: 104,
            child: Tooltip(
              message: vm.hint,
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  Text(
                    vm.name,
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 13, color: c.text2),
                  ),
                  if (vm.engine.isNotEmpty)
                    Text(
                      vm.engine,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: mono(size: 10, color: c.text4),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _editor(context)),
          const SizedBox(width: 6),
          SizedBox(
            width: 28,
            height: 32,
            child: bound
                ? _LinkMenu(
                    icon: AppIcon('ui_bind', size: 16, color: c.emberSoft),
                    items: [
                      if (vm.sourceBlock case final from?
                          when onGoToSource != null)
                        (goToSourceLabel, () => onGoToSource!(from)),
                      (unbindLabel, () => onUnbind(vm.id)),
                    ],
                  )
                : Tooltip(
                    message: takes ? bindLabel : '',
                    child: Opacity(
                      opacity: takes ? 1 : 0.35,
                      child: Center(
                        child: AppIcon('ui_bind', size: 16, color: c.text4),
                      ),
                    ),
                  ),
          ),
          if (onView case final view?)
            SizedBox(
              width: 28,
              height: 32,
              child: IconButton(
                tooltip: viewLabel,
                padding: EdgeInsets.zero,
                onPressed: () => view(vm.id),
                icon: AppIcon('ui_view', size: 16, color: c.text3),
              ),
            ),
        ],
      ),
    );
    if (!takes) {
      return row(false);
    }
    // A wire dragged out of the canvas and let go here binds the field.
    return FieldDropZone(
      drop: FieldDrop(vm.id, onDrop: (from) => onBind(vm.id, from)),
      builder: (context, lit) => row(lit),
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
        // As DGLux: the value that comes in, read only, in the accent
        // colour in a frame; the wire on the canvas shows its source.
        return Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.ground3,
            border: .all(color: vm.writes ? c.emberLine : c.goodLine),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
          ),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  vm.value.isEmpty ? '—' : vm.value,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: mono(size: 12, color: c.emberNew),
                ),
              ),
              Text(
                boundLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: vm.writes ? c.emberSoft : c.good,
                ),
              ),
            ],
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
                  DropdownMenuItem(
                    value: ch,
                    child: Text(ch, maxLines: 1, overflow: .ellipsis),
                  ),
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
                Flexible(
                  child: Text(
                    vm.value,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: mono(size: 12, color: c.text1),
                  ),
                ),
                Flexible(
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

/// The link button of a bound field: a menu of what can be done with its
/// binding (`Go to source`, `Unbind`).
class _LinkMenu extends StatelessWidget {
  const _LinkMenu({required this.icon, required this.items});

  final Widget icon;
  final List<(String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<int>(
      padding: EdgeInsets.zero,
      tooltip: '',
      color: c.ground3,
      position: .under,
      onSelected: (i) => items[i].$2(),
      itemBuilder: (_) => [
        for (final (i, (label, _)) in items.indexed)
          PopupMenuItem(
            value: i,
            height: 36,
            child: Text(label, style: TextStyle(fontSize: 13, color: c.text1)),
          ),
      ],
      child: Center(child: icon),
    );
  }
}
