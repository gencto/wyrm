import 'package:freezed_annotation/freezed_annotation.dart';

part 'site_state.freezed.dart';

@freezed
abstract class SiteState with _$SiteState {
  const factory SiteState({
    String? gateway,
    String? user,
    String? name,
    String? role,
    @Default(false) bool connected,
  }) = _SiteState;
}
