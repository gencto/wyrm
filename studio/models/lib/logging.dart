import 'package:freezed_annotation/freezed_annotation.dart';

import 'logging_type.dart';

part 'logging.freezed.dart';

/// What a watch group records, as the broker says it (`logging_type`).
/// It is shown only: a name this Studio does not know is kept as the
/// broker wrote it and shown as such, and the group stays whole.
@freezed
sealed class Logging with _$Logging {
  /// One of the ways this Studio knows.
  const factory Logging.known(LoggingType type) = LoggingKnown;

  /// A way of recording this Studio does not know, by the broker's name.
  const factory Logging.other(String name) = LoggingOther;
}
