import 'package:business/wyrm/device_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/device_tag.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// A device record as a row of Account › Security: what is computed from
/// the record and the clock (studio-rules §3: in business, not a mapper).
void main() {
  final now = DateTime(2026, 11, 15, 12);
  int s(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
  GatewayDevice dev({
    String id = 'd',
    GatewayDeviceState state = GatewayDeviceState.active,
    bool thisSession = false,
    int lastUsed = 0,
    int passwordDueAt = 0,
    String? removedBy,
  }) => GatewayDevice(
    id: id,
    name: id,
    platform: DevicePlatform.macos,
    state: state,
    thisSession: thisSession,
    lastUsed: lastUsed,
    passwordDueAt: passwordDueAt,
    removedBy: removedBy,
  );

  test('removed wins over own; own over signed out and due', () {
    final removed = deviceRowOf(
      dev(state: GatewayDeviceState.removed, thisSession: true),
      null,
      now,
    );
    expect(removed.tag, DeviceTag.removed);
    expect(removed.own, isTrue);
    expect(deviceRowOf(dev(id: 'me'), 'me', now).tag, DeviceTag.thisDevice);
    expect(
      deviceRowOf(dev(state: GatewayDeviceState.signedOut), null, now).tag,
      DeviceTag.signedOut,
    );
  });

  test('a password due within a week is tagged with its days, rounded up', () {
    final soon = deviceRowOf(
      dev(passwordDueAt: s(now.add(const Duration(days: 3, hours: 12)))),
      null,
      now,
    );
    expect(soon.tag, DeviceTag.passwordDue);
    expect(soon.dueDays, 4);
    final late = deviceRowOf(
      dev(passwordDueAt: s(now.add(const Duration(days: 9)))),
      null,
      now,
    );
    expect(late.tag, isNull);
    final past = deviceRowOf(
      dev(passwordDueAt: s(now.subtract(const Duration(days: 1)))),
      null,
      now,
    );
    expect(past.dueDays, 0);
  });

  test('used now only on the own row and within a minute', () {
    final recent = s(now.subtract(const Duration(seconds: 20)));
    expect(
      deviceRowOf(dev(thisSession: true, lastUsed: recent), null, now).usedNow,
      isTrue,
    );
    expect(deviceRowOf(dev(lastUsed: recent), null, now).usedNow, isFalse);
    final old = s(now.subtract(const Duration(minutes: 2)));
    expect(
      deviceRowOf(dev(thisSession: true, lastUsed: old), null, now).usedNow,
      isFalse,
    );
  });

  test('the user who removed it, without the subject prefix; 0 is no time', () {
    final r = deviceRowOf(dev(removedBy: 'user:ivan'), null, now);
    expect(r.removedBy, 'ivan');
    expect(r.lastUsed, isNull);
    expect(r.added, isNull);
  });
}
