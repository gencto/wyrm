import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spec 06: `permissions.maxperm` is a code (`0 none … 3 write`) or a name.
/// The flow editor cast it to a string, and a flow deployed with a code (a
/// tool, the agent) broke the editor's view-model ("type 'int' is not a
/// subtype of type 'String?'").
void main() {
  test('a code and a name give the same level', () {
    expect(maxpermName(3), 'write');
    expect(maxpermName('write'), 'write');
    expect(maxpermName(2), 'read');
  });

  test('anything else is none, not a fault', () {
    expect(maxpermName(null), isNull);
    expect(maxpermName(99), isNull);
    expect(maxpermName(const ['write']), isNull);
  });
}
