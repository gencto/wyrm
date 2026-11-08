import 'package:freezed_annotation/freezed_annotation.dart';

part 'site_choice.freezed.dart';

/// A site the top-bar switcher offers: the one logged into, the ones below
/// it (`downstream/<d>`, relayed included) and above it (`upstream/<u>`).
@freezed
abstract class SiteChoice with _$SiteChoice {
  const factory SiteChoice({
    required String site,

    /// `this`, `downstream` or `upstream`.
    @Default('this') String relation,

    /// The site it is reached through, when not directly.
    String? via,
  }) = _SiteChoice;
}
