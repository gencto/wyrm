import 'package:business/wyrm/device_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The platform a device record is registered with is one the gateway
/// accepts (`wyrm_gateway::devices::PLATFORMS`, ADR 0050). Studio sent `mac`
/// and the gateway refused the registration on macOS with
/// `platform: one of macos, windows, ios, android`.
void main() {
  const accepted = {'macos', 'windows', 'ios', 'android'};

  for (final (target, name) in [
    (TargetPlatform.macOS, 'macos'),
    (TargetPlatform.windows, 'windows'),
    (TargetPlatform.iOS, 'ios'),
    (TargetPlatform.android, 'android'),
  ]) {
    test('$target registers as $name, a platform the gateway takes', () {
      debugDefaultTargetPlatformOverride = target;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(devicePlatform(), name);
      expect(accepted, contains(devicePlatform()));
    });
  }
}
