import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/flow_draft.dart';
import 'package:models/port_end.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'flow_def.dart';

// The custom blocks of a flow definition (spec 06 0.2.24, ADR 0040 §3):
// `blocks.<name>` = `{description?, inputs: [{name, to, default?,
// description?}], outputs: [{name, from, description?}], nodes, edges,
// layout}`.
//
// A definition keeps its blocks as they came, as JSON, in the draft's
// `rest['blocks']`: they go back to the engine and to the library as they
// are, and the editor changes them only through the functions of
// `mappers/flow_blocks.dart`. What the editor reads of one — its ports,
// their wires, its description, its body, the library version it was
// copied at, where its inside draws the boundary blocks — is read here,
// by [blockDefOf], and only here.

const _shape = 'block def';

/// One declared input or output of a custom block.
final class BlockPort {
  const BlockPort(
    this.name, {
    this.ends = const [],
    this.defaultValue,
    this.description,
  });

  final String name;

  /// An input: the inner inputs it feeds (`to`); an output: the one inner
  /// output it sends (`from`).
  final List<PortEnd> ends;
  final Object? defaultValue;
  final String? description;
}

/// A custom block's definition, read.
final class BlockDef {
  const BlockDef({
    required this.body,
    this.description,
    this.inputs = const [],
    this.outputs = const [],
    this.libraryVersion,
    this.inputsAt,
    this.outputsAt,
  });

  final String? description;
  final List<BlockPort> inputs;
  final List<BlockPort> outputs;

  /// Its nodes, edges and layout, read as a flow's (an id-less draft).
  final FlowDraft body;

  /// The library version it was copied at; null for a block made in the
  /// flow.
  final int? libraryVersion;

  /// Where its inside draws the inputs block and the outputs block.
  final (double, double)? inputsAt;
  final (double, double)? outputsAt;

  /// The custom blocks its nodes are instances of, by name.
  Set<String> get uses => {
    for (final b in body.blocks.values)
      if (b.type case CustomType(:final name)) name,
  };

  /// How many of its nodes are instances of [type].
  int instances(CustomType type) =>
      body.blocks.values.where((b) => b.type == type).length;
}

/// The editor's keys of a block's `layout` (spec 06 0.2.26: the engine
/// reads none of it): where the inside view keeps the two boundary blocks,
/// and the library version a block was copied at.
const inputsAtKey = '_~port~in';
const outputsAtKey = '_~port~out';
const libraryMarkKey = '_~lib~version';

/// The custom blocks a definition's [rest] holds (`blocks`), by name, as
/// JSON. A `blocks` that is no map, or an entry of it that is none, is
/// left out with a warning.
Map<String, Map<String, Object?>> blockDefsIn(IMap<String, Object?> rest) {
  final out = <String, Map<String, Object?>>{};
  switch (rest['blocks']) {
    case null:
      break;
    case final Map<Object?, Object?> m:
      for (final MapEntry(:key, :value) in m.entries) {
        if ((key, value) case (
          final String k,
          final Map<String, Object?> v,
        )) {
          out[k] = v;
        } else {
          decodeLog.warning('$_shape: blocks.$key: not a map');
        }
      }
    default:
      decodeLog.warning('$_shape: blocks: not a map');
  }
  return out;
}

/// The definition [json] of a custom block, read. [Invalid], with the
/// field, when a port has no `name`, a `to` or a `from` is not
/// `<node>.<port>`, the description is no text, or its body does not read
/// as a flow's ([flowReadOf]).
///
/// A definition is read once per map: the editor reads the same ones on
/// every dispatch, and a definition's map is never changed in place (an
/// edit makes a new one, `withBlockDefs`).
Decoded<BlockDef> blockDefOf(Map<String, Object?> json) =>
    _read[json] ??= _blockDefOf(json);

final _read = Expando<Decoded<BlockDef>>('block def');

Decoded<BlockDef> _blockDefOf(Map<String, Object?> json) {
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
    final draft = switch (flowReadOf('', body)) {
      Valid(:final value) => value.draft,
      Invalid(:final field, :final reason) => throw _Bad(field, reason),
    };
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
      ),
    );
  } on _Bad catch (b) {
    return Invalid(_shape, b.field, b.reason);
  }
}

/// The definition [json], or null with a warning naming the block [name]
/// and the field when it does not read.
BlockDef? blockDefOrWarn(String name, Map<String, Object?> json) =>
    blockDefOf(json).orWarn('block $name');

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

// ---------- the other way: definitions changed as JSON ----------

/// [json] with every node of type [from] made one of type [to] (a block
/// renamed).
Map<String, Object?> withInstancesRenamed(
  Map<String, Object?> json,
  CustomType from,
  CustomType to,
) => {
  ...json,
  if (json['nodes'] case final Map<String, Object?> nodes)
    'nodes': {
      for (final MapEntry(:key, :value) in nodes.entries)
        key: switch (value) {
          final Map<String, Object?> m when m['type'] == from.wire => {
            ...m,
            'type': to.wire,
          },
          _ => value,
        },
    },
};

/// [json] marked as copied from the library at [version].
Map<String, Object?> withLibraryVersion(
  Map<String, Object?> json,
  int version,
) => {
  ...json,
  'layout': {
    ..._layoutOr(json),
    libraryMarkKey: [version, 0],
  },
};

/// [json] as the library takes it: without the editor's mark of where it
/// came from.
Map<String, Object?> libraryDefOf(Map<String, Object?> json) => {
  ...json,
  'layout': {..._layoutOr(json)}..remove(libraryMarkKey),
};

Map<String, Object?> _layoutOr(Map<String, Object?> json) =>
    switch (json['layout']) {
      final Map<String, Object?> m => m,
      _ => const {},
    };
