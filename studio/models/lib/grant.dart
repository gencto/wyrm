import 'package:freezed_annotation/freezed_annotation.dart';

part 'grant.freezed.dart';

/// One grant of the logged-in user (`/api/me` `grants: [{k, p}]`): a key
/// pattern and the level it gives.
@freezed
abstract class Grant with _$Grant {
  const factory Grant({
    /// A key or a pattern with `*` and `**` (`wy/**`).
    required String key,

    /// `none`, `list`, `read`, `write` or `config`.
    required String level,
  }) = _Grant;
}
