import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:wyrm_client/wyrm_client.dart' show TypeCode;

import '../mappers/block_cfg.dart';
import '../mappers/config_text.dart';
import '../mappers/flow_blocks.dart';
import '../mappers/flow_fields.dart';
import '../mappers/flow_mapper.dart';
import '../rights.dart';
import 'block_view.dart';
import 'off.dart';

/// What the inspector says the selected block is.
enum InspectorKind { ports, node, logic, sink, action, my }

/// The note under the inspector's title.
enum InspectorNote {
  /// The inputs block of an inside view.
  inputs,

  /// The outputs block of an inside view.
  outputs,

  /// A point of the tree (`subscribe`, `set`, …).
  treeNode,

  /// An action block with behaviours (ADR 0040 §2).
  actionBlock,

  /// A plain action block.
  action,

  /// Any other: the catalogue's description ([InspectorView.description]).
  catalog,
}

/// Why `Run` of a block's trigger is off ([OffFor.reason]).
enum RunOffReason {
  /// The broker has no `trigger` action.
  noBroker,

  /// The flow is not deployed.
  notDeployed,

  /// The draft differs from the deployed version.
  draft,

  /// A block of a custom block opened from the palette: no instance runs.
  noInstance,

  /// The block's `enabled` is off.
  off,
}

/// How a parameter is typed in the inspector.
enum ParamRowEditor { rows, suggest, choice, toggle, duration, text }

/// How an argument of an action block is typed.
enum ArgRowEditor { choice, toggle, text }

/// One column of a list of maps (`mapping`, `aggregates`).
final class RowsColumn extends Equatable {
  const RowsColumn(this.key, this.label, {this.choices = const IListConst([])});

  final String key;

  /// [humanize] of [key].
  final String label;
  final IList<String> choices;

  @override
  List<Object?> get props => [key, label, choices];
}

/// A list of maps typed a line per item.
final class RowsEditorView extends Equatable {
  const RowsEditorView({required this.columns, required this.rows});

  final IList<RowsColumn> columns;
  final IList<IMap<String, String>> rows;

  @override
  List<Object?> get props => [columns, rows];
}

/// One row of the inspector (spec §6): what every row has, and what its
/// editor needs.
sealed class InspectorRow extends Equatable {
  const InspectorRow({
    required this.id,
    required this.name,
    this.engine = '',
    this.inPort,
    this.hint = '',
    this.group = FieldGroup.none,
    this.pinned,
    this.pinLocked = false,
  });

  final RowId id;

  /// What the row reads ([FlowField.label]).
  final String name;

  /// What the engine calls it, when it reads otherwise; else ''.
  final String engine;
  final String? inPort;

  /// The catalogue's description of the field.
  final String hint;
  final FieldGroup group;

  /// On the block or not; null: a row with no pin (`Form`).
  final bool? pinned;

  /// A bound field stays on the block.
  final bool pinLocked;

  List<Object?> get _common => [
    id,
    name,
    engine,
    inPort,
    hint,
    group,
    pinned,
    pinLocked,
  ];
}

/// The form of a block of several (`scale`).
final class FormRowView extends InspectorRow {
  const FormRowView({required this.form, required this.forms})
    : super(id: const FormRow(), name: '');

  final BlockFormId form;
  final IList<BlockFormId> forms;

  @override
  List<Object?> get props => [..._common, form, forms];
}

/// A field bound by a wire: the value that comes in.
final class BoundRowView extends InspectorRow {
  const BoundRowView({
    required super.id,
    required super.name,
    required this.value,
    required this.source,
    required this.writes,
    super.engine,
    super.inPort,
    super.hint,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  final String value;

  /// The block the wire comes from (`Go to source`).
  final String source;

  /// The binding writes into a device.
  final bool writes;

  @override
  List<Object?> get props => [..._common, value, source, writes];
}

/// An unbound trigger: `Run`, or why it is off.
final class RunRowView extends InspectorRow {
  const RunRowView({
    required super.id,
    required super.name,
    this.off,
    super.engine,
    super.inPort,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  final Off<RunOffReason>? off;

  @override
  List<Object?> get props => [..._common, off];
}

/// A command input (`date_range` Next): a button a sample presses; Studio
/// cannot press it.
final class CommandRowView extends InspectorRow {
  const CommandRowView({
    required super.id,
    required super.name,
    super.engine,
    super.inPort,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  @override
  List<Object?> get props => _common;
}

/// An input of a custom block's inputs block: its default.
final class DefaultRowView extends InspectorRow {
  const DefaultRowView({
    required super.id,
    required super.name,
    required this.value,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  final String value;

  @override
  List<Object?> get props => [..._common, value];
}

/// A parameter of the block's config.
final class ParamRowView extends InspectorRow {
  const ParamRowView({
    required super.id,
    required super.name,
    required this.editor,
    required this.value,
    this.on = false,
    this.choices = const IListConst([]),
    this.rows,
    this.scopeError,
    this.confirm,
    super.engine,
    super.inPort,
    super.hint,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  final ParamRowEditor editor;
  final String value;

  /// What a [ParamRowEditor.toggle] shows: the typed value is `true`.
  final bool on;
  final IList<String> choices;
  final RowsEditorView? rows;

  /// A scope the engine would refuse, once it matters.
  final ScopeProblem? scopeError;

  /// `Run on start` asks first, with this warning of the catalogue.
  final String? confirm;

  @override
  List<Object?> get props => [
    ..._common,
    editor,
    value,
    on,
    choices,
    rows,
    scopeError,
    confirm,
  ];
}

/// An argument of an action block.
final class ArgRowView extends InspectorRow {
  const ArgRowView({
    required super.id,
    required super.name,
    required this.editor,
    required this.value,
    this.on = false,
    this.choices = const IListConst([]),
    super.engine,
    super.inPort,
    super.hint,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  final ArgRowEditor editor;
  final String value;

  /// What an [ArgRowEditor.toggle] shows: the typed value is `true`.
  final bool on;
  final IList<String> choices;

  @override
  List<Object?> get props => [..._common, editor, value, on, choices];
}

/// An operand: its typed constant until a binding replaces it.
final class OperandRowView extends InspectorRow {
  const OperandRowView({
    required super.id,
    required super.name,
    required this.value,
    this.range = false,
    super.engine,
    super.inPort,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  final String value;

  /// A range text of `date_range`: a text with the usual ones
  /// ([rangeChoices]).
  final bool range;

  @override
  List<Object?> get props => [..._common, value, range];
}

/// An output: its value and where it goes.
final class OutputRowView extends InspectorRow {
  const OutputRowView({
    required super.id,
    required super.name,
    required this.value,
    required this.targets,
    super.engine,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  /// Its value; null: an event that has not fired (or a run not made).
  final String? value;

  /// `<block>.<field label>` of every input it feeds; empty: not bound.
  final IList<String> targets;

  @override
  List<Object?> get props => [..._common, value, targets];
}

/// An input with no typed value: its last sample.
final class SampleRowView extends InspectorRow {
  const SampleRowView({
    required super.id,
    required super.name,
    required this.value,
    super.inPort,
    super.group,
    super.pinned,
    super.pinLocked,
  });

  /// Its sample ('' for none); null: an event that has not fired.
  final String? value;

  @override
  List<Object?> get props => [..._common, value];
}

/// The inspector of the selected block (spec §6).
final class InspectorView extends Equatable {
  const InspectorView({
    required this.id,
    required this.kind,
    required this.note,
    required this.rows,
    this.boundary,
    this.description = '',
    this.openInside = false,
  });

  /// The block's id: the title, unless it is a [boundary] block.
  final String id;
  final Boundary? boundary;
  final InspectorKind kind;
  final InspectorNote note;

  /// The catalogue's description ([InspectorNote.catalog]).
  final String description;

  /// `Open inside` above the rows (an instance on a broker with custom
  /// blocks).
  final bool openInside;
  final IList<InspectorRow> rows;

  /// The field of the inspector's row [row] (its index, as the inspector
  /// draws [rows]); null when there is none.
  RowId? rowAt(int row) => row >= 0 && row < rows.length ? rows[row].id : null;

  @override
  List<Object?> get props => [
    id,
    boundary,
    kind,
    note,
    description,
    openInside,
    rows,
  ];
}

/// Why `Run` is off for [b], or null when it runs: the engine's `trigger`
/// acts on the deployed flow, so the draft must be it.
Off<RunOffReason>? runOffOf(
  FlowBlock b, {
  required FlowCaps caps,
  required bool isNew,
  required bool deployed,
  required bool differs,
  required String? engineId,
  required Lack? write,
}) {
  if (!caps.trigger) {
    return const OffFor(RunOffReason.noBroker);
  }
  if (isNew || !deployed) {
    return const OffFor(RunOffReason.notDeployed);
  }
  if (differs) {
    return const OffFor(RunOffReason.draft);
  }
  if (engineId == null) {
    return const OffFor(RunOffReason.noInstance);
  }
  if (b.cfgEnabled == false) {
    return const OffFor(RunOffReason.off);
  }
  return offNeeds(write);
}

/// The inspector of block [b] of the canvas draft [d], with [fields] of
/// every block, [live] the values of [b], [runOff] why its trigger does
/// not run, [scopeProblemOf] what is wrong with a scope typed.
InspectorView inspectorViewOf(
  FlowBlock b,
  NodeType? t,
  FlowDraft d,
  Map<String, List<FlowField>> fields,
  LiveValue? Function(String) live, {
  required bool customBlocks,
  required Off<RunOffReason>? runOff,
  required ScopeProblem? Function(String scope) scopeProblemOf,
}) {
  final edges = d.edges;
  final boundary = Boundary.of(b.id);
  final role = roleOf(b.type);
  final keyed = scopedKeyOf(t);
  String inLabelOf(String block, String port) =>
      fields[block]?.where((f) => f.inPort == port).firstOrNull?.label ?? port;
  return InspectorView(
    id: b.id,
    boundary: boundary,
    kind: boundary != null
        ? InspectorKind.ports
        : switch (role) {
            BlockRole.node => InspectorKind.node,
            BlockRole.logic => InspectorKind.logic,
            BlockRole.sink => InspectorKind.sink,
            BlockRole.action => InspectorKind.action,
            BlockRole.custom => InspectorKind.my,
          },
    note: switch (boundary) {
      Boundary.inputs => InspectorNote.inputs,
      Boundary.outputs => InspectorNote.outputs,
      null when role == BlockRole.node => InspectorNote.treeNode,
      null when role == BlockRole.action =>
        behavesOf(t) ? InspectorNote.actionBlock : InspectorNote.action,
      null => InspectorNote.catalog,
    },
    description: t?.description ?? '',
    openInside: customBlocks && isInstance(b.type),
    rows: [
      if (formOf(b, edges) case final form?)
        FormRowView(
          form: form.id,
          forms: [for (final f in formsOf(b.type)) f.id].lock,
        ),
      for (final f in fields[b.id]!)
        _row(
          b,
          f,
          d,
          live,
          inLabelOf,
          t,
          keyed: keyed,
          runOff: runOff,
          scopeProblemOf: scopeProblemOf,
          group: groupOf(t, b, f),
          pinned: fieldPinned(b, f, edges),
          locked: fieldBound(b, f, edges),
        ),
    ].lock,
  );
}

InspectorRow _row(
  FlowBlock b,
  FlowField f,
  FlowDraft d,
  LiveValue? Function(String) live,
  String Function(String block, String port) inLabelOf,
  NodeType? t, {
  required ScopedKey? keyed,
  required Off<RunOffReason>? runOff,
  required ScopeProblem? Function(String scope) scopeProblemOf,
  required FieldGroup group,
  required bool pinned,
  required bool locked,
}) {
  final behaves = behavesOf(t);
  final engine = f.name == f.label ? '' : f.name;
  final into = f.inPort == null
      ? null
      : d.edges.where((e) => e.to == b.id && e.toPort == f.inPort).firstOrNull;
  final hint = f.spec?.description ?? '';
  if (into != null) {
    // The value that comes in, not where it comes from (owner decision
    // 2026-11-08): the wire shows the source, `Go to source` selects it.
    return BoundRowView(
      id: f.id,
      name: f.label,
      engine: engine,
      value: fieldValue(b, f, d, live).text,
      source: into.from,
      writes: writesTo(b.type),
      inPort: f.inPort,
      hint: hint,
      group: group,
      pinned: pinned,
      pinLocked: locked,
    );
  }
  // An unbound trigger is a button: the engine's `trigger` action on the
  // deployed flow (spec §19).
  if (f.id == FieldId.input(EnginePort.trigger.wire) && (t?.trigger ?? false)) {
    return RunRowView(
      id: f.id,
      name: f.label,
      engine: engine,
      off: runOff,
      inPort: f.inPort,
      group: group,
      pinned: pinned,
      pinLocked: locked,
    );
  }
  // A command (`date_range` Next, `table_page` First) is a button that a
  // sample on its wire presses; Studio has no way to press it itself.
  if (f.command) {
    return CommandRowView(
      id: f.id,
      name: f.label,
      engine: engine,
      inPort: f.inPort,
      group: group,
      pinned: pinned,
      pinLocked: locked,
    );
  }
  if (b.id == blockInputsId) {
    // An input of a custom block: its default is typed here.
    return DefaultRowView(
      id: f.id,
      name: f.label,
      value: _text(b.cfgDefaults[f.name]),
      group: group,
      pinned: pinned,
      pinLocked: locked,
    );
  }
  final p = f.spec;
  if (p != null) {
    final v = b.param(p.name) ?? p.defaultValue;
    final scoped = p.name == keyed?.scope;
    final keyBound =
        keyed != null &&
        d.edges.any((e) => e.to == b.id && e.toPort == keyed.port);
    // A list of maps (`mapping`, `aggregates`): a line per item.
    final items = listItemsOf(t, p);
    // A time zone or a range text: a text with the usual ones in a menu.
    final suggested = isTimeZoneParam(b.type, p)
        ? timeZoneChoicesOf(b.type)
        : (isRangeText(b.type, param: p.key) ? rangeChoices : null);
    return ParamRowView(
      id: f.id,
      name: f.label,
      engine: engine,
      rows: items == null
          ? null
          : RowsEditorView(
              columns: [
                for (final c in items)
                  RowsColumn(
                    c.key,
                    humanize(c.key),
                    choices: c.choices.lock,
                  ),
              ].lock,
              rows: [for (final r in listRowsOf(v)) r.lock].lock,
            ),
      // A scope that the engine would refuse says why, once it matters.
      scopeError: scoped && (keyBound || (v is String && v.trim().isNotEmpty))
          ? scopeProblemOf(v is String ? v : '')
          : null,
      // `Run on start` asks first, with the catalog's own warning.
      confirm: p.key == BlockCfgKey.runOnStart && p.warns ? hint : null,
      editor: items != null
          ? ParamRowEditor.rows
          : suggested != null
          ? ParamRowEditor.suggest
          : p.choices.isNotEmpty
          ? ParamRowEditor.choice
          : p.type == TypeCode.bool_
          ? ParamRowEditor.toggle
          // `now`'s clock is a period as a command's (spec 06 0.2.30)
          : (p.key == BlockCfgKey.intervalMs &&
                    (behaves || b.type.known == KnownBlock.now)
                ? ParamRowEditor.duration
                : ParamRowEditor.text),
      on: v == true,
      value: switch (v) {
        Map() || List() => jsonEditText(v),
        null => '',
        _ => '$v',
      },
      choices: (suggested ?? p.choices.unlock).lock,
      inPort: f.inPort,
      hint: hint,
      group: group,
      pinned: pinned,
      pinLocked: locked,
    );
  }
  if (f.kind == FieldKind.arg) {
    // An argument is typed as its action says: its choices, a toggle,
    // else a value.
    final spec = f.argSpec;
    return ArgRowView(
      id: f.id,
      name: f.label,
      engine: engine,
      editor: spec != null && spec.choices.isNotEmpty
          ? ArgRowEditor.choice
          : (spec?.type == TypeCode.bool_
                ? ArgRowEditor.toggle
                : ArgRowEditor.text),
      value: _text(b.cfgArgs[f.name]),
      on: b.cfgArgs[f.name] == true,
      choices: spec?.choices ?? const IListConst([]),
      inPort: f.inPort,
      hint: spec?.description ?? '',
      group: group,
      pinned: pinned,
      pinLocked: locked,
    );
  }
  if (f.operand) {
    // An operand holds a typed constant until a binding replaces it; an
    // instance's input its own constant, else the block's default.
    final v = isInstance(b.type)
        ? instanceValueOf(d, b, f.inPort!)
        : operandValueOf(b, f.inPort!);
    return OperandRowView(
      id: f.id,
      name: f.label,
      engine: engine,
      // The range text of a `date_range`: a text with the usual ones.
      range: isRangeText(b.type, port: f.port),
      value: _text(v),
      inPort: f.inPort,
      group: group,
      pinned: pinned,
      pinLocked: locked,
    );
  }
  final shown = fieldValue(b, f, d, live);
  final value = switch (f.name) {
    // An event: when it last fired, and for an error its code and message;
    // a run: its time. Null: none yet.
    _ when group == FieldGroup.events => eventText(
      live(portKey(PortSide.output, b.id, f.name)),
    ),
    'last_run' when behaves => lastRunText(shown.raw),
    _ => shown.text,
  };
  if (f.kind == FieldKind.output) {
    return OutputRowView(
      id: f.id,
      name: f.label,
      engine: engine,
      value: value,
      targets: [
        if (f.outPort != null)
          for (final e in d.edges)
            if (e.from == b.id && f.sends(e.fromPort))
              '${e.to}.${inLabelOf(e.to, e.toPort)}',
      ].lock,
      group: group,
      pinned: pinned,
      pinLocked: locked,
    );
  }
  return SampleRowView(
    id: f.id,
    name: f.label,
    value: value,
    inPort: f.inPort,
    group: group,
    pinned: pinned,
    pinLocked: locked,
  );
}

/// A typed value as its editor's text: a text as itself, anything else as
/// JSON, nothing as ''.
String _text(Object? v) => switch (v) {
  null => '',
  final String s => s,
  _ => jsonEncode(v),
};
