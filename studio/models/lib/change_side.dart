import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'param_side.dart';

part 'change_side.freezed.dart';

/// One side of a staged change as its review card shows it: what was
/// there, or what will be. A value, a name or a list is data (`text`);
/// what Studio says of it in its own words is a case `ui` words.
@freezed
sealed class ChangeSide with _$ChangeSide {
  /// Data as it is: a value, a wire name, a list of them.
  const factory ChangeSide.text(String text) = ChangeSideText;

  /// Nothing to show (`—`).
  const factory ChangeSide.none() = ChangeSideNone;

  /// The revision [rev] of a link's params, all of it.
  const factory ChangeSide.rev(int rev) = ChangeSideRev;

  /// Some params of a link as they are on this side ([values]), of the
  /// revision [rev] when the side is what was there.
  const factory ChangeSide.params(IList<ParamSide> values, {int? rev}) =
      ChangeSideParams;

  /// A switch: on or off.
  const factory ChangeSide.flag({required bool on}) = ChangeSideFlag;

  /// A JSON object of [count] top-level keys.
  const factory ChangeSide.keys(int count) = ChangeSideKeys;
}
