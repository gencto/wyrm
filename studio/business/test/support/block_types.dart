import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_clip.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:models/block_type.dart';
import 'package:models/flow_draft.dart';
import 'package:models/node_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A test catalog keyed by wire name (`types['scale']`) as the editor's
/// lookups take it: by [BlockType].
Map<BlockType, NodeType> byType(Map<String, NodeType> m) => {
  for (final t in m.values) t.type: t,
};

/// The type a definition names [wire].
BlockType bt(String wire) => BlockType.fromWire(wire);

/// A definition the test knows to be good, read ([flowReadOf]).
FlowRead readFlow(String id, Value def) => switch (flowReadOf(id, def)) {
  Valid(:final value) => value,
  final Invalid<FlowRead> i => throw StateError('$i'),
};

/// The draft of a definition the test knows to be good.
FlowDraft flowDraftOf(String id, Value def) => readFlow(id, def).draft;

/// A clipboard text the test knows to be good, read ([clipOf]).
FlowDraft clipped(String? text) => switch (clipOf(text)) {
  Valid(:final value) => value,
  final Invalid<FlowDraft> i => throw StateError('$i'),
};
