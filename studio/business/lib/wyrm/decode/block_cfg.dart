import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_block.dart';

/// The config keys of a flow node that the editor itself reads or tests
/// for (spec 06, docs/flow-blocks.md). Any other key is a parameter the
/// catalog describes, edited by name.
enum BlockCfgKey {
  key('key'),
  keyScope('key_scope'),
  pathScope('path_scope'),
  path('path'),
  target('target'),
  node('node'),
  action('action'),
  on('on'),
  args('args'),
  allowBad('allow_bad'),
  operandValues('values'),
  defaults('defaults'),
  descriptions('descriptions'),
  enabled('enabled'),
  inputs('inputs'),
  outputs('outputs'),
  value('value'),
  intervalMs('interval_ms'),
  autoRun('auto_run'),
  runOnStart('run_on_start'),
  timeZone('time_zone'),
  mapping('mapping'),
  aggregates('aggregates'),
  method('method'),
  delimiter('delimiter'),
  withHeader('with_header');

  const BlockCfgKey(this.wire);

  /// The key as the definition writes it.
  final String wire;

  static final Map<String, BlockCfgKey> _byWire = {
    for (final k in values) k.wire: k,
  };

  /// The key named [s]; null for a key the editor does not read itself.
  static BlockCfgKey? fromWire(String s) => _byWire[s];
}

/// The config values a flow node holds that the editor reads, typed.
///
/// A node's config ([FlowBlock.cfg]) stays the JSON of the definition's
/// node (`IMap<String, Object?>`): the inspector edits any parameter the
/// catalog names by its name, and the definition is written back as it
/// came. Typing every block's config is out of scope (studio-rules §8,
/// phase B1): what the editor itself reads — a point's `key` or `path`, a
/// scope, an action, its `args`, the operand constants `values`, the
/// boundary blocks' `inputs`/`outputs`/`defaults`, `enabled` — is read
/// here, and only here.
extension BlockCfg on FlowBlock {
  /// The text of [k]; null when it is no text.
  String? cfgText(BlockCfgKey k) => switch (cfg[k.wire]) {
    final String s => s,
    _ => null,
  };

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
  String? textOf(String name) => switch (cfg[name]) {
    final String s => s,
    _ => null,
  };

  /// `args` of an `invoke`, by argument name; empty when it has none.
  Map<String, Object?> get cfgArgs => _entries(cfg[BlockCfgKey.args.wire]);

  /// Whether `args` is a map at all (an `invoke` with no arguments yet).
  bool get hasArgs => cfg[BlockCfgKey.args.wire] is Map;

  /// `values`: the operand constants, by port (ADR 0038 §7).
  Map<String, Object?> get cfgValues => operandValuesIn(cfg);

  /// `defaults` of a boundary block: an input's default, by its name.
  Map<String, Object?> get cfgDefaults =>
      _entries(cfg[BlockCfgKey.defaults.wire]);

  /// `descriptions` of a boundary block: a port's note, by its name.
  Map<String, Object?> get cfgDescriptions =>
      _entries(cfg[BlockCfgKey.descriptions.wire]);

  /// `enabled`; null when the config does not say.
  bool? get cfgEnabled => switch (cfg[BlockCfgKey.enabled.wire]) {
    final bool b => b,
    _ => null,
  };

  /// The names a list parameter holds (`inputs` of `add`, a boundary
  /// block's `inputs`/`outputs`): its non-empty texts in order; null when
  /// [param] is no list.
  List<String>? namesOf(String param) => _names(cfg[param]);

  /// The keys of a map parameter (`args` of `invoke`, ADR 0040 §2), else
  /// the names of a list one; null when it is neither.
  List<String>? portNamesOf(String param) => switch (cfg[param]) {
    final Map<Object?, Object?> m => [
      for (final k in m.keys)
        if (k is String) k,
    ],
    final v => _names(v),
  };
}

/// The operand constants of a node config [cfg] (`values`), by port.
Map<String, Object?> operandValuesIn(IMap<String, Object?> cfg) =>
    _entries(cfg[BlockCfgKey.operandValues.wire]);

/// The entries of a JSON map with text keys; empty for anything else.
Map<String, Object?> _entries(Object? v) => switch (v) {
  final Map<Object?, Object?> m => {
    for (final e in m.entries)
      if (e.key case final String k) k: e.value,
  },
  _ => const {},
};

List<String>? _names(Object? v) => switch (v) {
  final List<Object?> l => [
    for (final n in l)
      if (n is String && n.isNotEmpty) n,
  ],
  _ => null,
};

// ---------- a config value as the editor shows it ----------

/// A config value (JSON) as the text its editor starts with: nothing for
/// none, a text as itself, a map or a list as indented JSON, anything else
/// as JSON.
String jsonEditText(Object? v) => switch (v) {
  null => '',
  final String s => s,
  Map() || List() => const JsonEncoder.withIndent('  ').convert(v),
  _ => jsonEncode(v),
};

/// What a field shows for a map or a list it holds, in short (`{…}`,
/// `[…]`); null for anything else, an empty one too.
String? jsonShortText(Object? v) => switch (v) {
  Map(isNotEmpty: true) => '{…}',
  List(isNotEmpty: true) => '[…]',
  _ => null,
};

/// The items of a list parameter as rows of texts by key: a text as it
/// is, another value as JSON. A value that is no list of maps gives no
/// rows.
List<Map<String, String>> listRowsIn(Object? v) => [
  if (v case final List<Object?> l)
    for (final item in l)
      if (item case final Map<Object?, Object?> m)
        {
          for (final MapEntry(:key, :value) in m.entries)
            '$key': switch (value) {
              null => '',
              final String s => s,
              _ => jsonEncode(value),
            },
        },
];
