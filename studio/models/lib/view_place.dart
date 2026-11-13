import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'view_place.freezed.dart';

/// One entry of a view project's back stack: a page and the values of its
/// parameters (full keys).
@freezed
abstract class ViewPlace with _$ViewPlace {
  const factory ViewPlace({
    required String page,
    @Default(IMapConst({})) IMap<String, String> params,
  }) = _ViewPlace;
}
