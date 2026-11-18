import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart' hide JsonValue;
import 'package:wyrm_core/wyrm_core.dart';

import 'block_cfg_key.dart';
import 'json_value.dart';

part 'param_spec.freezed.dart';

@freezed
abstract class ParamSpec with _$ParamSpec {
  /// One parameter of an action or of a link's `cfg` (spec 02).
  const factory ParamSpec({
    required String name,
    String? display,

    /// Its type (spec 02 `TypeCode`); a parameter with choices is
    /// [TypeCode.enum_].
    @Default(TypeCode.string) TypeCode type,
    @Default(false) bool required,

    /// Its default, as the JSON the catalog or the meta gives; null when
    /// it has none.
    JsonValue? defaultValue,
    num? min,
    num? max,
    @Default(IListConst([])) IList<String> choices,

    /// How a form edits it (spec 02 `editor`); null for none, for a
    /// secret (`secret` says it) and for an editor this Studio does not
    /// know (a UI ignores those, spec 02).
    ParamEditor? editor,
    @Default(false) bool secret,
    String? description,

    /// The input port that feeds it (`in.<name>`, ADR 0038 §2); null when
    /// the catalog does not say or it has none.
    String? port,

    /// Whether it repeats as an output named like it (ADR 0038 §1); null
    /// when the catalog does not say.
    bool? echo,

    /// The parameter that holds this field's scope (catalog
    /// `params[].scope`, ADR 0040 §1: `key` → `key_scope`): a key from the
    /// field's port is read only inside it.
    String? scope,

    /// The config key the flow editor knows this parameter as, decoded
    /// from [name] with the catalog (`dataflows` ▸ `node_types`); null for
    /// any other parameter, and for a parameter that is no flow node's.
    BlockCfgKey? key,

    /// Its [description] is a warning to confirm before it is turned on
    /// (the catalog writes it as `WARNING: …`: `run_on_start`, ADR 0040
    /// §2), decoded with the catalog.
    @Default(false) bool warns,
  }) = _ParamSpec;
}
