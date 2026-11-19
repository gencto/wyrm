import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_key/device_key.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart' hide ErrorHint;
import 'package:models/device_tag.dart';
import 'package:models/error_hint.dart';
import 'package:models/host_platform.dart';
import 'package:models/key_kind.dart';
import 'package:models/lock_error.dart';
import 'package:models/refusal_code.dart';
import 'package:models/step_up_error.dart';
import 'package:models/unlock_fallback.dart';
import 'package:models/unlock_refusal.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'session.dart';

// What Studio does with the device key of ADR 0050, in one place: the
// platform names, the alias of a key, the signer that turns the OS prompt
// into bytes, and the mapping of the gateway's answers.

/// The platform Studio runs on: the one a new device record names and the
/// log-in page draws (unlock-discover.md §1).
HostPlatform hostPlatform() {
  if (kIsWeb) {
    return .web;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS => .macos,
    TargetPlatform.windows => .windows,
    TargetPlatform.iOS => .ios,
    TargetPlatform.android => .android,
    _ => .linux,
  };
}

extension HostPlatformOnWire on HostPlatform {
  /// The gateway's name for this platform; null where Studio keeps no
  /// device key (`linux`, `web`).
  DevicePlatform? get device => switch (this) {
    HostPlatform.macos => .macos,
    HostPlatform.windows => .windows,
    HostPlatform.ios => .ios,
    HostPlatform.android => .android,
    HostPlatform.linux || HostPlatform.web => null,
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

/// The state's [KeyKind] for the plugin's: one exhaustive switch, so a
/// kind the plugin adds is a compile error here.
KeyKind keyKindOf(DeviceKeyKind k) => switch (k) {
  DeviceKeyKind.none => KeyKind.none,
  DeviceKeyKind.touchId => KeyKind.touchId,
  DeviceKeyKind.faceId => KeyKind.faceId,
  DeviceKeyKind.opticId => KeyKind.opticId,
  DeviceKeyKind.windowsHello => KeyKind.windowsHello,
  DeviceKeyKind.fingerprint => KeyKind.fingerprint,
  DeviceKeyKind.face => KeyKind.face,
  DeviceKeyKind.iris => KeyKind.iris,
  DeviceKeyKind.biometric => KeyKind.biometric,
};

/// A moment given in seconds since the Unix epoch; null for 0 (not known).
DateTime? momentOf(int seconds) =>
    seconds <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

extension GatewayDeviceWho on GatewayDevice {
  /// The user who removed this record (`user:` of the subject taken off).
  String get removedByUser => (removedBy ?? '').replaceFirst('user:', '');
}

/// A device record as a row of Account › Security, with what is computed
/// from it and the clock: whether it is this computer's (`own`), its
/// `tag`, the days until its password is due, whether it was used within
/// the last minute.
typedef DeviceRow = ({
  GatewayDevice device,
  bool own,
  DeviceTag? tag,
  String removedBy,
  int dueDays,
  bool usedNow,
  DateTime? lastUsed,
  DateTime? added,
});

/// A use this recent is `used now` on this computer's own row.
const _usedNowS = 60;

/// A password due within this many days is tagged.
const _dueSoonDays = 7;

/// [d] as a row at [now]; [thisDeviceId] is this computer's device.
DeviceRow deviceRowOf(GatewayDevice d, String? thisDeviceId, DateTime now) {
  final own = d.thisSession || d.id == thisDeviceId;
  final nowS = now.millisecondsSinceEpoch ~/ 1000;
  final dueDays = d.passwordDueAt == 0
      ? null
      : ((d.passwordDueAt - nowS) / Duration.secondsPerDay).ceil();
  return (
    device: d,
    own: own,
    tag: switch (d.state) {
      GatewayDeviceState.removed => DeviceTag.removed,
      _ when own => DeviceTag.thisDevice,
      GatewayDeviceState.signedOut => DeviceTag.signedOut,
      GatewayDeviceState.active
          when dueDays != null && dueDays <= _dueSoonDays =>
        DeviceTag.passwordDue,
      GatewayDeviceState.active => null,
    },
    removedBy: d.removedByUser,
    dueDays: dueDays == null || dueDays < 0 ? 0 : dueDays,
    usedNow: own && d.lastUsed > 0 && nowS - d.lastUsed < _usedNowS,
    lastUsed: momentOf(d.lastUsed),
    added: momentOf(d.added),
  );
}

/// The device records of a list, newest use first.
IList<GatewayDevice> newestFirst(List<GatewayDevice> ds) =>
    ([...ds]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed))).lock;

/// Why the gateway refused a device login, from its refusal code; null
/// for a failure that is not a refusal of the key.
UnlockRefusal? unlockRefusalOf(WyrmException e) => switch (e.refusal) {
  GatewayRefusal.deviceRemoved => UnlockRefusal.removed,
  GatewayRefusal.passwordChanged => UnlockRefusal.passwordChanged,
  GatewayRefusal.passwordDue => UnlockRefusal.passwordDue,
  GatewayRefusal.devicesOff => UnlockRefusal.devicesOff,
  GatewayRefusal.confirmRequired ||
  GatewayRefusal.passwordRequired ||
  GatewayRefusal.tooManyDevices ||
  GatewayRefusal.badPassword => null,
  // A bare 401 (unknown device, bad signature, a nonce out of time) has no
  // code: the gateway does not take this key (decision 1 of ADR 0050). A
  // code this client does not know is not about the key.
  null =>
    e.code == null && e.status == StatusCode.of(Status.permissionDenied)
        ? UnlockRefusal.unknown
        : null,
};

/// Why the page falls back to the password when the prompt gave [r]
/// instead of a signature (the key kept).
UnlockFallback fallbackOf(SignResult r) => switch (r) {
  SignLockout() => UnlockFallback.lockedOut,
  SignCancelled() ||
  SignUnavailable() ||
  SignFailed() ||
  SignInvalidated() ||
  Signed() => UnlockFallback.notOpened,
};

/// What the step-up dialog says when the prompt gave [r] instead of a
/// signature. A signature is never a stop ([signer] returns it), so
/// [Signed] reads as the prompt that gave none.
StepUpError stepUpErrorOf(SignResult r) => switch (r) {
  SignCancelled() ||
  SignLockout() ||
  SignUnavailable() ||
  Signed() => const .stopped(),
  SignInvalidated() => const .keyGone(),
  SignFailed(:final message) => .refused(message),
};

/// The code of a refusal the gateway named, as Studio keeps it.
RefusalCode refusalCodeOf(GatewayRefusal r) => switch (r) {
  GatewayRefusal.deviceRemoved => .deviceRemoved,
  GatewayRefusal.passwordChanged => .passwordChanged,
  GatewayRefusal.passwordDue => .passwordDue,
  GatewayRefusal.devicesOff => .devicesOff,
  GatewayRefusal.confirmRequired => .confirmRequired,
  GatewayRefusal.passwordRequired => .passwordRequired,
  GatewayRefusal.tooManyDevices => .tooManyDevices,
  GatewayRefusal.badPassword => .badPassword,
};

/// Why the lock stays on after the gateway refused [e]: the password, a
/// refusal it named, else its message.
LockError lockErrorOf(WyrmException e) => switch (e.refusal) {
  GatewayRefusal.badPassword => const .wrongPassword(),
  final r? => .gateway(refusalCodeOf(r)),
  null => .refused(e.message),
};

/// What the step-up says after the gateway refused [e]: the password, a
/// refusal it named, else its message.
StepUpError stepUpRefusalOf(WyrmException e) => switch (e.refusal) {
  GatewayRefusal.badPassword => const .wrongPassword(),
  final r? => .gateway(refusalCodeOf(r)),
  null => .refused(e.message),
};

/// The words of the OS prompts of the device key (unlock-discover.md §2):
/// `ui`'s, handed to `AppDependencies` by `app`, so that `business` writes
/// none (studio-rules §5). Each is asked with the site and the user at the
/// moment the prompt opens.
abstract interface class DevicePrompts {
  /// A device login or an idle unlock.
  String unlock(String site, String user);

  /// Making and registering a new key.
  String enable(String site, String user);

  /// A step-up of a refused request.
  String confirm(String site);
}

/// No words: the site and the user as they are, for a store no words were
/// given to (tests). The app always gives its own.
final class PlainPrompts implements DevicePrompts {
  const PlainPrompts();

  @override
  String unlock(String site, String user) => '$site · $user';

  @override
  String enable(String site, String user) => '$site · $user';

  @override
  String confirm(String site) => site;
}

/// The OS prompt gave no signature: what it gave instead. Its text is for
/// the log; a screen says [signHintOf].
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

/// What Studio says of a prompt that gave no signature; null when the
/// system gave its own words ([SignFailed]), which are shown as they came.
ErrorHint? signHintOf(SignResult r) => switch (r) {
  SignCancelled() => const ErrorHint.signCancelled(),
  SignLockout() => const ErrorHint.signLockedOut(),
  SignInvalidated() => const ErrorHint.signKeyGone(),
  SignUnavailable() => const ErrorHint.signUnavailable(),
  SignFailed() || Signed() => null,
};

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
({GatewayAddress gateway, String origin, String user})? accountOf(
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
