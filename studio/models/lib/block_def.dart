import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'block_type.dart';
import 'engine_port.dart';
import 'flow_draft.dart';
import 'port_end.dart';

part 'block_def.freezed.dart';

/// One declared input or output of a custom block (spec 06 0.2.24, ADR
/// 0040 §3): `{name, to | from, default?, description?}`.
@freezed
abstract class BlockPort with _$BlockPort {
  const factory BlockPort(
    String name, {

    /// An input: the inner inputs it feeds (`to`); an output: the one inner
    /// output it sends (`from`).
    @Default([]) List<PortEnd> ends,

    /// An input's default, as JSON; null for none.
    Object? defaultValue,
    String? description,

    /// The definition wrote the input's `to` as one text, not a list (the
    /// spec takes both): written back the same way.
    @Default(false) bool oneEnd,

    /// The keys of the port the editor does not read, as JSON, kept for
    /// the write back (the block's own are [BlockDef.extra]).
    @Default(IMapConst({})) IMap<String, Object?> extra,
  }) = _BlockPort;

  const BlockPort._();

  /// Its name as an engine port the editor treats in its own way (a
  /// custom block's `in`, `out`, `error`, `trigger`), read here as a
  /// catalog's are; null for any other name.
  EnginePort? get known => EnginePort.fromWire(name);
}

/// A custom block's definition (`blocks.<name>` of a flow, a library's
/// `def`), decoded: its ports, its inside, where its inside draws the
/// boundary blocks, and the library version it was copied at.
@freezed
abstract class BlockDef with _$BlockDef {
  const factory BlockDef({
    /// Its nodes, edges and layout, read as a flow's (an id-less draft).
    required FlowDraft body,
    String? description,
    @Default([]) List<BlockPort> inputs,
    @Default([]) List<BlockPort> outputs,

    /// The library version it was copied at; null for a block made in the
    /// flow.
    int? libraryVersion,

    /// Where its inside draws the inputs block and the outputs block.
    (double, double)? inputsAt,
    (double, double)? outputsAt,

    /// The nodes of [body] its `layout` gave a place, when it was read; the
    /// others stand where the editor put them, and only a placed one is
    /// written back with its place. Null: every node is placed (a block
    /// made or edited in the editor).
    ISet<String>? placed,

    /// The definition came with a `layout` (the spec lets it go without):
    /// written back with one even when it has no entry. A block made in
    /// the editor has one.
    @Default(true) bool hasLayout,

    /// The keys of the definition the editor does not read, as JSON, kept
    /// for the write back.
    @Default(IMapConst({})) IMap<String, Object?> extra,
  }) = _BlockDef;

  const BlockDef._();

  /// The custom blocks its nodes are instances of, by name.
  Set<String> get uses => {
    for (final b in body.blocks.values)
      if (b.type case CustomType(:final name)) name,
  };

  /// How many of its nodes are instances of [type].
  int instances(CustomType type) =>
      body.blocks.values.where((b) => b.type == type).length;
}
