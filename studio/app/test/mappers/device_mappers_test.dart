import 'package:app/mappers/device_mappers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/host_platform.dart';
import 'package:models/key_kind.dart';
import 'package:ui/indicators/biometric_icon.dart';
import 'package:ui/indicators/device_os.dart';
import 'package:ui/indicators/unlock_method.dart';
import 'package:wyrm_client/wyrm_client.dart';

void main() {
  setUp(() => S.load(const Locale('en')));

  test('each platform has its tile word, as the device tile drew it', () {
    expect(
      {for (final p in DevicePlatform.values) p: p.os.tile},
      {
        DevicePlatform.macos: 'mac',
        DevicePlatform.windows: 'win',
        DevicePlatform.ios: 'iOS',
        DevicePlatform.android: 'and',
      },
    );
    expect((null as DevicePlatform?).os, DeviceOs.unknown);
    expect(
      {for (final p in HostPlatform.values) p: p.os.tile},
      {
        HostPlatform.macos: 'mac',
        HostPlatform.windows: 'win',
        HostPlatform.ios: 'iOS',
        HostPlatform.android: 'and',
        HostPlatform.linux: 'lin',
        HostPlatform.web: 'web',
      },
    );
  });

  test('the user who removed a record, without the subject prefix', () {
    const d = GatewayDevice(
      id: 'd',
      name: 'x',
      platform: null,
      removedBy: 'user:ivan',
    );
    expect(d.removedByUser, 'ivan');
  });

  test('the method and the store follow the platform', () {
    expect(DevicePlatform.macos.os.method, 'Touch ID');
    expect(DevicePlatform.ios.os.method, 'Face ID');
    expect(DevicePlatform.windows.os.method, 'Windows Hello');
    expect(DevicePlatform.android.os.method, S.current.unlockNameFingerprint);
    expect(HostPlatform.linux.os.method, S.current.unlockNameBiometric);
    expect(DevicePlatform.macos.os.store, S.current.unlockStoreMac);
    expect(HostPlatform.linux.os.store, '');
    expect(HostPlatform.web.os.device, S.current.unlockDeviceComputer);
  });

  test('every key kind has a method; a face kind draws a face', () {
    for (final k in KeyKind.values) {
      expect(k.method.name, k.name);
    }
    expect(KeyKind.windowsHello.method.glyph, BiometricGlyph.face);
    expect(KeyKind.touchId.method.glyph, BiometricGlyph.finger);
    expect(KeyKind.none.method.glyph, BiometricGlyph.key);
    expect(KeyKind.none.method, UnlockMethod.none);
  });
}
