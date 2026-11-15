import 'package:business/wyrm/decode/user_device.dart';
import 'package:models/key_kind.dart';
import 'package:ui/indicators/device_os.dart';
import 'package:ui/indicators/unlock_method.dart';

// The domain's device enums as `ui` draws them: one exhaustive switch per
// enum, used by every connector (studio-rules §3). A new domain value is a
// compile error here, not a silent default on some screen.

extension DevicePlatformOs on DevicePlatform? {
  /// How `ui` draws and names this platform; [DeviceOs.unknown] for a
  /// platform Studio does not know (a null on the record).
  DeviceOs get os => switch (this) {
    DevicePlatform.macos => .mac,
    DevicePlatform.windows => .windows,
    DevicePlatform.ios => .iphone,
    DevicePlatform.android => .android,
    DevicePlatform.linux => .linux,
    DevicePlatform.web => .web,
    null => .unknown,
  };
}

extension KeyKindMethod on KeyKind {
  /// How `ui` names and draws what unlocks the key.
  UnlockMethod get method => switch (this) {
    KeyKind.none => .none,
    KeyKind.touchId => .touchId,
    KeyKind.faceId => .faceId,
    KeyKind.opticId => .opticId,
    KeyKind.windowsHello => .windowsHello,
    KeyKind.fingerprint => .fingerprint,
    KeyKind.face => .face,
    KeyKind.iris => .iris,
    KeyKind.biometric => .biometric,
  };
}
