import 'package:business/wyrm/labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a human reads for a name the broker uses (owner 2026-11-11).
void main() {
  test('a name reads in sentence case, a unit suffix in brackets', () {
    expect(humanize('a_ab'), 'A ab');
    expect(humanize('add_watch_path'), 'Add watch path');
    expect(humanize('edit'), 'Edit');
    expect(humanize('poll_s'), 'Poll (s)');
  });

  test("the meta's display wins; an empty one does not", () {
    expect(
      labelOf('add_watch_path', display: 'Add Watch Path'),
      'Add Watch Path',
    );
    expect(labelOf('add_watch_path', display: ' '), 'Add watch path');
    expect(labelOf('add_watch_path'), 'Add watch path');
  });

  test('a snake_case choice reads as words, any other stays as it is', () {
    expect(choiceLabel('read_back'), 'Read back');
    expect(choiceLabel('a_ab'), 'A ab');
    for (final raw in [
      'holding',
      'f32',
      '1m',
      'All Data',
      'pkg:modbus',
      'wy/edge/downstream',
      'portable-echo',
      'f32_wbswap',
    ]) {
      expect(choiceLabel(raw), raw, reason: raw);
    }
    expect(choiceLabels(['holding', 'read_back']), {'read_back': 'Read back'});
  });
}
