import 'package:business/common/memo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a memo keeps its result while every input is the same object', () {
    final memo = Memo<List<int>>();
    var runs = 0;
    final a = [1, 2];
    final b = <String, int>{'x': 1};
    List<int> of(List<Object?> inputs) => memo.of(inputs, () {
      runs++;
      return [runs];
    });

    final first = of([a, b, 3]);
    expect(runs, 1);
    expect(identical(of([a, b, 3]), first), isTrue);
    expect(runs, 1);

    // An equal input that is another object: computed again.
    of([
      [1, 2],
      b,
      3,
    ]);
    expect(runs, 2);
    // Another count of inputs, another value: computed again.
    of([a, b]);
    expect(runs, 3);
    of([a, b, 4]);
    expect(runs, 4);
    // Null is an input as any other.
    final n = of([null]);
    expect(identical(of([null]), n), isTrue);
    expect(runs, 5);
  });
}
