/// One remembered result: [of] computes it again only when one of its
/// inputs is not the very object it was the last time (`identical`, so a
/// map the store kept is not compared item by item). `fromStore` runs on
/// every dispatch of the app; a view that depends on a few parts of the
/// state keeps its result while those parts stay the same objects.
///
/// A value that is new on every dispatch although it holds the same items
/// (the live values: `SetLiveValuesAction` makes a new map) is not an input;
/// the items read from it are (`[for (final k in keys) values[k]]`).
final class Memo<R> {
  List<Object?>? _inputs;
  R? _result;

  /// The result for [inputs]: the last one when every input is identical
  /// to the last call's, else [compute]'s.
  R of(List<Object?> inputs, R Function() compute) {
    final last = _inputs;
    if (last != null && _same(last, inputs)) {
      return _result as R;
    }
    final r = compute();
    _inputs = List.of(inputs, growable: false);
    _result = r;
    return r;
  }

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
}
