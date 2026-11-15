import 'sys_value.dart';

/// What System's *Router traffic* card draws: the router's messages, its
/// frames, or its bytes per second (`sys/<measure>_{in,out}_per_second`).
enum TrafficMeasure {
  messages('messages'),
  frames('frames'),
  bytes('data');

  const TrafficMeasure(this.key);

  /// The middle of its `sys` keys: `data` for bytes
  /// (`data_in_per_second`).
  final String key;

  /// The rate into the router.
  SysValue get inward => switch (this) {
    messages => SysValue.messagesIn,
    frames => SysValue.framesIn,
    bytes => SysValue.dataIn,
  };

  /// The rate out of the router.
  SysValue get outward => switch (this) {
    messages => SysValue.messagesOut,
    frames => SysValue.framesOut,
    bytes => SysValue.dataOut,
  };
}
