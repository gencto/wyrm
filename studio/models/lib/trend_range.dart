/// The span History's trend shows, back from now (its brush).
enum TrendRange {
  hour(Duration(hours: 1)),
  day(Duration(hours: 24)),
  week(Duration(days: 7)),
  month(Duration(days: 30));

  const TrendRange(this.span);

  final Duration span;
}
