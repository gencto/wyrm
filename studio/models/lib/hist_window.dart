import 'package:freezed_annotation/freezed_annotation.dart';

part 'hist_window.freezed.dart';

/// The window a trend shows inside its range (spec trend.md §4): [span]
/// wide, ending at [end], or at now while [end] is null (it follows new
/// samples). No window at all is the whole range.
@freezed
abstract class HistWindow with _$HistWindow {
  const factory HistWindow({
    required Duration span,

    /// The right edge; null follows now.
    DateTime? end,
  }) = _HistWindow;

  const HistWindow._();

  /// The window's edges at [now].
  (DateTime, DateTime) at(DateTime now) {
    final e = end ?? now;
    return (e.subtract(span), e);
  }
}
