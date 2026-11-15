import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/user_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The device record of ADR 0050 §1.5 as the gateway sends it, decoded once.
void main() {
  Value record(Map<String, Object?> m) => Value.from(m);

  test('a record decodes with its platform and state as enums', () {
    final d = userDeviceOf(
      GatewayDevice.of(
        record({
          'id': 'd1',
          'name': 'MacBook · Studio',
          'platform': 'macos',
          'added': 100,
          'last_used': 200,
          'password_due_at': 300,
          'state': 'signed_out',
          'this': true,
          'removed_by': 'user:admin',
        }),
      ),
    );
    expect(
      d,
      const Valid(
        UserDevice(
          id: 'd1',
          name: 'MacBook · Studio',
          platform: DevicePlatform.macos,
          added: 100,
          lastUsed: 200,
          passwordDueAt: 300,
          state: DeviceRecordState.signedOut,
          thisDevice: true,
          removedBy: 'admin',
        ),
      ),
    );
  });

  test('every wire name of the two sets reads back as itself', () {
    for (final p in DevicePlatform.values) {
      expect(DevicePlatform.fromWire(p.wire), p);
    }
    for (final s in DeviceRecordState.values) {
      expect(DeviceRecordState.fromWire(s.wire), s);
    }
    // the bug of 2026-11-15: the gateway's name is `macos`, never `mac`
    expect(DevicePlatform.fromWire('mac'), isNull);
    expect(DevicePlatform.macos.wire, 'macos');
  });

  test('an unknown platform is null, an unknown state is active', () {
    final d = userDeviceOf(
      GatewayDevice.of(
        record({'id': 'd1', 'name': 'x', 'platform': 'beos', 'state': '?'}),
      ),
    ).valueOrNull!;
    expect(d.platform, isNull);
    expect(d.state, DeviceRecordState.active);
  });

  test('a record with no id is invalid, and a list leaves it out', () {
    final bad = GatewayDevice.of(record({'name': 'x'}));
    expect(
      userDeviceOf(bad),
      const Invalid<UserDevice>('device record', 'id', 'missing'),
    );
    final good = GatewayDevice.of(record({'id': 'a', 'name': 'a'}));
    expect(userDevicesOf([bad, good]).map((d) => d.id), ['a']);
  });

  test('a list is newest use first', () {
    final ds = [
      GatewayDevice.of(record({'id': 'old', 'name': '', 'last_used': 1})),
      GatewayDevice.of(record({'id': 'new', 'name': '', 'last_used': 9})),
    ];
    expect(userDevicesOf(ds).map((d) => d.id), ['new', 'old']);
  });
}
