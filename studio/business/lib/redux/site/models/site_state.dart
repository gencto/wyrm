import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/grant.dart';
import 'package:models/site_choice.dart';

part 'site_state.freezed.dart';

@freezed
abstract class SiteState with _$SiteState {
  const factory SiteState({
    String? gateway,
    String? user,
    String? name,
    String? role,
    @Default(false) bool connected,
    String? current,
    @Default(IListConst([])) IList<Grant> grants,
    @Default(IListConst([])) IList<SiteChoice> choices,
    String? max,
  }) = _SiteState;
}
