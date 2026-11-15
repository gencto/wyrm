import 'package:models/host_platform.dart';
import 'package:models/key_kind.dart';
import 'package:ui/indicators/device_os.dart';
import 'package:ui/indicators/unlock_method.dart';
import 'package:wyrm_client/wyrm_client.dart'
    show DevicePlatform, GatewayDevice;

// The domain's device enums as `ui` draws them: one exhaustive switch per
// enum, used by every connector (studio-rules §3). A new domain value is a
// compile error here, not a silent default on some screen.

extension DevicePlatformOs on DevicePlatform? {
  /// How `ui` draws and names a device record's platform (the gateway's
  /// set); [DeviceOs.unknown] for one this client does not know (null).
  DeviceOs get os => switch (this) {
    DevicePlatform.macos => .mac,
    DevicePlatform.windows => .windows,
    DevicePlatform.ios => .iphone,
    DevicePlatform.android => .android,
    null => .unknown,
  };
}

extension HostPlatformOs on HostPlatform {
  /// How `ui` draws and names the computer Studio runs on.
  DeviceOs get os => switch (this) {
    HostPlatform.macos => .mac,
    HostPlatform.windows => .windows,
    HostPlatform.ios => .iphone,
    HostPlatform.android => .android,
    HostPlatform.linux => .linux,
    HostPlatform.web => .web,
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

extension GatewayDeviceWho on GatewayDevice {
  /// The user who removed this record (`user:` of the subject taken off).
  String get removedByUser => (removedBy ?? '').replaceFirst('user:', '');
}
