/// The span of a point's history Explorer reads, back from now.
enum HistoryRange {
  hour('1h', Duration(hours: 1)),
  day('24h', Duration(hours: 24)),
  week('7d', Duration(days: 7));

  const HistoryRange(this.code, this.span);

  /// Its short name (`1h`), as a sentence about the range writes it.
  final String code;
  final Duration span;
}
