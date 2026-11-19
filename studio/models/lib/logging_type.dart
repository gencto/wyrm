import 'package:wyrm_core/wyrm_core.dart';

/// What a watch group of the historian records (`logging_type` of
/// `sys/history/<group>`; `Logging` of `wyrm-history`, by the names the
/// broker lists, shows and takes).
enum LoggingType implements WireName {
  /// Nothing: the group is paused.
  none('None'),

  /// The last value of each point every interval, changed or not.
  interval('Interval'),

  /// Every update.
  allData('All Data'),

  /// Updates whose value or quality differ from the last one recorded.
  pointChange('Point Change');

  const LoggingType(this.wire);

  @override
  final String wire;

  static LoggingType? fromWire(String wire) =>
      values.where((l) => l.wire == wire).firstOrNull;
}
