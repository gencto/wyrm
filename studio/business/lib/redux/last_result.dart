/// The last result of a selector and the inputs it was computed from,
/// compared by identity (studio-rules §9: work done in `fromStore` is
/// redone on every dispatch). The inputs are immutable state (an `IMap`,
/// a stored `String`): a new instance is a change, the same one is not, so an
/// unchanged state is not decoded again.
final class LastResult<R> {
  List<Object?>? _inputs;
  R? _value;

  /// The value for [inputs]: the last one when every input is the very
  /// object it was, else [compute] run again.
  R of(List<Object?> inputs, R Function() compute) {
    final last = _inputs;
    if (last != null && last.length == inputs.length) {
      var same = true;
      for (var i = 0; i < inputs.length && same; i++) {
        same = identical(last[i], inputs[i]);
      }
      if (same) {
        return _value as R;
      }
    }
    final value = compute();
    _inputs = inputs;
    _value = value;
    return value;
  }
}
