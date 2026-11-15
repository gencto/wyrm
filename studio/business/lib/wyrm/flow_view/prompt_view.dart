import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/node_type.dart';
import 'package:models/port_end.dart';

import '../decode/block_cfg.dart';
import '../mappers/flow_blocks.dart';
import '../mappers/flow_canvas.dart';
import '../mappers/flow_fields.dart';

/// The site of [root] (`wy/<site>` → `<site>`).
String siteOf(String root) => root.startsWith('wy/') ? root.substring(3) : root;

/// What is wrong with a scope typed for a key of the site of [root].
ScopeProblem? scopeProblemAt(String root, String scope) =>
    scopeProblem(scope, site: siteOf(root));

/// The scope asked of a key that got a wire (spec §17): on its `Scope` row
/// when the block shows it, else on its key's.
final class ScopePromptView extends Equatable {
  const ScopePromptView({
    required this.block,
    required this.row,
    required this.value,
    required this.suggestions,
  });

  final String block;
  final FieldId row;

  /// The scope it starts with: the block's own, else the suggested one.
  final String value;
  final IList<String> suggestions;

  @override
  List<Object?> get props => [block, row, value, suggestions];
}

/// The scope prompt of block [block] of [blocks] (with its [rows], the
/// pinned fields); null when it asks nothing.
ScopePromptView? scopePromptOf(
  String root,
  String? block,
  IMap<String, FlowBlock> blocks,
  Map<BlockType, NodeType> types,
  Map<String, List<FlowField>> rows,
) {
  final b = blocks[block ?? ''];
  final keyed = scopedKeyOf(types[b?.type]);
  if (b == null || keyed == null) {
    return null;
  }
  final own = b.textOf(keyed.scope);
  final suggested = scopeSuggestion(b.textOf(keyed.key), site: siteOf(root));
  final onBlock = rows[b.id]?.any((f) => f.id == keyed.scopeField) ?? false;
  return ScopePromptView(
    block: b.id,
    row: onBlock ? keyed.scopeField : keyed.keyField,
    value: own == null || own.trim().isEmpty ? suggested : own,
    suggestions: {
      suggested,
      for (final s in scopeSections) '$s/**',
    }.toIList(),
  );
}

/// One port of the block a selection would become, with what it is wired
/// to outside.
final class CustomPortView extends Equatable {
  const CustomPortView(this.name, this.outside);

  final String name;

  /// An input: the one outside output that feeds it; an output: every
  /// outside input it feeds.
  final IList<PortEnd> outside;

  @override
  List<Object?> get props => [name, outside];
}

/// What `Create custom block…` asks (spec §20): a free name, and the ports
/// the selection would have.
final class CustomBlockView extends Equatable {
  const CustomBlockView({
    required this.name,
    required this.blocks,
    required this.inputs,
    required this.outputs,
  });

  /// The suggested name: the first free `block<n>`.
  final String name;

  /// How many blocks the selection holds.
  final int blocks;
  final IList<CustomPortView> inputs;
  final IList<CustomPortView> outputs;

  @override
  List<Object?> get props => [name, blocks, inputs, outputs];
}

/// What the dialog asks of the selection [selection] of [d]; null when
/// there is nothing to make a block of, or the broker has none.
CustomBlockView? customBlockOf(
  FlowDraft? d,
  ISet<String> selection, {
  required bool customBlocks,
}) {
  final ids = {
    for (final id in selection)
      if (!isBoundary(id)) id,
  };
  if (d == null || ids.isEmpty || !customBlocks) {
    return null;
  }
  final sub = extractSubflow(d, ids);
  final defs = blockDefsOf(d);
  var n = 1;
  while (defs.containsKey('block$n')) {
    n++;
  }
  return CustomBlockView(
    name: 'block$n',
    blocks: sub.blocks.length,
    inputs: [
      for (final p in sub.inputs)
        CustomPortView(p.name, [p.outside.first].lock),
    ].lock,
    outputs: [
      for (final p in sub.outputs) CustomPortView(p.name, p.outside.lock),
    ].lock,
  );
}

/// The block the dialog hands back to make: a default is read as JSON
/// when it parses (`2` is a number, `AHU-` a text).
CustomBlockSpec customBlockSpecOf({
  required String name,
  required String description,
  required List<String> inputs,
  required List<String> outputs,
  required Map<String, String> defaults,
}) => CustomBlockSpec(
  name: name,
  description: description,
  inputs: inputs,
  outputs: outputs,
  defaults: {
    for (final e in defaults.entries) e.key: typedText(e.value, FieldEdit.any),
  },
);

/// What is wrong with [name] for a custom block of a flow with [defs]
/// (`Rename`); null: it is free.
BlockNameProblem? blockNameProblemOf(
  Map<String, Map<String, Object?>> defs,
  String name,
) => !blockNameOk(name)
    ? BlockNameProblem.name
    : (defs.containsKey(name) ? BlockNameProblem.taken : null);

/// What is wrong with [text] typed in the viewer for field [row] of [b];
/// null: it saves (or the field is not typed).
FieldEditError? viewerTextErrorOf(
  FlowBlock b,
  RowId row,
  List<FlowField> fields,
  FlowDraft d,
  String text,
) {
  final f = fields.where((f) => f.id == row).firstOrNull;
  final edit = f == null ? null : fieldEditOf(b, f, d.edges).edit;
  return edit == null ? null : fieldEditError(text, edit);
}

/// A refusal of a wire, with the label of the field it was let go on
/// ([BindRefusal.noInput], [BindRefusal.needsBroker] name it).
final class WireRefusal extends Equatable {
  const WireRefusal(this.refused, this.label);

  final Refused refused;
  final String label;

  @override
  List<Object?> get props => [refused, label];
}

/// Where a dragged wire is: from [from] over row [row] of block [block];
/// [replacing] the wire being moved, if any.
final class WireAsk extends Equatable {
  const WireAsk(this.from, this.block, this.row, {this.replacing});

  final PortEnd from;
  final String block;
  final RowId row;
  final PortEnd? replacing;

  @override
  List<Object?> get props => [from, block, row, replacing];
}

/// Why the wire [ask] would not bind, or null when it would (or the row is
/// gone).
WireRefusal? wireRefusalOf(
  WireAsk ask,
  FlowDraft? d,
  Map<BlockType, NodeType> types,
  Map<String, List<FlowField>> fields,
) {
  final to = fields[ask.block]?.where((f) => f.id == ask.row).firstOrNull;
  if (d == null || to == null) {
    return null;
  }
  final r = bindRefusal(
    types,
    d,
    fromBlock: ask.from.block,
    fromPort: ask.from.port,
    toBlock: ask.block,
    to: to,
    replacing: ask.replacing,
  );
  return r == null ? null : WireRefusal(r, to.label);
}
