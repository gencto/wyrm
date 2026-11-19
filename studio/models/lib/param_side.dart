import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'param_side.freezed.dart';

/// One param of a link on one side of a staged change: its wire [name]
/// and what it holds there: a [text], a [list], or neither (not set).
@freezed
abstract class ParamSide with _$ParamSide {
  const factory ParamSide({
    required String name,
    String? text,
    IList<String>? list,
  }) = _ParamSide;
}
