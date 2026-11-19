import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/call_refusal.dart';
import 'package:models/hist_window.dart';
import 'package:models/log_level.dart';
import 'package:models/log_line.dart';
import 'package:models/log_read_error.dart';
import 'package:models/profile_info.dart';
import 'package:models/system_tab.dart';
import 'package:models/traffic_measure.dart';
import 'package:models/traffic_sample.dart';

part 'system_state.freezed.dart';

@freezed
abstract class SystemState with _$SystemState {
  const factory SystemState({
    @Default(IListConst([])) IList<LogLine> log,

    /// The Log toolbar's level (`get_log` `level`); none: the broker's.
    LogLevel? logLevel,
    String? filter,
    @Default(SystemTab.overview) SystemTab tab,
    @Default(TrafficMeasure.messages) TrafficMeasure measure,
    String? source,
    @Default(200) int lines,
    @Default(true) bool auto,
    @Default(false) bool shown,
    LogReadError? logError,
    @Default(IListConst([])) IList<TrafficSample> samples,
    String? trafficRoot,
    @Default(IListConst([])) IList<ProfileInfo> profiles,
    CallRefusal? profilesNote,
    int? aclSeen,
    @Default(IMapConst({})) IMap<String, String> about,
    @Default(IMapConst({})) IMap<String, String> units,
    String? around,
    HistWindow? trafficWindow,
  }) = _SystemState;
}
