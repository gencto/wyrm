import 'package:business/wyrm/decode/live_value.dart';
import 'package:business/wyrm/decode/node_detail.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/quality.dart' as m;
import 'package:wyrm_client/wyrm_client.dart';

/// A sample of `subscribe` and a node's full `~meta` (spec 02), decoded
/// once where they arrive (studio-rules §8).
void main() {
  test('a sample: its value as plain Dart, its quality and time', () {
    final v = liveValueOf(
      const Sample(VFloat(21.5), q: Quality.uncertain, t: 1794108760204785),
    );

    expect(v.value, 21.5);
    expect(v.quality, m.Quality.uncertain);
    expect(v.time.microsecondsSinceEpoch, 1794108760204785);
  });

  test('a sample of a map keeps its fields', () {
    final v = liveValueOf(
      Sample(Value.from({'a': 1, 'b': 'x'}), t: 1),
    );

    expect(v.value, {'a': 1, 'b': 'x'});
    expect(v.quality, m.Quality.good);
  });

  test("a meta's cfg and attr as the texts a detail shows", () {
    final d = nodeDetailOf(
      'wy/p/downstream/m/c1',
      NodeMeta(
        cfg: {
          'host': const VStr('10.0.0.5'),
          'port': const VInt(502),
          'scale': const VFloat(2),
          'gain': const VFloat(0.5),
          'on': const VBool(true),
          'none': const VNull(),
          'map': Value.from({'a': 1}),
          'list': Value.from([1, 'x']),
        },
        attr: {'history': const VStr('trend')},
      ),
    );

    expect(
      d.cfg,
      {
        'host': '10.0.0.5',
        'port': '502',
        'scale': '2',
        'gain': '0.5',
        'on': 'true',
        'none': '',
        'map': '{a: 1}',
        'list': '[1, x]',
      }.lock,
    );
    expect(d.attr, {'history': 'trend'}.lock);
    expect(d.hasHistory, isTrue);
  });
}
