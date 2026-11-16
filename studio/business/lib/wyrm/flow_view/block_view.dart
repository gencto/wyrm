import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_frame.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/node_type.dart';

import '../mappers/block_cfg.dart';
import '../mappers/flow_blocks.dart';
import '../mappers/flow_fields.dart';
import '../mappers/value_text.dart';

/// The two blocks of the inside of a custom block: its inputs and its
/// outputs ([blockInputsId], [blockOutputsId]).
enum Boundary {
  inputs,
  outputs;

  /// The boundary block [id] is, or null for a block of the flow.
  static Boundary? of(String id) => switch (id) {
    blockInputsId => inputs,
    blockOutputsId => outputs,
    _ => null,
  };
}

/// The width of the inputs and outputs blocks of an inside view: names
/// only.
const boundaryBlockWidth = 160.0;

/// What a sink would do in the preview (nothing is written): its kind.
enum GhostKind {
  /// An action block with behaviours sends its action.
  send,

  /// A plain action block runs its action.
  run,

  /// A `set`/`publish`/… writes its point.
  write,
}

/// How a row's value is drawn.
enum RowTone { plain, bound, bad, stale, ghost }

/// A port's mark beside a row: none, free, bound, bound into a device.
enum PortMarkKind { none, free, bound, write }

/// What − and + of a block change: the ports of a boundary block, the
/// pairs of `case`/`router`, or the inputs of `add`, `if`, ….
enum VariadicKind { ports, pairs, inputs }

/// The − / + row under a block's fields.
final class VariadicView extends Equatable {
  const VariadicView(this.kind, {required this.count, required this.canRemove});

  final VariadicKind kind;
  final int count;
  final bool canRemove;

  @override
  List<Object?> get props => [kind, count, canRemove];
}

/// One row of a block on the canvas: a pinned field.
final class RowView extends Equatable {
  const RowView({
    required this.id,
    required this.label,
    required this.name,
    required this.value,
    required this.tone,
    required this.inMark,
    required this.outMark,
    this.ghost,
    this.inPort,
    this.outPort,
    this.outAliases = const IListConst([]),
    this.editScope = false,
    this.command = false,
  });

  final FieldId id;
  final String label;
  final String name;

  /// What it shows: its value as text ('' for none), or — on the row a
  /// sink's [ghost] stands on — the value the sink would send or write.
  final String value;

  /// Set on the row a sink's ghost stands on (the preview).
  final GhostKind? ghost;
  final RowTone tone;
  final String? inPort;
  final String? outPort;
  final IList<String> outAliases;
  final PortMarkKind inMark;
  final PortMarkKind outMark;

  /// The scope of a key: its pencil opens the scope prompt.
  final bool editScope;

  /// A command input, drawn as a button.
  final bool command;

  @override
  List<Object?> get props => [
    id,
    label,
    name,
    value,
    ghost,
    tone,
    inPort,
    outPort,
    outAliases,
    inMark,
    outMark,
    editScope,
    command,
  ];
}

/// A block on the canvas (spec §3, §12).
final class BlockView extends Equatable {
  const BlockView({
    required this.id,
    required this.role,
    required this.caption,
    required this.x,
    required this.y,
    required this.width,
    required this.selected,
    required this.rows,
    this.boundary,
    this.ghost = false,
    this.openable = false,
    this.variadic,
  });

  /// Its id; its title unless it is a [boundary] block.
  final String id;
  final Boundary? boundary;
  final BlockRole role;

  /// What it is, in parts (`tcp-tank`, `ramp`): a point's connection, an
  /// action block's node and action, a custom block's name, else the
  /// engine's type.
  final IList<String> caption;
  final double x;
  final double y;
  final double width;
  final bool selected;

  /// A sink in the preview: it shows what it would do (a `preview` tag).
  final bool ghost;

  /// An instance of a custom block on a broker with them: `Open inside`.
  final bool openable;
  final IList<RowView> rows;
  final VariadicView? variadic;

  @override
  List<Object?> get props => [
    id,
    boundary,
    role,
    caption,
    x,
    y,
    width,
    selected,
    ghost,
    openable,
    rows,
    variadic,
  ];
}

/// A wire between two blocks.
final class WireView extends Equatable {
  const WireView({
    required this.from,
    required this.fromPort,
    required this.to,
    required this.toPort,
    required this.writes,
    required this.firesAtDeploy,
  });

  final String from;
  final String fromPort;
  final String to;
  final String toPort;

  /// It writes into a device (into a `set` or an `invoke`).
  final bool writes;

  /// A parameter's echo or a variable's value into a device's `in`: it
  /// writes at every deploy (ADR 0038 §6, ADR 0040 §2).
  final bool firesAtDeploy;

  @override
  List<Object?> get props => [
    from,
    fromPort,
    to,
    toPort,
    writes,
    firesAtDeploy,
  ];
}

/// The block [b] of draft [d] as the canvas draws it, with its [rows] (the
/// pinned fields), its values from [live], selected or not.
BlockView blockViewOf(
  FlowBlock b,
  NodeType? t,
  List<FlowField> rows,
  FlowDraft d,
  LiveValue? Function(String) live, {
  required bool selected,
  required bool previewing,
  required String root,
  required IList<FlowFrame> frames,
  required IMap<String, LiveValue> previewSinks,
  required bool previewFailed,
  required IMap<String, NodeInfo> nodes,
  required bool customBlocks,
}) {
  final role = roleOf(b.type);
  final writes = writesTo(b.type);
  final point = pointOf(b);
  final keyed = scopedKeyOf(t);
  final behaves = behavesOf(t);
  // The row a sink's ghost stands on: its value's, else its trigger's.
  final trigger = FieldId.input(EnginePort.trigger.wire);
  final ghostRow =
      rows.any((f) => f.kind == FieldKind.input && f.port == EnginePort.in_)
      ? FieldId.input(EnginePort.in_.wire)
      : (rows.any((f) => f.id == trigger) ? trigger : rows.firstOrNull?.id);
  // What a sink would write in the preview (nothing is written).
  final ghost = previewing && isSink(b.type)
      ? previewSinks[engineIdOf(frames, b.id) ?? b.id]
      : null;
  // The draft no longer runs: the preview's last values, greyed.
  final stale = previewing && previewFailed;
  final info = point == null ? null : nodes[fullKey(root, point)];
  final v = variadicOf(t, b);
  final boundary = Boundary.of(b.id);
  return BlockView(
    id: b.id,
    boundary: boundary,
    role: role,
    caption: [
      ...switch (role) {
        BlockRole.node => [connectionOf(point, parent: true)],
        // The action block names what it runs: `tcp-tank · ramp`.
        BlockRole.action => [
          connectionOf(point, parent: false).split('/').last,
          if (b.cfgAction case final a? when behaves) a,
        ],
        BlockRole.custom => [blockNameOf(b.type) ?? ''],
        _ => [b.type.wire],
      },
    ].where((x) => x.isNotEmpty).toIList(),
    openable: isInstance(b.type) && customBlocks,
    x: b.x,
    y: b.y,
    width: boundary != null ? boundaryBlockWidth : blockWidthOf(role),
    selected: selected,
    ghost: ghost != null,
    rows: [
      for (final f in rows)
        () {
          final value = fieldValue(
            b,
            f,
            d,
            live,
            unit: info?.unit,
            choices: info?.choices.unlock ?? const [],
          );
          final group = groupOf(t, b, f);
          final ghostKind = ghost != null && f.id == ghostRow
              ? (b.type.known == KnownBlock.invoke
                    ? (behaves ? GhostKind.send : GhostKind.run)
                    : GhostKind.write)
              : null;
          return RowView(
            id: f.id,
            label: f.label,
            name: f.name,
            ghost: ghostKind,
            // An event reads when it fired, not its map; a run its time.
            value: switch (ghostKind) {
              GhostKind.send || GhostKind.run => valueText(ghost!.value),
              GhostKind.write => valueText(
                ghost!.value,
                unit: info?.unit,
                choices: info?.choices.unlock ?? const [],
              ),
              null => switch (f.port) {
                // A command is a button: it shows no value.
                _ when f.command => '',
                _ when group == FieldGroup.events =>
                  eventText(live(portKey(PortSide.output, b.id, f.name))) ?? '',
                EnginePort.lastRun when behaves =>
                  lastRunText(value.raw) ?? '',
                _ => value.text,
              },
            },
            // The scope is typed in its prompt: the pencil opens it.
            editScope: f.name == keyed?.scope,
            command: f.command,
            tone: switch (value) {
              _ when ghostKind != null => RowTone.ghost,
              FieldValue(bad: true) => RowTone.bad,
              FieldValue(live: true) when stale => RowTone.stale,
              FieldValue(bound: true) => RowTone.bound,
              _ => RowTone.plain,
            },
            inPort: f.inPort,
            outPort: f.outPort,
            outAliases: f.outAliases.lock,
            inMark: f.inPort == null
                ? PortMarkKind.none
                : (!value.bound
                      ? PortMarkKind.free
                      : (writes ? PortMarkKind.write : PortMarkKind.bound)),
            outMark: f.outPort == null
                ? PortMarkKind.none
                : (d.edges.any((e) => e.from == b.id && f.sends(e.fromPort))
                      ? PortMarkKind.bound
                      : PortMarkKind.free),
          );
        }(),
    ].lock,
    variadic: boundary != null
        ? VariadicView(
            VariadicKind.ports,
            count: rows.length,
            canRemove: rows.isNotEmpty,
          )
        : v == null
        ? null
        // A pair of inputs (`case`) or a case with its output (`router`).
        : (v.step == 2 || v.outPrefix != null
              ? VariadicView(
                  VariadicKind.pairs,
                  count: v.names.length ~/ v.step,
                  canRemove: v.removes.isNotEmpty,
                )
              : VariadicView(
                  VariadicKind.inputs,
                  count: v.names.length,
                  canRemove: v.removes.isNotEmpty,
                )),
  );
}

/// The wires of [d]: which write into a device, and which of those fire at
/// every deploy.
IList<WireView> wireViewsOf(
  FlowDraft d,
  Map<String, List<FlowField>> fields,
) => [
  for (final e in d.edges)
    () {
      final writes = writesTo(d.blocks[e.to]?.type) && e.to != blockOutputsId;
      // A parameter's echo and a variable's value send at start: into a
      // device they write at every deploy (ADR 0038 §6, `blocks.rs`).
      final fromParam =
          fields[e.from]?.where((f) => f.sends(e.fromPort)).firstOrNull?.kind ==
          FieldKind.param;
      return WireView(
        from: e.from,
        fromPort: e.fromPort,
        to: e.to,
        toPort: e.toPort,
        writes: writes,
        // Only `in` acts on a value sent at start; a trigger, an
        // argument and a behaviour never do (ADR 0040 §2).
        firesAtDeploy: writes && fromParam && e.target.known == EnginePort.in_,
      );
    }(),
].lock;
