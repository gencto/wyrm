import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/json_value.dart';

/// A flow node's config (`FlowBlock.cfg`: spec 06 `nodes.<id>` without
/// `type`, as `wyrm-flow` `NodeDef` takes it) decoded: each field as the
/// [JsonValue] it holds, in the config's order.
///
/// The config stays the JSON of the definition (it is written back as it
/// came), and every reader of the editor reads it through this one
/// decoder: once per config, since an edit makes a new one and the same
/// config is the same instance. A config holds JSON only: the definition's
/// decoder refuses anything else (`flowReadOf`), and an edit writes the
/// `raw` of a decoded value.
IMap<String, JsonValue> blockConfigOf(IMap<String, Object?> cfg) =>
    _configs[cfg] ??= {
      for (final MapEntry(:key, :value) in cfg.entries)
        key: JsonValue.of(value),
    }.lock;

final _configs = Expando<IMap<String, JsonValue>>('block configs');
