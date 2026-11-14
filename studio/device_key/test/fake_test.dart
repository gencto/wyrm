import 'dart:typed_data';

import 'package:device_key/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

void main() {
  final nonce = Uint8List.fromList(List.filled(56, 7));

  test('the fake signs a login message the gateway can check', () async {
    final keys = FakeDeviceKey();
    final pub = await keys.create('olena@plant');
    expect(pub.alg, 'es256');
    expect(pub.publicKey.length, 65);
    expect(pub.publicKey.first, 4);
    final msg = deviceLoginMessage(
      'plant',
      'https://gw:8443',
      'olena',
      'd1',
      nonce,
    );
    final r = await keys.sign('olena@plant', msg, 'Unlock WYRM Studio');
    expect(r, isA<Signed>());
    final sig = (r as Signed).signature;
    expect(sig.first, 0x30);
    expect(FakeDeviceKey.verify(pub.publicKey, msg, sig), isTrue);
    final other = Uint8List.fromList(msg)..[msg.length - 1] ^= 1;
    expect(FakeDeviceKey.verify(pub.publicKey, other, sig), isFalse);
    expect(keys.reasons, ['Unlock WYRM Studio']);
  });

  test('a register message is signed by the key it carries', () async {
    final keys = FakeDeviceKey();
    final pub = await keys.create('k');
    final msg = deviceRegisterMessage(
      'plant',
      'https://gw:8443',
      'olena',
      nonce,
      pub.publicKey,
    );
    final r = await keys.sign('k', msg, 'Turn on Touch ID') as Signed;
    expect(FakeDeviceKey.verify(pub.publicKey, msg, r.signature), isTrue);
  });

  test('the answers a test sets', () async {
    final keys = FakeDeviceKey();
    await keys.create('k');
    final msg = Uint8List(3);
    final want = <FakeAnswer, Matcher>{
      FakeAnswer.cancelled: isA<SignCancelled>(),
      FakeAnswer.lockout: isA<SignLockout>(),
      FakeAnswer.invalidated: isA<SignInvalidated>(),
      FakeAnswer.unavailable: isA<SignUnavailable>(),
      FakeAnswer.failed: isA<SignFailed>(),
      FakeAnswer.sign: isA<Signed>(),
    };
    for (final MapEntry(:key, :value) in want.entries) {
      keys.answer = key;
      expect(await keys.sign('k', msg, 'r'), value, reason: key.name);
    }
  });

  test('invalidate, a missing key and delete answer invalidated', () async {
    final keys = FakeDeviceKey();
    await keys.create('k');
    keys.invalidate('k');
    expect(keys.has('k'), isTrue);
    expect(await keys.sign('k', Uint8List(1), 'r'), isA<SignInvalidated>());
    await keys.create('k');
    expect(await keys.sign('k', Uint8List(1), 'r'), isA<Signed>());
    await keys.delete('k');
    expect(keys.has('k'), isFalse);
    expect(await keys.sign('k', Uint8List(1), 'r'), isA<SignInvalidated>());
  });

  test('create errors and no availability', () async {
    final keys = FakeDeviceKey()
      ..createError = const DeviceKeyException(DeviceKeyErrorCode.cancelled);
    await expectLater(
      keys.create('k'),
      throwsA(
        isA<DeviceKeyException>().having(
          (e) => e.code,
          'code',
          DeviceKeyErrorCode.cancelled,
        ),
      ),
    );
    expect((await keys.create('k')).alg, 'es256');
    keys.availability = DeviceKeyAvailability.none;
    expect(await keys.isAvailable(), DeviceKeyAvailability.none);
    await expectLater(keys.create('j'), throwsA(isA<DeviceKeyException>()));
  });
}
