import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/view_check.dart';
import 'package:models/view_place.dart';

part 'views_state.freezed.dart';

@freezed
abstract class ViewsState with _$ViewsState {
  const factory ViewsState({
    @Default('demo-plant') String sample,
    @Default('') String source,
    @Default('') String refine,
    @Default(IMapConst({})) IMap<String, String> docs,
    @Default(IMapConst({})) IMap<String, Object> catalog,
    @Default('desktop') String width,
    String? density,
    @Default('checks') String tab,
    @Default(false) bool project,
    @Default(IListConst([])) IList<ViewPlace> stack,
    @Default(IMapConst({})) IMap<String, Object> data,
    @Default(IMapConst({})) IMap<String, IList<String>> children,
    @Default(IListConst([])) IList<ViewCheck> checks,
    String? result,
    @Default(false) bool open,
    @Default(IMapConst({})) IMap<String, String> keys,
    @Default(IMapConst({})) IMap<String, String> alarms,
    @Default(IListConst([])) IList<(String, String)> grants,
    @Default('') String draft,
  }) = _ViewsState;
}
