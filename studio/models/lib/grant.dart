import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart' show Perm;

part 'grant.freezed.dart';

/// One grant of the logged-in user (`/api/me` `grants: [{k, p}]`): a key
/// pattern and the level it gives.
@freezed
abstract class Grant with _$Grant {
  const factory Grant({
    /// A key or a pattern with `*` and `**` (`wy/**`).
    required String key,

    /// The level it gives, as `/api/me` decodes it (a name that is no
    /// level refuses the whole answer, `wyrm_client` `GatewayIdentity`).
    required Perm level,
  }) = _Grant;
}
