import 'package:business/wyrm/log_in_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gateway field is one text, `main, standby` (ADR 0036), shown as two
/// fields: emptying one keeps the other in its place.
void main() {
  const main = 'https://plant.local:8446';
  const standby = 'https://edge.local:8446';
  final both = GatewayField.of('$main, $standby');

  test('a new main or standby replaces only its own part', () {
    expect(
      both.withMain('https://lab.local:8446'),
      'https://lab.local:8446, $standby',
    );
    expect(
      both.withStandby('https://b.local:8446'),
      '$main, https://b.local:8446',
    );
  });

  test('an empty main beside a standby: the standby stays the standby', () {
    final f = GatewayField.of(both.withMain(null));
    expect(f.main, isEmpty);
    expect(f.standby, standby);
  });

  test('an empty standby: the main alone', () {
    expect(both.withStandby(null), main);
    expect(GatewayField.of(main).withMain(null), isEmpty);
  });

  test('a standby typed while the main is empty stays the standby', () {
    final f = GatewayField.of(GatewayField.of('').withStandby(standby));
    expect(f.main, isEmpty);
    expect(f.standby, standby);
  });
}
