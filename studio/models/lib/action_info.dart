import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart' show Perm;

import 'param_spec.dart';

part 'action_info.freezed.dart';

/// One action of a node (`~meta` `actions`, spec 02).
@freezed
abstract class ActionInfo with _$ActionInfo {
  const factory ActionInfo({
    required String name,

    /// The level a call needs (the action's own, else the node's
    /// `invokable`; an action with neither is not callable and is no
    /// [ActionInfo]).
    required Perm level,
    String? display,

    /// The menu group (`edit`, `secrets`, `Install Link`).
    String? group,
    @Default(IListConst([])) IList<ParamSpec> params,

    /// `stream`, `void`, or a type name.
    String? result,
  }) = _ActionInfo;

  const ActionInfo._();

  /// A `config` action changes how the network runs: it is staged for
  /// Review and apply, not run at once.
  bool get staged => level == Perm.config;
}
