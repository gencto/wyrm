import 'dart:typed_data';

/// What unlocks the key on this device. The UI picks its icon by this.
enum DeviceKeyKind {
  /// No key can be made here: Linux, web, no sensor, nothing enrolled, or a
  /// build that cannot reach the secure hardware.
  none,

  /// macOS, iOS: Touch ID.
  touchId,

  /// iOS: Face ID.
  faceId,

  /// visionOS-class devices: Optic ID.
  opticId,

  /// Windows: Windows Hello (face, finger or Hello PIN).
  windowsHello,

  /// Android: a fingerprint sensor is the strong biometric.
  fingerprint,

  /// Android: face unlock is the strong biometric.
  face,

  /// Android: iris.
  iris,

  /// Android: a strong biometric of more than one kind, or one the OS does
  /// not name.
  biometric;

  /// The kind for its wire name; an unknown name reads as [none].
  static DeviceKeyKind of(String? name) => DeviceKeyKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => DeviceKeyKind.none,
  );
}

/// Whether a device key can be made here, and the word the UI shows for it.
class DeviceKeyAvailability {
  const DeviceKeyAvailability(this.kind, this.name);

  /// Nothing to offer.
  static const none = DeviceKeyAvailability(
    DeviceKeyKind.none,
    '',
  );

  final DeviceKeyKind kind;

  /// "Touch ID", "Face ID", "Windows Hello", "Fingerprint", … (English, from
  /// the platform; a localised UI maps [kind] to its own words).
  final String name;

  bool get available => kind != DeviceKeyKind.none;

  @override
  bool operator ==(Object other) =>
      other is DeviceKeyAvailability &&
      other.kind == kind &&
      other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => 'DeviceKeyAvailability($kind, $name)';
}

/// The public half of a new device key, as `POST /api/devices` takes it.
class DeviceKeyPublic {
  const DeviceKeyPublic({required this.alg, required this.publicKey});

  /// `es256` (Secure Enclave, Android Keystore: P-256, the 65-byte
  /// uncompressed point) or `rs256` (Windows Hello: RSA-2048, PKCS#1 DER).
  final String alg;

  final Uint8List publicKey;

  @override
  String toString() => 'DeviceKeyPublic($alg, ${publicKey.length} bytes)';
}

/// Why `DeviceKey.create` made no key.
enum DeviceKeyErrorCode {
  /// The person closed the OS prompt (Windows Hello asks at creation).
  cancelled,

  /// The OS locked its biometrics after too many misses.
  lockout,

  /// No biometric, nothing enrolled, no secure hardware, or a build that
  /// cannot reach it.
  unavailable,

  /// Anything else; [DeviceKeyException.message] says what.
  failed;

  static DeviceKeyErrorCode of(String? code) =>
      DeviceKeyErrorCode.values.firstWhere(
        (c) => c.name == code,
        orElse: () => DeviceKeyErrorCode.failed,
      );
}

/// `DeviceKey.create` made no key.
class DeviceKeyException implements Exception {
  const DeviceKeyException(this.code, [this.message = '']);

  final DeviceKeyErrorCode code;
  final String message;

  @override
  String toString() => 'DeviceKeyException(${code.name}: $message)';
}

/// What `DeviceKey.sign` gave.
sealed class SignResult {
  const SignResult();
}

/// The OS checked the person and signed. [signature] is ASN.1 DER ECDSA over
/// SHA-256 for `es256`, RSASSA-PKCS1-v1_5 SHA-256 for `rs256`.
final class Signed extends SignResult {
  const Signed(this.signature);

  final Uint8List signature;
}

/// The person closed the prompt, chose the password, or the OS took the
/// prompt away. The key is kept.
final class SignCancelled extends SignResult {
  const SignCancelled();
}

/// The biometric did not match too many times, or the OS locked it. The key
/// is kept.
final class SignLockout extends SignResult {
  const SignLockout();
}

/// The key can never sign again: fingerprints or faces changed, the key is
/// gone, or it came from another device. Delete it and its device record.
final class SignInvalidated extends SignResult {
  const SignInvalidated();
}

/// Biometrics are off or not enrolled any more, or the hardware is busy. The
/// key may work later.
final class SignUnavailable extends SignResult {
  const SignUnavailable();
}

/// Anything else.
final class SignFailed extends SignResult {
  const SignFailed(this.message);

  final String message;
}
