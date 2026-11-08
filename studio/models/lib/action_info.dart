import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'param_spec.dart';

part 'action_info.freezed.dart';

/// One action of a node (`~meta` `actions`, spec 02).
@freezed
abstract class ActionInfo with _$ActionInfo {
  const factory ActionInfo({
    required String name,
    String? display,

    /// The menu group (`edit`, `secrets`, `Install Link`).
    String? group,

    /// `read`, `write` or `config`.
    @Default('write') String level,
    @Default(IListConst([])) IList<ParamSpec> params,

    /// `stream`, `void`, or a type name.
    String? result,
  }) = _ActionInfo;
}
