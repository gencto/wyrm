import 'package:app/common/trend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/hist_window.dart';

/// The connector's side of the trend (spec trend.md §4): where the range
/// ends, when the window's finer rows are drawn, how a chosen window is
/// kept.
void main() {
  const minute = 60 * 1000000;
  final t0 = DateTime.utc(2026, 11, 12, 12);

  test('a window that follows now, read after the range, is drawn', () {
    // The range read at T0; the window (last hour) read 10 min later, no
    // live sample since.
    final read = t0.add(const Duration(minutes: 10));
    final w = const HistWindow(span: Duration(hours: 1)).at(read);
    final end = trendRangeEnd(t0, [
      t0.subtract(const Duration(minutes: 3)),
      w.$2,
    ]);
    final start = end - 60 * minute;
    expect(
      detailCovers(
        from: w.$1.microsecondsSinceEpoch,
        to: w.$2.microsecondsSinceEpoch,
        start: start,
        end: end,
        follows: true,
      ),
      isTrue,
    );
  });

  test('rows of another window are not drawn', () {
    final e = t0.microsecondsSinceEpoch;
    expect(
      detailCovers(
        from: e - 120 * minute,
        to: e - 60 * minute,
        start: e - 30 * minute,
        end: e,
        follows: false,
      ),
      isFalse,
    );
  });

  test('the range ends at the latest read or row', () {
    final later = t0.add(const Duration(seconds: 5));
    expect(trendRangeEnd(t0, [null, later]), later.microsecondsSinceEpoch);
    expect(trendRangeEnd(t0, []), t0.microsecondsSinceEpoch);
  });

  test('a chosen window: whole range, following, fixed', () {
    final e = t0.microsecondsSinceEpoch;
    final s = e - 24 * 60 * minute;
    expect(trendWindow(s, e, s, e), isNull);
    expect(
      trendWindow(e - 60 * minute, e, s, e),
      const HistWindow(span: Duration(hours: 1)),
    );
    expect(trendWindow(s, e - minute, s, e)!.end, isNotNull);
  });

  test('decimals: precision as text, else from the values', () {
    expect(trendDecimals(const [], precision: '2'), 2);
    expect(trendDecimals(const []), 0);
  });
}
