import 'package:localization/localization.dart';

/// A device's platform as Studio draws and says it (unlock-discover.md §1,
/// board `UnlockApp`): the word on its tile, the method its key unlocks
/// with, where the key lives and what the device is called. A `ui` enum
/// (studio-rules §3): it owns its drawing and its words; the domain
/// platform reaches it through one mapper in `app/lib/mappers/`.
enum DeviceOs {
  mac('mac'),
  windows('win'),
  iphone('iOS'),
  android('and'),
  linux('lin'),
  web('web'),

  /// A platform Studio does not know.
  unknown('?');

  const DeviceOs(this.tile);

  /// The word on the device tile: `mac`, `iOS`, `win`, `and`. The same in
  /// every language.
  final String tile;

  /// What a key on this device unlocks with: `Touch ID`, `Face ID`,
  /// `Windows Hello` (product names, never translated), `fingerprint`.
  String get method => switch (this) {
    mac => 'Touch ID',
    iphone => 'Face ID',
    windows => 'Windows Hello',
    android => S.current.unlockNameFingerprint,
    linux || web || unknown => S.current.unlockNameBiometric,
  };

  /// Where the key lives: `this Mac’s Secure Enclave`, `this PC’s TPM`, …;
  /// empty where Studio keeps no key.
  String get store => switch (this) {
    mac => S.current.unlockStoreMac,
    windows => S.current.unlockStoreWindows,
    iphone => S.current.unlockStoreIos,
    android => S.current.unlockStoreAndroid,
    linux || web || unknown => '',
  };

  /// `this Mac`, `this PC`, `this iPhone`, `this phone`, `this computer`.
  String get device => switch (this) {
    mac => S.current.unlockDeviceMac,
    windows => S.current.unlockDevicePc,
    iphone => S.current.unlockDeviceIphone,
    android => S.current.unlockDevicePhone,
    linux || web || unknown => S.current.unlockDeviceComputer,
  };
}
