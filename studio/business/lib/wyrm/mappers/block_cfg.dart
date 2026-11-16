import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_cfg_key.dart';
import 'package:models/flow_block.dart';
import 'package:models/json_value.dart';

export 'package:models/block_cfg_key.dart';

/// What a flow node's config holds, read through its typed JSON
/// ([JsonValue]).
///
/// A node's config ([FlowBlock.cfg]) stays the JSON of the definition's
/// node: the inspector edits any parameter the catalog names by its name,
/// and the definition is written back as it came. This is the one place
/// it is read: the keys the editor itself reads ([BlockCfgKey]: a point's
/// `key` or `path`, a scope, an action, its `args`, the operand constants
/// `values`, the boundary blocks' `inputs`/`outputs`/`defaults`,
/// `enabled`) as typed values, and a catalog parameter by its name
/// ([param], [hasParam]) as the JSON value its editor shows.
extension BlockCfg on FlowBlock {
  /// The value of the catalog parameter [name] as the config holds it;
  /// null when it holds none.
  Object? param(String name) => cfg[name];

  /// Whether the config holds a value for the parameter [name].
  bool hasParam(String name) => cfg[name] != null;

  /// The text of [k]; null when it is no text.
  String? cfgText(BlockCfgKey k) => textOf(k.wire);

  /// `key`: the point a reader names.
  String? get cfgKey => cfgText(BlockCfgKey.key);

  /// `path`: the point or node a writer or a reader names.
  String? get cfgPath => cfgText(BlockCfgKey.path);

  /// `target`: what an older sink names.
  String? get cfgTarget => cfgText(BlockCfgKey.target);

  /// `node`: the value a `publish` writes.
  String? get cfgNode => cfgText(BlockCfgKey.node);

  /// `action`: the action an `invoke` runs.
  String? get cfgAction => cfgText(BlockCfgKey.action);

  /// The scope of a key from a port (`key_scope`, else `path_scope`, ADR
  /// 0040 §1); null when neither is a text.
  String? get cfgScope =>
      cfgText(BlockCfgKey.keyScope) ?? cfgText(BlockCfgKey.pathScope);

  /// The text of the parameter [name] (a scope the catalog names); null
  /// when it is no text.
  String? textOf(String name) => switch (JsonValue.of(cfg[name])) {
    JsonText(:final text) => text,
    _ => null,
  };

  /// `args` of an `invoke`, by argument name; empty when it has none.
  Map<String, Object?> get cfgArgs => _entries(cfg[BlockCfgKey.args.wire]);

  /// Whether `args` is a map at all (an `invoke` with no arguments yet).
  bool get hasArgs => JsonValue.of(cfg[BlockCfgKey.args.wire]) is JsonMap;

  /// `values`: the operand constants, by port (ADR 0038 §7).
  Map<String, Object?> get cfgValues => operandValuesIn(cfg);

  /// `defaults` of a boundary block: an input's default, by its name.
  Map<String, Object?> get cfgDefaults =>
      _entries(cfg[BlockCfgKey.defaults.wire]);

  /// `descriptions` of a boundary block: a port's note, by its name.
  Map<String, Object?> get cfgDescriptions =>
      _entries(cfg[BlockCfgKey.descriptions.wire]);

  /// `enabled`; null when the config does not say.
  bool? get cfgEnabled => switch (JsonValue.of(
    cfg[BlockCfgKey.enabled.wire],
  )) {
    JsonBool(:final value) => value,
    _ => null,
  };

  /// The names a list parameter holds (`inputs` of `add`, a boundary
  /// block's `inputs`/`outputs`): its non-empty texts in order; null when
  /// [param] is no list.
  List<String>? namesOf(String param) => switch (JsonValue.of(cfg[param])) {
    final JsonList l => l.names,
    _ => null,
  };

  /// The keys of a map parameter (`args` of `invoke`, ADR 0040 §2), else
  /// the names of a list one; null when it is neither.
  List<String>? portNamesOf(String param) => switch (JsonValue.of(
    cfg[param],
  )) {
    JsonMap(:final fields) => fields.keys.toList(),
    final JsonList l => l.names,
    _ => null,
  };
}

/// The operand constants of a node config [cfg] (`values`), by port.
Map<String, Object?> operandValuesIn(IMap<String, Object?> cfg) =>
    _entries(cfg[BlockCfgKey.operandValues.wire]);

/// The entries of a JSON map; empty for anything else.
Map<String, Object?> _entries(Object? v) => switch (JsonValue.of(v)) {
  final JsonMap m => m.entries,
  _ => const {},
};
