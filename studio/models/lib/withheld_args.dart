import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'withheld_args.freezed.dart';

/// The arguments of plan step [step] that a saved plan leaves out (secret
/// ones, and every one of a step whose schema is not known), by name.
@freezed
abstract class WithheldArgs with _$WithheldArgs {
  const factory WithheldArgs({
    required int step,
    required IList<String> names,
  }) = _WithheldArgs;
}
