import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../indicators/app_icon.dart';
import '../indicators/level_badge.dart';
import '../indicators/lines_text.dart';
import '../models/disabled.dart';
import '../overlays/confirm_dialog.dart';
import '../theme/extensions/colors.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'field_drop_zone.dart';
import 'field_word.dart';
import 'flow_block_view.dart';
import 'flow_intents.dart';
import 'rows_editor.dart';
import 'scope_prompt.dart';
import 'suggest_field.dart';

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

  /// An unbound `Trigger`: a `Run` button ([InspectorRowVm.off] why it is
  /// off).
  run,

  /// A command input (`date_range` Next): a button named as the field that
  /// a sample on its wire presses; Studio cannot press it.
  command,

  /// The default of a custom block's input: a text field.
  defaults,

  /// The form of a block of several ([InspectorRowVm.form] of
  /// [InspectorRowVm.forms]): a dropdown.
  form,

  /// A period: a number with its unit (ms, s, min, h); the value is in
  /// milliseconds.
  duration,

  /// A text with a menu of the usual values ([InspectorRowVm.choices]): a
  /// time zone, a range text. Any other text may be typed.
  suggest,

  /// A list of maps ([InspectorRowVm.rows]): a line per item, a field per
  /// key (`mapping`, `aggregates`). The value handed on is the list as
  /// JSON.
  rows,
}

/// The group a row is listed under: its heading stands above the group's
/// first row.
enum FieldGroupVm {
  target,
  arguments,
  behaviour,
  events,
  state;

  String get label => switch (this) {
    target => S.current.grpTarget,
    arguments => S.current.grpArguments,
    behaviour => S.current.grpBehaviour,
    events => S.current.grpEvents,
    state => S.current.grpState,
  };
}

/// One way a block of several forms works (`scale`), as the Form row says
/// it.
enum BlockFormVm {
  linear,
  range;

  String get label => switch (this) {
    linear => S.current.formLinear,
    range => S.current.formRange,
  };
}

/// What the inspector says the selected block is.
enum InspectorKindVm {
  /// The inputs or outputs block of an inside view.
  ports,
  node,
  logic,
  sink,
  action,
  my;

  String get label => switch (this) {
    ports => S.current.kindBlockPorts,
    node => S.current.kindTreeNode,
    logic => S.current.kindLogic,
    sink => S.current.kindSink,
    action => S.current.kindAction,
    my => S.current.kindMyBlock,
  };
}

/// The note under the inspector's title.
enum InspectorNoteVm {
  inputs,
  outputs,
  treeNode,
  actionBlock,
  action,

  /// The catalogue's description of the type ([InspectorHeadVm.description]).
  catalog,
}

/// The head of the inspector of a selected block: its kind, its title (the
/// block's id, or the word of a [boundary] block) and its note.
final class InspectorHeadVm extends Equatable {
  const InspectorHeadVm({
    required this.kind,
    required this.id,
    this.boundary,
    this.note = InspectorNoteVm.catalog,
    this.description = '',
  });

  final InspectorKindVm kind;
  final String id;
  final BoundaryVm? boundary;
  final InspectorNoteVm note;

  /// The catalogue's description (domain text) of a [InspectorNoteVm.catalog]
  /// note.
  final String description;

  /// The title: the block's id, or `Inputs` / `Outputs`.
  String get title => boundary?.label ?? id;

  /// The note, in words.
  String get noteText => switch (note) {
    InspectorNoteVm.inputs => S.current.noteBlockInputs,
    InspectorNoteVm.outputs => S.current.noteBlockOutputs,
    InspectorNoteVm.treeNode => S.current.noteTreeNode,
    InspectorNoteVm.actionBlock => S.current.noteActionBlock,
    InspectorNoteVm.action => S.current.noteAction,
    InspectorNoteVm.catalog => description,
  };

  @override
  List<Object?> get props => [kind, id, boundary, note, description];
}

/// An input an output feeds: its block and what the input reads
/// (`plc1.fan`, `show.Value`).
final class RowTargetVm extends Equatable {
  const RowTargetVm(this.block, this.field, {this.word});

  final String block;

  /// The input's label when it is data; [word] when it is Studio's word.
  final String field;
  final FieldWordVm? word;

  String get text => '$block.${word?.text ?? field}';

  @override
  List<Object?> get props => [block, field, word];
}

/// One field of the selected block.
final class InspectorRowVm extends Equatable {
  const InspectorRowVm({
    required this.id,
    required this.name,
    required this.editor,
    this.word,
    this.engine = '',
    this.value = '',
    this.on = false,
    this.choices = const [],
    this.sourceBlock,
    this.writes = false,
    this.targets = const [],
    this.inPort,
    this.hint = '',
    this.pinned,
    this.pinLocked = false,
    this.group,
    this.off,
    this.confirm,
    this.error,
    this.rows,
    this.form,
    this.forms = const [],
  });

  /// The list a [FieldEditorVm.rows] editor shows.
  final RowsEditorVm? rows;

  /// The group this row is listed under; null: none.
  final FieldGroupVm? group;

  /// Why a `run` button is off (said under it); null: it runs.
  final Disabled? off;

  /// A toggle that asks before it goes on (`Run on start`): the catalogue's
  /// warning, under the question's own title.
  final String? confirm;

  /// What is wrong with the typed scope, in coral under the editor.
  final ScopeProblemVm? error;

  /// The block's form and its forms ([FieldEditorVm.form]).
  final BlockFormVm? form;
  final List<BlockFormVm> forms;

  /// The field's id within its block: the row's widget identity.
  final String id;

  /// What the row reads: `Input min`.
  final String name;

  /// What the engine calls it (`input_min`, `in.0`), mono and small under
  /// [name]; empty when it reads the same.
  final String engine;
  final FieldEditorVm editor;

  /// The typed value (text, choice, `true`/`false`) or the sample shown;
  /// null: an event that has not fired yet (or a run not made).
  final String? value;

  /// What a [FieldEditorVm.toggle] shows: on or off.
  final bool on;
  final List<String> choices;

  /// The block a bound field's wire comes from: `Go to source` selects
  /// it; it is not shown.
  final String? sourceBlock;

  /// The binding writes to a device (ember frame).
  final bool writes;

  /// The inputs an output feeds (`plc1.fan`); none: not bound.
  final List<RowTargetVm> targets;

  /// The row's name when it is Studio's own word; else [name] says it.
  final FieldWordVm? word;

  /// The engine input a drop on this row binds; null: it takes none.
  final String? inPort;

  /// The parameter's description, as a tooltip.
  final String hint;

  /// Whether the field is a row of the block on the canvas (spec §12);
  /// null: the row has no pin (the `Form` row).
  final bool? pinned;

  /// A bound field stays on the block: its pin cannot be taken off.
  final bool pinLocked;

  /// [value] as the row shows it: `not yet` for none.
  String get text => value ?? S.current.eventNone;

  /// What the row reads: [name], or `Form` for the Form row.
  String get label =>
      editor == FieldEditorVm.form ? S.current.blockForm : (word?.text ?? name);

  /// The same row with its pin: on the block or not, and whether a wire
  /// holds it there.
  InspectorRowVm pin({required bool pinned, required bool locked}) =>
      _with(pinned: pinned, pinLocked: locked);

  /// The same row under [group].
  InspectorRowVm inGroup(FieldGroupVm? group) => _with(group: group);

  InspectorRowVm _with({bool? pinned, bool? pinLocked, FieldGroupVm? group}) =>
      InspectorRowVm(
        id: id,
        name: name,
        word: word,
        editor: editor,
        engine: engine,
        value: value,
        on: on,
        choices: choices,
        sourceBlock: sourceBlock,
        writes: writes,
        targets: targets,
        inPort: inPort,
        hint: hint,
        pinned: pinned ?? this.pinned,
        pinLocked: pinLocked ?? this.pinLocked,
        group: group ?? this.group,
        off: off,
        confirm: confirm,
        error: error,
        rows: rows,
        form: form,
        forms: forms,
      );

  @override
  List<Object?> get props => [
    pinned,
    pinLocked,
    id,
    name,
    word,
    engine,
    editor,
    value,
    on,
    choices,
    sourceBlock,
    writes,
    targets,
    inPort,
    hint,
    group,
    off,
    confirm,
    error,
    rows,
    form,
    forms,
  ];
}

/// Where the values the blocks show come from.
enum ValuesFromVm {
  preview,
  deployed;

  String get label => switch (this) {
    preview => S.current.valuesPreview,
    deployed => S.current.valuesDeployed,
  };
}

/// One fact of the flow's summary: its label and its value, in words.
sealed class FlowFactVm extends Equatable {
  const FlowFactVm();

  String get label;
  String get value;
}

/// The deployed version; 0: not deployed.
final class FactVersion extends FlowFactVm {
  const FactVersion(this.version);

  final int version;

  @override
  String get label => S.current.factVersion;

  @override
  String get value => version > 0 ? '$version' : S.current.notDeployed;

  @override
  List<Object?> get props => [version];
}

/// Who deployed it and, when the flow is watched, how long ago.
final class FactDeployedBy extends FlowFactVm {
  const FactDeployedBy(this.by, {this.at});

  final String by;
  final DateTime? at;

  @override
  String get label => S.current.factDeployedBy;

  @override
  String get value => switch (at) {
    final t? => '$by · ${Formats.ago(t)}',
    null => by,
  };

  @override
  List<Object?> get props => [by, at];
}

/// The most it may write.
final class FactMayWrite extends FlowFactVm {
  const FactMayWrite(this.level);

  final AccessLevel level;

  @override
  String get label => S.current.factMayWrite;

  @override
  String get value => level.label;

  @override
  List<Object?> get props => [level];
}

/// Where the values the blocks show come from.
final class FactValues extends FlowFactVm {
  const FactValues(this.from);

  final ValuesFromVm from;

  @override
  String get label => S.current.factValues;

  @override
  String get value => from.label;

  @override
  List<Object?> get props => [from];
}

/// The watch or the preview was refused for a lack of rights.
final class FactLiveRefused extends FlowFactVm {
  const FactLiveRefused();

  @override
  String get label => S.current.factLive;

  @override
  String get value => S.current.liveRefused;

  @override
  List<Object?> get props => [];
}

/// The keys it reads.
final class FactReads extends FlowFactVm {
  const FactReads(this.keys);

  final List<String> keys;

  @override
  String get label => S.current.factReads;

  @override
  String get value => keys.join(', ');

  @override
  List<Object?> get props => [keys];
}

/// The keys it writes.
final class FactWrites extends FlowFactVm {
  const FactWrites(this.keys);

  final List<String> keys;

  @override
  String get label => S.current.factWrites;

  @override
  String get value => keys.join(', ');

  @override
  List<Object?> get props => [keys];
}

/// What a problem of the last validation is about.
enum FlowProblemKindVm {
  /// The flow has no name yet.
  unnamed,

  /// The broker said what is wrong ([FlowProblemVm.message]).
  broker,

  /// The broker's answer could not be read.
  unread,
}

/// One problem of the last validation, or the draft's preview refused
/// ([preview]); [block] selects its block.
final class FlowProblemVm extends Equatable {
  const FlowProblemVm(
    this.kind, {
    this.message,
    this.block,
    this.preview = false,
  });

  final FlowProblemKindVm kind;

  /// The broker's own words (domain text).
  final String? message;
  final String? block;
  final bool preview;

  /// The problem in words.
  String get text {
    final what = switch (kind) {
      FlowProblemKindVm.unnamed => S.current.problemUnnamed,
      FlowProblemKindVm.broker => message ?? S.current.problemInvalid,
      FlowProblemKindVm.unread => S.current.problemInvalid,
    };
    return preview ? S.current.previewInvalid(what) : what;
  }

  @override
  List<Object?> get props => [kind, message, block, preview];
}

/// The inspector with nothing selected: the flow itself.
final class FlowSummaryVm extends Equatable {
  const FlowSummaryVm({
    required this.name,
    this.facts = const [],
    this.problems = const [],
  });

  /// The flow id; null: a new flow with no name yet.
  final String? name;

  /// `Version` · `4`, `Deployed by` · `olena · 12 min ago`, `May write` · …
  final List<FlowFactVm> facts;
  final List<FlowProblemVm> problems;

  /// The title: the flow's id, or `New dataflow`.
  String get title => name ?? S.current.newDataflow;

  @override
  List<Object?> get props => [name, facts, problems];
}

/// The right column of the flow editor (spec §6): the selected block's kind,
/// id and note, then one row per field with its editor and link button; with
/// nothing selected, the flow's summary. A field dragged from the canvas and
/// dropped on a row binds it.
class FieldInspector extends StatelessWidget {
  const FieldInspector({
    required this.onChanged,
    required this.onUnbind,
    required this.onBind,
    required this.onProblem,
    this.onGoToSource,
    this.onView,
    this.onPin,
    this.onForm,
    this.head,
    this.rows = const [],
    this.summary,
    this.header,
    this.onRemove,
    this.onRun,
    this.onOpenInside,
    super.key,
  });

  /// The `Run` button of a row ([FieldEditorVm.run]): the row's index.
  final ValueChanged<int>? onRun;

  /// `Open inside` above the rows (an instance of a custom block); null:
  /// none.
  final VoidCallback? onOpenInside;

  /// The selected block's kind, title and note; with [summary] the flow is
  /// shown instead.
  final InspectorHeadVm? head;
  final List<InspectorRowVm> rows;
  final FlowSummaryVm? summary;

  /// Shown above everything (the id field of a new flow).
  final Widget? header;

  /// A row typed, by its index in [rows].
  final ValueChanged<RowTyped> onChanged;

  /// `Unbind` of a bound row: its index.
  final ValueChanged<int> onUnbind;

  /// An output dropped on a row.
  final ValueChanged<RowBound> onBind;
  final ValueChanged<String> onProblem;

  /// A form picked on the Form row ([FieldEditorVm.form]).
  final ValueChanged<BlockFormVm>? onForm;

  /// `Go to source` of a bound field: selects the block its wire comes
  /// from.
  final ValueChanged<String>? onGoToSource;

  /// The eye at the end of a row (its index): opens the field's value in
  /// the viewer; null: rows have none.
  final ValueChanged<int>? onView;

  /// The pin before a row's label (its index): puts the field on the block
  /// or takes it off (spec §12); null: rows have none.
  final ValueChanged<RowPinned>? onPin;
  final VoidCallback? onRemove;

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
            padding: Insets.flowInspectorHead,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line1)),
            ),
            child: Column(
              crossAxisAlignment: .start,
              spacing: AppSpacing.xs,
              children: [
                Text(
                  (s != null ? S.current.kindFlow : head?.kind.label ?? '')
                      .toUpperCase(),
                  style: TextStyle(
                    fontSize: FontSizes.sm,
                    fontWeight: .w600,
                    letterSpacing: 0.72,
                    color: c.text4,
                  ),
                ),
                Text(
                  s?.title ?? head?.title ?? '',
                  style: mono(
                    size: FontSizes.flowInspectorTitle,
                    weight: .w600,
                    color: c.text1,
                  ),
                ),
                if (s == null && (head?.noteText ?? '').isNotEmpty)
                  Text(
                    head!.noteText,
                    style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: Insets.flowInspectorList,
              children: s != null
                  ? _summary(context, s)
                  : [
                      if (onOpenInside case final open?)
                        Padding(
                          padding: Insets.flowInspectorLink,
                          child: Align(
                            alignment: .centerLeft,
                            child: Button.quiet(
                              label: S.current.openInside,
                              size: ButtonSize.small,
                              onPressed: open,
                            ),
                          ),
                        ),
                      for (final (i, r) in rows.indexed) ...[
                        if (r.group case final g?
                            when i == 0 || rows[i - 1].group != g)
                          Padding(
                            padding: i == 0
                                ? Insets.flowInspectorFirstGroup
                                : Insets.flowInspectorGroup,
                            child: Text(
                              g.label.toUpperCase(),
                              style: TextStyle(
                                fontSize: FontSizes.xs,
                                fontWeight: .w600,
                                letterSpacing: 0.66,
                                color: c.text4,
                              ),
                            ),
                          ),
                        _Row(
                          vm: r,
                          index: i,
                          onRun: onRun,
                          onChanged: onChanged,
                          onUnbind: onUnbind,
                          onBind: onBind,
                          onForm: onForm,
                          onGoToSource: onGoToSource,
                          onView: onView,
                          onPin: onPin,
                        ),
                      ],
                      if (onRemove != null) ...[
                        Gaps.md,
                        Align(
                          alignment: .centerLeft,
                          child: Button.danger(
                            label: S.current.removeBlock,
                            size: ButtonSize.small,
                            onPressed: onRemove,
                          ),
                        ),
                      ],
                    ],
            ),
          ),
          Container(
            padding: Insets.flowInspectorFoot,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line1)),
            ),
            child: Column(
              crossAxisAlignment: .start,
              spacing: AppSpacing.flowLines,
              children: [
                for (final f in [
                  S.current.flowPropertiesNote,
                  S.current.flowPropertiesNote2,
                ])
                  Text(
                    f,
                    style: TextStyle(
                      fontSize: FontSizes.sm,
                      height: 1.5,
                      color: c.text4,
                    ),
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
      for (final f in s.facts)
        Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.flowInspectorFact,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.ground3)),
          ),
          child: Row(
            crossAxisAlignment: .start,
            children: [
              SizedBox(
                width: AppSizes.flowInspectorLabel,
                child: Text(
                  f.label,
                  style: TextStyle(fontSize: FontSizes.md, color: c.text4),
                ),
              ),
              Expanded(
                child: Text(
                  f.value,
                  style: TextStyle(fontSize: FontSizes.md, color: c.text1),
                ),
              ),
            ],
          ),
        ),
      if (s.problems.isNotEmpty) ...[
        Gaps.md,
        Text(
          S.current.problems.toUpperCase(),
          style: TextStyle(
            fontSize: FontSizes.sm,
            fontWeight: .w600,
            letterSpacing: 0.72,
            color: c.text4,
          ),
        ),
        Gaps.flowInspectorLabel,
        for (final p in s.problems)
          InkWell(
            onTap: p.block == null ? null : () => onProblem(p.block!),
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadii.segment),
            ),
            child: Padding(
              padding: Insets.flowInspectorProblem,
              child: Row(
                crossAxisAlignment: .start,
                spacing: AppSpacing.sm,
                children: [
                  Padding(
                    padding: Insets.flowInspectorProblemDot,
                    child: Container(
                      width: AppSizes.flowDot,
                      height: AppSizes.flowDot,
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
                        fontSize: FontSizes.md,
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
    required this.index,
    required this.onChanged,
    required this.onUnbind,
    required this.onBind,
    required this.onForm,
    required this.onGoToSource,
    required this.onView,
    required this.onPin,
    required this.onRun,
  });

  final InspectorRowVm vm;

  /// The row's place in the inspector: what its callbacks report.
  final int index;
  final ValueChanged<int>? onRun;
  final ValueChanged<RowPinned>? onPin;
  final ValueChanged<int>? onView;
  final ValueChanged<RowTyped> onChanged;
  final ValueChanged<int> onUnbind;
  final ValueChanged<RowBound> onBind;
  final ValueChanged<BlockFormVm>? onForm;
  final ValueChanged<String>? onGoToSource;

  void _typed(String text) => onChanged(RowTyped(index, text));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bound = vm.editor == FieldEditorVm.bound;
    // A list editor takes the inspector's width, under the label.
    final wide = vm.editor == FieldEditorVm.rows;
    final takes = vm.inPort != null;
    final pin = onPin;
    final pinned = vm.pinned;
    final hasPin = pin != null && pinned != null;
    Widget head() => Row(
      children: [
        if (hasPin)
          SizedBox(
            width: AppSizes.flowInspectorPin,
            height: AppSizes.flowControl,
            child: Tooltip(
              message: vm.pinLocked
                  ? S.current.pinLocked
                  : (pinned ? S.current.unpinField : S.current.pinField),
              waitDuration: Motion.flowPinTipWait,
              child: InkWell(
                key: ValueKey('pin-${vm.id}'),
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadii.chip),
                ),
                onTap: vm.pinLocked
                    ? null
                    : () => pin(RowPinned(index, on: !pinned)),
                child: Align(
                  alignment: .centerLeft,
                  child: AppIcon(
                    'ui_pin',
                    size: AppSizes.flowPinIcon,
                    color: !pinned
                        ? c.muted
                        : (vm.pinLocked ? c.good : c.emberSoft),
                  ),
                ),
              ),
            ),
          ),
        SizedBox(
          width: hasPin
              ? AppSizes.flowInspectorPinnedLabel
              : AppSizes.flowInspectorLabel,
          child: Tooltip(
            message: vm.hint,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                Text(
                  vm.label,
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: TextStyle(fontSize: FontSizes.md, color: c.text2),
                ),
                if (vm.engine.isNotEmpty)
                  Text(
                    vm.engine,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: mono(size: FontSizes.flowDetail, color: c.text4),
                  ),
              ],
            ),
          ),
        ),
        Gaps.hSm,
        Expanded(
          child: wide
              ? Gaps.xl
              : vm.error == null
              ? _editor(context)
              : Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    Gaps.flowInspectorEditorTop,
                    _editor(context),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        vm.error!.label,
                        style: TextStyle(fontSize: FontSizes.xs, color: c.bad),
                      ),
                    ),
                  ],
                ),
        ),
        Gaps.hFlowInspectorButtons,
        SizedBox(
          width: AppSizes.flowInspectorButton,
          height: AppSizes.flowControl,
          child: bound
              ? _LinkMenu(
                  icon: AppIcon(
                    'ui_bind',
                    size: AppSizes.flowInspectorIcon,
                    color: c.emberSoft,
                  ),
                  items: [
                    if (vm.sourceBlock case final from?
                        when onGoToSource != null)
                      _LinkItem(
                        S.current.goToSource,
                        () => onGoToSource!(from),
                      ),
                    _LinkItem(S.current.unbind, () => onUnbind(index)),
                  ],
                )
              : Tooltip(
                  message: takes ? S.current.bindHint : '',
                  child: Opacity(
                    opacity: takes ? 1 : 0.35,
                    child: Center(
                      child: AppIcon(
                        'ui_bind',
                        size: AppSizes.flowInspectorIcon,
                        color: c.text4,
                      ),
                    ),
                  ),
                ),
        ),
        if (onView case final view?)
          SizedBox(
            width: AppSizes.flowInspectorButton,
            height: AppSizes.flowControl,
            child: IconButton(
              tooltip: S.current.viewValue,
              padding: EdgeInsets.zero,
              onPressed: () => view(index),
              icon: AppIcon(
                'ui_view',
                size: AppSizes.flowInspectorIcon,
                color: c.text3,
              ),
            ),
          ),
      ],
    );
    Widget row(bool lit) => Container(
      constraints: const BoxConstraints(minHeight: AppSizes.flowInspectorRow),
      decoration: BoxDecoration(
        color: lit ? c.ember.withValues(alpha: 0.12) : null,
        border: Border(bottom: BorderSide(color: c.ground3)),
      ),
      child: wide
          ? Column(
              crossAxisAlignment: .stretch,
              children: [
                head(),
                Padding(
                  padding: Insets.flowInspectorWideEditor,
                  child: _editor(context),
                ),
              ],
            )
          : head(),
    );
    if (!takes) {
      return row(false);
    }
    // A wire dragged out of the canvas and let go here binds the field.
    return FieldDropZone(
      drop: FieldDrop(vm.id, onDrop: (from) => onBind(RowBound(index, from))),
      builder: (context, lit, _) => row(lit),
    );
  }

  Widget _editor(BuildContext context) {
    final c = context.colors;
    // The mark of a value of several lines opens it in the viewer.
    final open = switch (onView) {
      final view? => () => view(index),
      null => null,
    };
    final box = BoxDecoration(
      color: c.ground3,
      border: .all(color: c.line2),
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.segment)),
    );
    switch (vm.editor) {
      case FieldEditorVm.bound:
        // A bound field: the value that comes in, read only, in the
        // accent colour in a frame; the wire on the canvas shows its source.
        return Container(
          height: AppSizes.flowControl,
          padding: Insets.control,
          decoration: BoxDecoration(
            color: c.ground3,
            border: .all(color: vm.writes ? c.emberLine : c.goodLine),
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadii.segment),
            ),
          ),
          child: Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                child: LinesText(
                  vm.text.isEmpty ? '—' : vm.text,
                  onOpen: open,
                  style: mono(size: FontSizes.sm, color: c.emberNew),
                ),
              ),
              // A value of several lines needs the room for its first
              // line and its mark; the frame's colour says it is bound.
              if (!vm.text.contains('\n'))
                Text(
                  S.current.boundMark,
                  style: TextStyle(
                    fontSize: FontSizes.flowDetail,
                    color: vm.writes ? c.emberSoft : c.good,
                  ),
                ),
            ],
          ),
        );
      case FieldEditorVm.choice:
        return Container(
          height: AppSizes.flowControl,
          decoration: box,
          padding: Insets.control,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: vm.choices.contains(vm.value) ? vm.value : null,
              isExpanded: true,
              isDense: true,
              dropdownColor: c.ground3,
              icon: AppIcon(
                'ui_chevron_down',
                size: AppSizes.flowChoiceChevron,
                color: c.text4,
              ),
              style: mono(size: FontSizes.sm, color: c.text1),
              items: [
                for (final ch in vm.choices)
                  DropdownMenuItem(
                    value: ch,
                    child: Text(ch, maxLines: 1, overflow: .ellipsis),
                  ),
              ],
              onChanged: (v) => _typed(v ?? ''),
            ),
          ),
        );
      case FieldEditorVm.form:
        return Container(
          height: AppSizes.flowControl,
          decoration: box,
          padding: Insets.control,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<BlockFormVm>(
              value: vm.form,
              isExpanded: true,
              isDense: true,
              dropdownColor: c.ground3,
              icon: AppIcon(
                'ui_chevron_down',
                size: AppSizes.flowChoiceChevron,
                color: c.text4,
              ),
              style: mono(size: FontSizes.sm, color: c.text1),
              items: [
                for (final f in vm.forms)
                  DropdownMenuItem(
                    value: f,
                    child: Text(f.label, maxLines: 1, overflow: .ellipsis),
                  ),
              ],
              onChanged: (f) {
                if (f != null) {
                  onForm?.call(f);
                }
              },
            ),
          ),
        );
      case FieldEditorVm.toggle:
        return Align(
          alignment: .centerLeft,
          child: SizedBox(
            height: AppSizes.flowControl,
            child: FittedBox(
              child: Switch(
                key: ValueKey('toggle-${vm.id}'),
                value: vm.on,
                onChanged: (v) async {
                  // A toggle with a warning asks before it goes on.
                  if (v) {
                    if (vm.confirm case final message?) {
                      final yes = await ConfirmDialog.ask(
                        context,
                        title: S.current.runOnStartTitle,
                        message: message,
                        confirm: S.current.turnOn,
                        cancel: S.current.cancel,
                      );
                      if (!yes) {
                        return;
                      }
                    }
                  }
                  _typed('$v');
                },
              ),
            ),
          ),
        );
      case FieldEditorVm.text || FieldEditorVm.defaults:
        return _TextEditor(
          value: vm.text,
          decoration: box,
          onChanged: _typed,
        );
      case FieldEditorVm.output:
        // The value, and under it where it goes: each has the whole cell,
        // so a time or an error's text is not cut by `not bound`.
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.flowControl),
          child: Padding(
            padding: Insets.flowInspectorOutput,
            child: Column(
              mainAxisAlignment: .center,
              crossAxisAlignment: .start,
              children: [
                if (vm.text.isNotEmpty)
                  LinesText(
                    vm.text,
                    onOpen: open,
                    style: mono(size: FontSizes.sm, color: c.text1),
                  ),
                Text(
                  vm.targets.isEmpty
                      ? S.current.notBound
                      : '→ ${[for (final t in vm.targets) t.text].join(', ')}',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: mono(size: FontSizes.flowDetail, color: c.text4),
                ),
              ],
            ),
          ),
        );
      case FieldEditorVm.run || FieldEditorVm.command:
        // Off, it says why under the button, not only in its tooltip; a
        // command is pressed only by a sample on its wire.
        final command = vm.editor == FieldEditorVm.command;
        final why = command ? S.current.commandNote : vm.off?.text;
        return Padding(
          padding: why == null ? EdgeInsets.zero : Insets.flowInspectorRunWhy,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            spacing: AppSpacing.xs,
            children: [
              Button.secondary(
                key: ValueKey('run-${vm.id}'),
                label: command ? vm.label : S.current.runBlock,
                icon: 'action_play',
                size: ButtonSize.small,
                disabledReason: why,
                onPressed: why != null || onRun == null
                    ? null
                    : () => onRun!(index),
              ),
              if (why != null)
                Text(
                  why,
                  style: TextStyle(
                    fontSize: FontSizes.xs,
                    height: 1.35,
                    color: c.text4,
                  ),
                ),
            ],
          ),
        );
      case FieldEditorVm.duration:
        return _DurationEditor(
          key: ValueKey('duration-${vm.id}'),
          millis: vm.text,
          decoration: box,
          onChanged: _typed,
        );
      case FieldEditorVm.suggest:
        return SuggestField(
          key: ValueKey('suggest-field-${vm.id}'),
          vm: SuggestFieldVm(
            id: vm.id,
            value: vm.text,
            choices: vm.choices,
            menuLabel: S.current.suggestPick,
          ),
          decoration: box,
          onChanged: _typed,
        );
      case FieldEditorVm.rows:
        final rows = vm.rows;
        if (rows == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: RowsEditor(
            key: ValueKey('rows-editor-${vm.id}'),
            vm: rows,
            decoration: box,
            onChanged: (list) => _typed(jsonEncode(list)),
          ),
        );
      case FieldEditorVm.sample:
        return SizedBox(
          height: AppSizes.flowControl,
          child: Padding(
            padding: Insets.control,
            child: Align(
              alignment: .centerLeft,
              child: LinesText(
                switch (vm.value) {
                  null => S.current.eventNone,
                  final v when v.isEmpty => '—',
                  final v => v,
                },
                onOpen: open,
                style: mono(size: FontSizes.sm, color: c.text3),
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
      spacing: AppSpacing.flowRowParts,
      children: [
        Expanded(
          child: _TextEditor(
            value: _shown,
            decoration: widget.decoration,
            onChanged: (t) => _typed(t, _unit),
          ),
        ),
        Container(
          height: AppSizes.flowControl,
          width: AppSizes.flowUnitBox,
          decoration: widget.decoration,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _unit,
              isExpanded: true,
              isDense: true,
              dropdownColor: c.ground3,
              icon: AppIcon(
                'ui_chevron_down',
                size: AppSizes.flowDropChevron,
                color: c.text4,
              ),
              style: mono(size: FontSizes.sm, color: c.text1),
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
    // A text of several lines (a CSV typed in the value viewer) keeps its
    // lines here: a one-line field would drop them at the next key.
    final lines = _controller.text.contains('\n');
    return Container(
      height: lines ? null : AppSizes.flowControl,
      constraints: lines
          ? const BoxConstraints(minHeight: AppSizes.flowControl)
          : null,
      decoration: widget.decoration,
      padding: lines ? Insets.flowTextEditorLines : Insets.control,
      alignment: .centerLeft,
      child: TextField(
        key: lines ? const ValueKey('text-editor-lines') : null,
        controller: _controller,
        focusNode: _focus,
        maxLines: lines ? 6 : 1,
        minLines: 1,
        keyboardType: lines ? .multiline : null,
        onChanged: (v) {
          widget.onChanged(v);
          if (v.contains('\n') != lines) {
            setState(() {});
          }
        },
        style: mono(size: FontSizes.sm, color: c.text1),
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
/// An item of a [_LinkMenu]: its word and what it does.
final class _LinkItem {
  const _LinkItem(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}

class _LinkMenu extends StatelessWidget {
  const _LinkMenu({required this.icon, required this.items});

  final Widget icon;
  final List<_LinkItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<int>(
      padding: EdgeInsets.zero,
      tooltip: '',
      color: c.ground3,
      position: .under,
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (_) => [
        for (final (i, item) in items.indexed)
          PopupMenuItem(
            value: i,
            height: AppSizes.flowLinkMenuItem,
            child: Text(
              item.label,
              style: TextStyle(fontSize: FontSizes.md, color: c.text1),
            ),
          ),
      ],
      child: Center(child: icon),
    );
  }
}
