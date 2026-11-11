import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/hist_point.dart';
import 'package:models/watch_group.dart';

part 'historian_state.freezed.dart';

@freezed
abstract class HistorianState with _$HistorianState {
  const factory HistorianState({
    @Default(IListConst([])) IList<WatchGroup> groups,
    String? selected,
    @Default('24h') String range,
    @Default(IMapConst({})) IMap<String, IList<HistPoint>> series,
    @Default(IMapConst({})) IMap<String, String> stats,
    @Default(IListConst([])) IList<String> points,
  }) = _HistorianState;
}
