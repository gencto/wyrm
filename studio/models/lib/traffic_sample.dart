import 'package:freezed_annotation/freezed_annotation.dart';

import 'traffic_measure.dart';

part 'traffic_sample.freezed.dart';

/// The router's network rates at one metrics interval
/// (`sys/{messages,frames,data}_{in,out}_per_second`), kept by Studio: the
/// broker keeps no history of them.
@freezed
abstract class TrafficSample with _$TrafficSample {
  const factory TrafficSample({
    required DateTime time,
    @Default(0) double messagesIn,
    @Default(0) double messagesOut,
    @Default(0) double framesIn,
    @Default(0) double framesOut,

    /// Bytes per second.
    @Default(0) double dataIn,
    @Default(0) double dataOut,
  }) = _TrafficSample;

  const TrafficSample._();

  /// The rate of [measure], into the router or out of it.
  double rate(TrafficMeasure measure, {required bool inward}) =>
      switch (measure) {
        TrafficMeasure.messages => inward ? messagesIn : messagesOut,
        TrafficMeasure.frames => inward ? framesIn : framesOut,
        TrafficMeasure.bytes => inward ? dataIn : dataOut,
      };
}
