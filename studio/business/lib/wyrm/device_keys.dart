import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_key/device_key.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:models/device_policy_info.dart';
import 'package:models/key_kind.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/user_device.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'session.dart';

// What Studio does with the device key of ADR 0050, in one place: the
// platform names, the alias of a key, the signer that turns the OS prompt
// into bytes, and the mapping of the gateway's answers.

/// `mac`, `windows`, `linux`, `ios` or `android`: the platform a device
/// record names and the log-in page draws (unlock-discover.md §1).
String devicePlatform() {
  if (kIsWeb) {
    return 'web';
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS => 'mac',
    TargetPlatform.windows => 'windows',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => 'linux',
  };
}

/// The name a new device record gets: the computer's host name and
/// `Studio` (`MacBook-Pro · Studio`), at most 64 bytes as the gateway takes.
String deviceName() {
  var host = 'Studio';
  try {
    host = Platform.localHostname.replaceFirst(RegExp(r'\.local$'), '');
  } on Object {
    // No host name: the plain word.
  }
  final name = host.isEmpty || host == 'Studio' ? 'Studio' : '$host · Studio';
  return utf8.encode(name).length <= 64 ? name : 'Studio';
}

/// The alias of the key of [user] on the gateway [origin]: one key per
/// gateway, user and device (ADR 0050 §1.8). A hash, so the OS store does
/// not name the gateway or the user.
String keyAlias(String origin, String user) {
  final hash = sha256.convert(utf8.encode('$origin|$user')).toString();
  return 'wyrm-${hash.substring(0, 32)}';
}

/// The state's [KeyKind] for the plugin's.
KeyKind keyKindOf(DeviceKeyKind k) => KeyKind.values.byName(k.name);

/// The gateway's device policy as the state keeps it.
DevicePolicyInfo policyOf(DevicePolicy p) => DevicePolicyInfo(
  enabled: p.enabled,
  maxPerUser: p.maxPerUser,
  passwordEveryDays: p.passwordEveryDays,
  idleLockMaxMin: p.idleLockMaxMin,
  stepUp: p.stepUp,
  allowDeviceCredential: p.allowDeviceCredential,
);

/// A device record as the state keeps it.
UserDevice userDeviceOf(GatewayDevice d) => UserDevice(
  id: d.id,
  name: d.name,
  platform: d.platform,
  added: d.added,
  lastUsed: d.lastUsed,
  passwordDueAt: d.passwordDueAt,
  state: d.state,
  thisDevice: d.thisSession,
  removedBy: d.removedBy,
);

/// The device records of a list, newest use first.
IList<UserDevice> userDevicesOf(List<GatewayDevice> ds) => ([
  for (final d in ds) userDeviceOf(d),
]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed))).lock;

/// Why the gateway refused a device login, from its `code`; null for a
/// failure that is not a refusal of the key.
UnlockRefusal? unlockRefusalOf(WyrmException e) => switch (e.code) {
  'device_removed' => UnlockRefusal.removed,
  'password_changed' => UnlockRefusal.passwordChanged,
  'password_due' => UnlockRefusal.passwordDue,
  'devices_off' => UnlockRefusal.devicesOff,
  // A bare 401 (unknown device, bad signature, a nonce out of time) has no
  // code: the gateway does not take this key (decision 1 of ADR 0050).
  null when e.status == StatusCode.of(Status.permissionDenied) =>
    UnlockRefusal.unknown,
  _ => null,
};

/// The OS prompt gave no signature: what it gave instead.
final class SignStopped implements Exception {
  const SignStopped(this.result);

  final SignResult result;

  @override
  String toString() => switch (result) {
    SignCancelled() => 'cancelled',
    SignLockout() => 'locked out',
    SignInvalidated() => 'the key no longer opens',
    SignUnavailable() => 'biometrics are not available',
    SignFailed(:final message) => message,
    Signed() => 'signed',
  };
}

/// A `sign` callback of `wyrm_client` over the device key [alias]: the OS
/// prompt with [reason]; anything but a signature throws [SignStopped].
/// [onSigned] runs once the person is checked, before the gateway answers.
Future<Uint8List> Function(Uint8List) signer(
  DeviceKey keys,
  String alias,
  String reason, {
  void Function()? onSigned,
}) => (bytes) async {
  final r = await keys.sign(alias, bytes, reason);
  if (r case Signed(:final signature)) {
    onSigned?.call();
    return signature;
  }
  throw SignStopped(r);
};

/// Seconds since the Unix epoch.
int nowS() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// The gateway (the first of the field) and the user a device key is for,
/// or null while the form has none.
({Uri gateway, String origin, String user})? accountOf(
  String? gatewayField,
  String? userField,
) {
  final gateways = parseGateways(gatewayField ?? '');
  final user = (userField ?? '').trim();
  if (gateways.isEmpty || user.isEmpty) {
    return null;
  }
  return (gateway: gateways.first, origin: gateways.first.origin, user: user);
}
