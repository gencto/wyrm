import 'package:models/staged_change_kind.dart';
import 'package:test/test.dart';

/// The ids of the staged table: one kind and the full key, built in one
/// place (the table and the tests that read it keep their old texts).
void main() {
  test('a change id is its kind and its full key', () {
    expect(
      StagedChangeKind.set.idOf('wy/plant/sys/enable_quarantine'),
      'set:wy/plant/sys/enable_quarantine',
    );
    expect(
      StagedChangeKind.params.idOf('wy/plant/sys/links/modbus'),
      'params:wy/plant/sys/links/modbus',
    );
  });
}
