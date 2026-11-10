import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../overlays/confirm_dialog.dart';
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

  /// An unbound `Trigger`: a `Run` button ([InspectorRowVm.value] is its
  /// label, [InspectorRowVm.disabledReason] why it is off).
  run,

  /// A period: a number with its unit (ms, s, min, h); the value is in
  /// milliseconds.
  duration,
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
    this.pinned,
    this.pinLocked = false,
    this.group = '',
    this.disabledReason,
    this.confirm,
    this.error = '',
  });

  /// The group this row is listed under (`Arguments`, `Behaviour`,
  /// `Events`, `State`): its heading stands above the group's first row.
  final String group;

  /// Why a `run` button is off (its tooltip); null: it runs.
  final String? disabledReason;

  /// A toggle that asks before it goes on: the question's title and its
  /// text (`Run on start`: the catalog's warning).
  final (String, String)? confirm;

  /// What is wrong with the typed value, in coral under the editor.
  final String error;

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

  /// Whether the field is a row of the block on the canvas (spec §12);
  /// null: the row has no pin (the `Form` row).
  final bool? pinned;

  /// A bound field stays on the block: its pin cannot be taken off.
  final bool pinLocked;

  /// The same row with its pin: on the block or not, and whether a wire
  /// holds it there.
  InspectorRowVm pin({required bool pinned, required bool locked}) =>
      _with(pinned: pinned, pinLocked: locked);

  /// The same row under [group].
  InspectorRowVm inGroup(String group) => _with(group: group);

  InspectorRowVm _with({bool? pinned, bool? pinLocked, String? group}) =>
      InspectorRowVm(
        id: id,
        name: name,
        editor: editor,
        engine: engine,
        value: value,
        choices: choices,
        sourceBlock: sourceBlock,
        writes: writes,
        targets: targets,
        inPort: inPort,
        hint: hint,
        pinned: pinned ?? this.pinned,
        pinLocked: pinLocked ?? this.pinLocked,
        group: group ?? this.group,
        disabledReason: disabledReason,
        confirm: confirm,
        error: error,
      );

  @override
  List<Object?> get props => [
    pinned,
    pinLocked,
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
    group,
    disabledReason,
    confirm,
    error,
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
    this.onPin,
    this.pinLabel = 'Pin to block',
    this.unpinLabel = 'Unpin from block',
    this.pinLockedLabel = 'A bound field stays on the block',
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
    this.onRun,
    this.confirmLabel = 'Turn on',
    this.cancelLabel = 'Cancel',
    this.links = const [],
    super.key,
  });

  /// The `Run` button of a row ([FieldEditorVm.run]): the row's id.
  final ValueChanged<String>? onRun;

  /// The buttons of a toggle's question ([InspectorRowVm.confirm]).
  final String confirmLabel;
  final String cancelLabel;

  /// Link buttons above the rows (`Open inside`), each a label and what
  /// it does.
  final List<(String, VoidCallback)> links;

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

  /// The pin before a row's label: puts the field on the block or takes
  /// it off (spec §12); null: rows have none.
  final void Function(String id, {required bool pinned})? onPin;
  final String pinLabel;
  final String unpinLabel;
  final String pinLockedLabel;
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
                      for (final (label, onTap) in links)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Align(
                            alignment: .centerLeft,
                            child: Button.quiet(
                              label: label,
                              size: ButtonSize.small,
                              onPressed: onTap,
                            ),
                          ),
                        ),
                      for (final (i, r) in rows.indexed) ...[
                        if (r.group.isNotEmpty &&
                            (i == 0 || rows[i - 1].group != r.group))
                          Padding(
                            padding: EdgeInsets.only(
                              top: i == 0 ? 2 : 14,
                              bottom: 2,
                            ),
                            child: Text(
                              r.group.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: .w600,
                                letterSpacing: 0.66,
                                color: c.text4,
                              ),
                            ),
                          ),
                        _Row(
                          vm: r,
                          onRun: onRun,
                          confirmLabel: confirmLabel,
                          cancelLabel: cancelLabel,
                          onChanged: onChanged,
                          onUnbind: onUnbind,
                          onBind: onBind,
                          onGoToSource: onGoToSource,
                          onView: onView,
                          viewLabel: viewLabel,
                          onPin: onPin,
                          pinLabel: pinLabel,
                          unpinLabel: unpinLabel,
                          pinLockedLabel: pinLockedLabel,
                          unbindLabel: unbindLabel,
                          bindLabel: bindLabel,
                          goToSourceLabel: goToSourceLabel,
                          boundLabel: boundLabel,
                        ),
                      ],
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

/// One field: pin · label (engine name under it) · editor · link button ·
/// view button (18 · 86 · 1fr · 28 · 28, min 44 high; 104 for the label
/// of a row without a pin). Every value ellipsizes in
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
    required this.onPin,
    required this.pinLabel,
    required this.unpinLabel,
    required this.pinLockedLabel,
    required this.unbindLabel,
    required this.bindLabel,
    required this.goToSourceLabel,
    required this.boundLabel,
    required this.onRun,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final ValueChanged<String>? onRun;
  final String confirmLabel;
  final String cancelLabel;
  final InspectorRowVm vm;
  final void Function(String id, {required bool pinned})? onPin;
  final String pinLabel;
  final String unpinLabel;
  final String pinLockedLabel;
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
    final pin = onPin;
    final pinned = vm.pinned;
    final hasPin = pin != null && pinned != null;
    Widget row(bool lit) => Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: lit ? c.ember.withValues(alpha: 0.12) : null,
        border: Border(bottom: BorderSide(color: c.ground3)),
      ),
      child: Row(
        children: [
          if (hasPin)
            SizedBox(
              width: 18,
              height: 32,
              child: Tooltip(
                message: vm.pinLocked
                    ? pinLockedLabel
                    : (pinned ? unpinLabel : pinLabel),
                waitDuration: const Duration(milliseconds: 400),
                child: InkWell(
                  key: ValueKey('pin-${vm.id}'),
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                  onTap: vm.pinLocked
                      ? null
                      : () => pin(vm.id, pinned: !pinned),
                  child: Align(
                    alignment: .centerLeft,
                    child: AppIcon(
                      'ui_pin',
                      size: 14,
                      color: !pinned
                          ? c.muted
                          : (vm.pinLocked ? c.good : c.emberSoft),
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(
            width: hasPin ? 86 : 104,
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
          Expanded(
            child: vm.error.isEmpty
                ? _editor(context)
                : Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: [
                      const SizedBox(height: 6),
                      _editor(context),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          vm.error,
                          style: TextStyle(fontSize: 11, color: c.bad),
                        ),
                      ),
                    ],
                  ),
          ),
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
                key: ValueKey('toggle-${vm.id}'),
                value: vm.value == 'true',
                onChanged: (v) async {
                  // A toggle with a warning asks before it goes on.
                  if (v) {
                    if (vm.confirm case (final title, final message)) {
                      final yes = await ConfirmDialog.ask(
                        context,
                        title: title,
                        message: message,
                        confirm: confirmLabel,
                        cancel: cancelLabel,
                      );
                      if (!yes) {
                        return;
                      }
                    }
                  }
                  onChanged(vm.id, '$v');
                },
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
        // The value, and under it where it goes: each has the whole cell,
        // so a time or an error's text is not cut by `not bound`.
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              mainAxisAlignment: .center,
              crossAxisAlignment: .start,
              children: [
                if (vm.value.isNotEmpty)
                  Text(
                    vm.value,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: mono(size: 12, color: c.text1),
                  ),
                if (vm.targets.isNotEmpty)
                  Text(
                    vm.targets,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: mono(size: 10, color: c.text4),
                  ),
              ],
            ),
          ),
        );
      case FieldEditorVm.run:
        // Off, it says why under the button, not only in its tooltip.
        return Padding(
          padding: EdgeInsets.symmetric(
            vertical: vm.disabledReason == null ? 0 : 6,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              Button.secondary(
                key: ValueKey('run-${vm.id}'),
                label: vm.value,
                icon: 'action_play',
                size: ButtonSize.small,
                disabledReason: vm.disabledReason,
                onPressed: vm.disabledReason != null || onRun == null
                    ? null
                    : () => onRun!(vm.id),
              ),
              if (vm.disabledReason case final why?)
                Text(
                  why,
                  style: TextStyle(fontSize: 11, height: 1.35, color: c.text4),
                ),
            ],
          ),
        );
      case FieldEditorVm.duration:
        return _DurationEditor(
          key: ValueKey('duration-${vm.id}'),
          millis: vm.value,
          decoration: box,
          onChanged: (v) => onChanged(vm.id, v),
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

/// A period typed as a number and a unit (`5` `min`): the value in and out
/// is milliseconds as text; empty is none. It reads in the largest unit
/// that gives a whole number, and keeps the unit the user picked.
class _DurationEditor extends StatefulWidget {
  const _DurationEditor({
    required this.millis,
    required this.decoration,
    required this.onChanged,
    super.key,
  });

  final String millis;
  final BoxDecoration decoration;
  final ValueChanged<String> onChanged;

  @override
  State<_DurationEditor> createState() => _DurationEditorState();
}

class _DurationEditorState extends State<_DurationEditor> {
  static const _units = {'ms': 1, 's': 1000, 'min': 60000, 'h': 3600000};

  late String _unit = _fit(widget.millis);

  static String _fit(String millis) {
    final ms = num.tryParse(millis.trim());
    if (ms == null || ms == 0) {
      return 's';
    }
    return _units.entries
        .lastWhere((u) => ms % u.value == 0, orElse: () => _units.entries.first)
        .key;
  }

  String get _shown {
    final ms = num.tryParse(widget.millis.trim());
    if (ms == null) {
      return widget.millis;
    }
    final v = ms / _units[_unit]!;
    return v == v.roundToDouble() ? '${v.round()}' : '$v';
  }

  void _typed(String text, String unit) {
    final n = num.tryParse(text.trim());
    widget.onChanged(
      n == null ? text.trim() : '${(n * _units[unit]!).round()}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      spacing: 6,
      children: [
        Expanded(
          child: _TextEditor(
            value: _shown,
            decoration: widget.decoration,
            onChanged: (t) => _typed(t, _unit),
          ),
        ),
        Container(
          height: 32,
          width: 64,
          decoration: widget.decoration,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _unit,
              isExpanded: true,
              isDense: true,
              dropdownColor: c.ground3,
              icon: AppIcon('ui_chevron_down', size: 14, color: c.text4),
              style: mono(size: 12, color: c.text1),
              items: [
                for (final u in _units.keys)
                  DropdownMenuItem(value: u, child: Text(u)),
              ],
              onChanged: (u) {
                if (u == null) {
                  return;
                }
                final shown = _shown;
                setState(() => _unit = u);
                _typed(shown, u);
              },
            ),
          ),
        ),
      ],
    );
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
