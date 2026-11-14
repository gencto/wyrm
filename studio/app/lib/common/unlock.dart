import 'package:localization/localization.dart';
import 'package:models/key_kind.dart';
import 'package:ui/indicators/biometric_icon.dart';

// The words and the glyph of the device unlock by platform and kind
// (unlock-discover.md §1, board `UnlockPlatforms`).

/// `Touch ID`, `Face ID`, `Windows Hello`, `fingerprint`, … The product
/// names stay as they are in every language.
String unlockName(KeyKind kind) => switch (kind) {
  KeyKind.touchId => 'Touch ID',
  KeyKind.faceId => 'Face ID',
  KeyKind.opticId => 'Optic ID',
  KeyKind.windowsHello => 'Windows Hello',
  KeyKind.fingerprint => S.current.unlockNameFingerprint,
  KeyKind.face => S.current.unlockNameFace,
  KeyKind.iris => S.current.unlockNameIris,
  KeyKind.biometric || KeyKind.none => S.current.unlockNameBiometric,
};

/// The glyph of the round button and the prompts: a face for Face ID,
/// Windows Hello and Android face, a key with no biometric, else a
/// fingerprint.
BiometricGlyph unlockGlyph(KeyKind kind) => switch (kind) {
  KeyKind.none => BiometricGlyph.key,
  KeyKind.faceId ||
  KeyKind.windowsHello ||
  KeyKind.face ||
  KeyKind.opticId => BiometricGlyph.face,
  _ => BiometricGlyph.finger,
};

/// Where the key lives: `this Mac’s Secure Enclave`, `this PC’s TPM`, …
String unlockStore(String platform) => switch (platform) {
  'mac' => S.current.unlockStoreMac,
  'windows' => S.current.unlockStoreWindows,
  'ios' => S.current.unlockStoreIos,
  'android' => S.current.unlockStoreAndroid,
  _ => '',
};

/// `this Mac`, `this PC`, `this iPhone`, `this phone`, `this computer`.
String unlockDevice(String platform) => switch (platform) {
  'mac' => S.current.unlockDeviceMac,
  'windows' => S.current.unlockDevicePc,
  'ios' => S.current.unlockDeviceIphone,
  'android' => S.current.unlockDevicePhone,
  _ => S.current.unlockDeviceComputer,
};

/// `3 Nov` for seconds since the Unix epoch; empty for 0.
String shortDate(int seconds) {
  if (seconds <= 0) {
    return '';
  }
  final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final months = S.current.monthsShort.split(',');
  return '${d.day} ${months[(d.month - 1) % months.length]}';
}

/// `now`, `5 min ago`, `2 h ago`, `3 d ago`.
String agoOf(int seconds, {DateTime? now}) {
  if (seconds <= 0) {
    return '';
  }
  final d = (now ?? DateTime.now()).difference(
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
  );
  if (d.inMinutes < 1) {
    return S.current.unlockAgoNow;
  }
  if (d.inHours < 1) {
    return S.current.agoMinutes(d.inMinutes);
  }
  if (d.inDays < 1) {
    return S.current.agoHours(d.inHours);
  }
  return S.current.agoDays(d.inDays);
}

/// Two letters of a user: `olena` → `OL`.
String initialsOf(String user) {
  final u = user.trim();
  if (u.isEmpty) {
    return '?';
  }
  final parts = u.split(RegExp(r'[\s._-]+')).where((p) => p.isNotEmpty);
  final two = parts.length > 1
      ? '${parts.first[0]}${parts.elementAt(1)[0]}'
      : u.substring(0, u.length < 2 ? u.length : 2);
  return two.toUpperCase();
}
