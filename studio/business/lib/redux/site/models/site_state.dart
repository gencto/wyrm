import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/grant.dart';
import 'package:models/site_choice.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../../../wyrm/session.dart';

part 'site_state.freezed.dart';

@freezed
abstract class SiteState with _$SiteState {
  const factory SiteState({
    GatewayAddress? gateway,
    String? user,
    String? name,
    String? role,
    @Default(false) bool connected,
    String? current,
    @Default(IListConst([])) IList<Grant> grants,
    @Default(IListConst([])) IList<SiteChoice> choices,

    /// The highest level the session may use (`/api/me` `max`), set with
    /// [grants] at log-in; null while `/api/me` is not read, and then no
    /// grant gives any right (the cap is closed).
    Perm? max,
  }) = _SiteState;
}
