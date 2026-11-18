import 'package:freezed_annotation/freezed_annotation.dart';

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

  /// The revision [rev] of a link's params, with what of it changes
  /// ([detail]: param names and their values, data); empty for all of it.
  const factory ChangeSide.rev(int rev, {@Default('') String detail}) =
      ChangeSideRev;

  /// A switch: on or off.
  const factory ChangeSide.flag({required bool on}) = ChangeSideFlag;

  /// A JSON object of [count] top-level keys.
  const factory ChangeSide.keys(int count) = ChangeSideKeys;
}
