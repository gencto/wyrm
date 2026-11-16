import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_def.dart';
import 'package:models/flow_draft.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'block_def.dart';
import 'decoded.dart';
import 'flow_def.dart';

// The flow editor's clipboard text both ways (flow-editor.md §13, §20): a
// JSON object `{format, nodes, edges, layout, blocks?}` whose `nodes`,
// `edges` and `layout` are written as a definition writes them (spec 06),
// and `blocks` holds the custom blocks the copied instances are of, with
// all they use, so an instance pasted into another flow brings its
// definition.

/// The clipboard format.
const clipFormat = 'wyrm-flow-blocks/1';

/// A clipboard text larger than this is not read.
const int _clipMax = 4 * 1024 * 1024;

const _shape = 'flow clipboard';

/// The blocks a clipboard [text] holds, as an id-less draft with only the
/// edges among them. [Invalid] when it is anything else: empty, too large,
/// no JSON object, another `format`, no `nodes`, or `nodes`/`edges`/
/// `layout` that do not read as a definition's ([flowReadOf]).
Decoded<FlowDraft> clipOf(String? text) {
  if (text == null || text.isEmpty) {
    return const Invalid(_shape, '', 'empty');
  }
  if (text.length > _clipMax) {
    return const Invalid(_shape, '', 'too large');
  }
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return const Invalid(_shape, '', 'not JSON');
  }
  if (json is! Map<String, Object?>) {
    return const Invalid(_shape, '', 'not an object');
  }
  if (json['format'] != clipFormat) {
    return const Invalid(_shape, 'format', 'not $clipFormat');
  }
  final nodes = json['nodes'];
  if (nodes is! Map<String, Object?> || nodes.isEmpty) {
    return const Invalid(_shape, 'nodes', 'missing');
  }
  final blocks = json['blocks'];
  if (blocks != null && blocks is! Map<String, Object?>) {
    return const Invalid(_shape, 'blocks', 'not a map');
  }
  final Value def;
  try {
    def = Value.from({
      'nodes': nodes,
      'edges': json['edges'] ?? const <Object?>[],
      'layout': json['layout'] ?? const <String, Object?>{},
      'blocks': ?blocks,
    });
  } on Object {
    return const Invalid(_shape, '', 'not JSON values');
  }
  return switch (flowReadOf('', def)) {
    Valid(value: FlowRead(:final draft)) => Valid(
      // Only edges among the blocks themselves.
      draft.copyWith(
        edges: draft.edges.removeWhere(
          (e) =>
              !draft.blocks.containsKey(e.from) ||
              !draft.blocks.containsKey(e.to),
        ),
      ),
    ),
    Invalid(:final field, :final reason) => Invalid(_shape, field, reason),
  };
}

/// The blocks [part] (already cut out of a draft, no boundary block) as
/// clipboard text, with the definitions [defs] of the custom blocks it
/// uses. Null when [part] has no block.
String? clipTextFor(FlowDraft part, Map<String, BlockDef> defs) {
  if (part.blocks.isEmpty) {
    return null;
  }
  return jsonEncode({
    'format': clipFormat,
    'nodes': nodesJsonOf(part),
    'edges': edgesJsonOf(part),
    'layout': layoutJsonOf(part),
    if (defs.isNotEmpty) 'blocks': blockDefsJsonOf(defs.lock),
  });
}

/// The custom blocks a clip brought (its `blocks`, decoded with it).
Map<String, BlockDef> clipBlocksOf(FlowDraft clip) => clip.defs.unlock;
