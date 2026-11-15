import 'package:app/mappers/device_mappers.dart';
import 'package:business/wyrm/decode/user_device.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/key_kind.dart';
import 'package:ui/indicators/biometric_icon.dart';
import 'package:ui/indicators/device_os.dart';
import 'package:ui/indicators/unlock_method.dart';

void main() {
  setUp(() => S.load(const Locale('en')));

  test('each platform has its tile word, as the device tile drew it', () {
    expect({for (final p in DevicePlatform.values) p: p.os.tile}, {
      DevicePlatform.macos: 'mac',
      DevicePlatform.windows: 'win',
      DevicePlatform.ios: 'iOS',
      DevicePlatform.android: 'and',
      DevicePlatform.linux: 'lin',
      DevicePlatform.web: 'web',
    });
    expect((null as DevicePlatform?).os, DeviceOs.unknown);
  });

  test('the method and the store follow the platform', () {
    expect(DevicePlatform.macos.os.method, 'Touch ID');
    expect(DevicePlatform.ios.os.method, 'Face ID');
    expect(DevicePlatform.windows.os.method, 'Windows Hello');
    expect(DevicePlatform.android.os.method, S.current.unlockNameFingerprint);
    expect(DevicePlatform.linux.os.method, S.current.unlockNameBiometric);
    expect(DevicePlatform.macos.os.store, S.current.unlockStoreMac);
    expect(DevicePlatform.linux.os.store, '');
    expect(DevicePlatform.web.os.device, S.current.unlockDeviceComputer);
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
