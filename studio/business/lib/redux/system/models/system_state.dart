import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/log_line.dart';
import 'package:models/profile_info.dart';
import 'package:models/traffic_sample.dart';

part 'system_state.freezed.dart';

@freezed
abstract class SystemState with _$SystemState {
  const factory SystemState({
    @Default(IListConst([])) IList<LogLine> log,
    String? logLevel,
    String? filter,
    @Default('overview') String tab,
    @Default('messages') String measure,
    String? source,
    @Default(200) int lines,
    @Default(true) bool auto,
    @Default(false) bool shown,
    String? logError,
    @Default(IListConst([])) IList<TrafficSample> samples,
    String? trafficRoot,
    @Default(IListConst([])) IList<ProfileInfo> profiles,
    String? profilesNote,
    int? aclSeen,
    @Default(IMapConst({})) IMap<String, String> about,
    @Default(IMapConst({})) IMap<String, String> units,
    String? around,
  }) = _SystemState;
}
