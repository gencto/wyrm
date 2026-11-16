import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_def.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'flow_def.dart';

// The custom blocks of a flow definition (spec 06 0.2.24, ADR 0040 §3):
// `blocks.<name>` = `{description?, inputs: [{name, to, default?,
// description?}], outputs: [{name, from, description?}], nodes, edges,
// layout}`.
//
// A definition's blocks are read once, with the flow ([flowReadOf]), into
// typed [BlockDef]s the draft holds ([FlowDraft.defs]); they go back to the
// engine, the library and the clipboard through [blockDefJsonOf]. Both
// ways are here, and only here.

const _shape = 'block def';

/// The editor's keys of a block's `layout` (spec 06 0.2.26: the engine
/// reads none of it): where the inside view keeps the two boundary blocks,
/// and the library version a block was copied at.
const inputsAtKey = '_~port~in';
const outputsAtKey = '_~port~out';
const libraryMarkKey = '_~lib~version';

/// The inside of a custom block as a draft: its [blocks] and [edges], with
/// no id (a block's definition has none), as [blockDefOf] reads it.
FlowDraft blockBodyOf(
  IMap<String, FlowBlock> blocks, [
  IList<FlowEdge> edges = const IListConst([]),
]) => FlowDraft(id: _bodyId, blocks: blocks, edges: edges);

/// The id of a block's inside ([blockBodyOf]).
const _bodyId = '';

/// The definition [json] of a custom block, read. [Invalid], with the
/// field, when a port has no `name`, a `to` or a `from` is not
/// `<node>.<port>`, the description is no text, or its body does not read
/// as a flow's ([flowReadOf]).
Decoded<BlockDef> blockDefOf(Map<String, Object?> json) {
  try {
    final layout = _layoutOf(json);
    final Value body;
    try {
      body = Value.from({
        'nodes': json['nodes'] ?? const <String, Object?>{},
        'edges': json['edges'] ?? const <Object?>[],
        'layout': layout,
      });
    } on Object {
      throw const _Bad('nodes', 'not JSON');
    }
    final read = switch (flowReadOf(_bodyId, body)) {
      Valid(:final value) => value,
      Invalid(:final field, :final reason) => throw _Bad(field, reason),
    };
    final draft = read.draft;
    return Valid(
      BlockDef(
        body: draft,
        description: switch (json['description']) {
          null => null,
          final String s => s,
          _ => throw const _Bad('description', 'not a text'),
        },
        inputs: _ports(json['inputs'], 'inputs', 'to'),
        outputs: _ports(json['outputs'], 'outputs', 'from'),
        libraryVersion: switch (layout[libraryMarkKey]) {
          [final num v, ...] => v.toInt(),
          _ => null,
        },
        inputsAt: _at(layout[inputsAtKey]),
        outputsAt: _at(layout[outputsAtKey]),
        placed: read.placed.length == draft.blocks.length ? null : read.placed,
        hasLayout: json.containsKey('layout'),
        extra: {
          for (final MapEntry(:key, :value) in json.entries)
            if (!_read.contains(key)) key: value,
        }.lock,
      ),
    );
  } on _Bad catch (b) {
    return Invalid(_shape, b.field, b.reason);
  }
}

Map<String, Object?> _layoutOf(Map<String, Object?> json) =>
    switch (json['layout']) {
      null => const {},
      final Map<String, Object?> m => m,
      _ => throw const _Bad('layout', 'not a map'),
    };

(double, double)? _at(Object? v) => switch (v) {
  [final num x, final num y] => (x.toDouble(), y.toDouble()),
  _ => null,
};

List<BlockPort> _ports(Object? v, String field, String endsKey) {
  final list = switch (v) {
    null => const <Object?>[],
    final List<Object?> l => l,
    _ => throw _Bad(field, 'not an array'),
  };
  return [
    for (final (i, p) in list.indexed)
      switch (p) {
        final Map<String, Object?> m => BlockPort(
          switch (m['name']) {
            final String n when n.isNotEmpty => n,
            _ => throw _Bad('$field[$i].name', 'missing'),
          },
          oneEnd: m[endsKey] is String,
          ends: [
            for (final e in switch (m[endsKey]) {
              null => const <Object?>[],
              final String s => [s],
              final List<Object?> l => l,
              _ => throw _Bad('$field[$i].$endsKey', 'not a text or a list'),
            })
              switch (e) {
                final String s when portEndOf(s) != null => portEndOf(s)!,
                _ => throw _Bad('$field[$i].$endsKey', 'not <node>.<port>'),
              },
          ],
          defaultValue: m['default'],
          description: switch (m['description']) {
            null => null,
            final String s => s,
            _ => throw _Bad('$field[$i].description', 'not a text'),
          },
          extra: {
            for (final MapEntry(:key, :value) in m.entries)
              if (!_portKeys.contains(key) && key != endsKey) key: value,
          }.lock,
        ),
        _ => throw _Bad('$field[$i]', 'not a map'),
      },
  ];
}

final class _Bad implements Exception {
  const _Bad(this.field, this.reason);

  final String field;
  final String reason;
}

// ---------- the other way: a definition written back ----------

/// The keys of a port the editor reads besides its `to`/`from`; any other
/// is kept in [BlockPort.extra].
const _portKeys = {'name', 'default', 'description'};

/// The keys of a block's definition the editor reads; any other is kept
/// in [BlockDef.extra].
const _read = {'description', 'inputs', 'outputs', 'nodes', 'edges', 'layout'};

/// [def] as a flow's `blocks.<name>`, a library's `def` and the clipboard
/// write it.
Map<String, Object?> blockDefJsonOf(BlockDef def) => {
  ...def.extra.unlock,
  'description': ?def.description,
  'inputs': [
    for (final p in def.inputs)
      {
        'name': p.name,
        'to': p.oneEnd && p.ends.length == 1
            ? p.ends.single.wire
            : [for (final e in p.ends) e.wire],
        'default': ?p.defaultValue,
        'description': ?p.description,
        ...p.extra.unlock,
      },
  ],
  'outputs': [
    for (final p in def.outputs)
      {
        'name': p.name,
        if (p.ends.isNotEmpty) 'from': p.ends.first.wire,
        'description': ?p.description,
        ...p.extra.unlock,
      },
  ],
  'nodes': nodesJsonOf(def.body),
  'edges': edgesJsonOf(def.body),
  if (_layoutJsonOf(def) case final layout
      when def.hasLayout || layout.isNotEmpty)
    'layout': layout,
};

/// [def]'s `layout`: its placed nodes, the boundary blocks, the library
/// mark.
Map<String, Object?> _layoutJsonOf(BlockDef def) => {
  ...layoutJsonOf(def.body, placed: def.placed),
  if (def.inputsAt case (final x, final y)) inputsAtKey: [x.round(), y.round()],
  if (def.outputsAt case (final x, final y))
    outputsAtKey: [x.round(), y.round()],
  if (def.libraryVersion case final v?) libraryMarkKey: [v, 0],
};

/// [defs] as a definition's `blocks`.
Map<String, Map<String, Object?>> blockDefsJsonOf(
  IMap<String, BlockDef> defs,
) => {
  for (final MapEntry(:key, :value) in defs.entries) key: blockDefJsonOf(value),
};
