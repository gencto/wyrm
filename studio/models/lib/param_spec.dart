import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'param_spec.freezed.dart';

@freezed
abstract class ParamSpec with _$ParamSpec {
  /// One parameter of an action or of a link's `cfg` (spec 02).
  const factory ParamSpec({
    required String name,
    String? display,

    /// TypeCode name (`string`, `number`, `int`, `bool`, `enum`, …).
    @Default('string') String type,
    @Default(false) bool required,
    Object? defaultValue,
    num? min,
    num? max,
    @Default(IListConst([])) IList<String> choices,

    /// `file`, `textarea`, …
    String? editor,
    @Default(false) bool secret,
    String? description,

    /// The input port that feeds it (`in.<name>`, ADR 0038 §2); null when
    /// the catalog does not say or it has none.
    String? port,

    /// Whether it repeats as an output named like it (ADR 0038 §1); null
    /// when the catalog does not say.
    bool? echo,
  }) = _ParamSpec;
}
