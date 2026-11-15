import 'package:models/block_type.dart';
import 'package:models/node_type.dart';

/// A test catalog keyed by wire name (`types['scale']`) as the editor's
/// lookups take it: by [BlockType].
Map<BlockType, NodeType> byType(Map<String, NodeType> m) => {
  for (final t in m.values) t.type: t,
};

/// The type a definition names [wire].
BlockType bt(String wire) => BlockType.fromWire(wire);
