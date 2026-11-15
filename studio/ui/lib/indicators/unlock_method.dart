import 'package:localization/localization.dart';

import 'biometric_icon.dart';

/// What unlocks the device key here, as Studio names and draws it
/// (unlock-discover.md §1): its name in `Unlock with <name>` and its glyph.
/// A `ui` enum (studio-rules §3); the domain `KeyKind` reaches it through
/// one mapper in `app/lib/mappers/`.
enum UnlockMethod {
  touchId(.finger),
  faceId(.face),
  opticId(.face),
  windowsHello(.face),
  fingerprint(.finger),
  face(.face),
  iris(.finger),
  biometric(.finger),

  /// No biometric here: the key glyph.
  none(.key);

  const UnlockMethod(this.glyph);

  /// The glyph of the round button and the prompts.
  final BiometricGlyph glyph;

  /// `Touch ID`, `Face ID`, `Windows Hello`, `fingerprint`, … The product
  /// names stay as they are in every language.
  String get label => switch (this) {
    touchId => 'Touch ID',
    faceId => 'Face ID',
    opticId => 'Optic ID',
    windowsHello => 'Windows Hello',
    fingerprint => S.current.unlockNameFingerprint,
    face => S.current.unlockNameFace,
    iris => S.current.unlockNameIris,
    biometric || none => S.current.unlockNameBiometric,
  };
}
