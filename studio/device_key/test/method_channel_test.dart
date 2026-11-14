import 'package:device_key/device_key.dart';
import 'package:device_key/src/device_key.dart' show signResultOf;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MethodChannelDeviceKey.channelName);
  final keys = MethodChannelDeviceKey();
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('isAvailable reads kind and name', () async {
    answer((_) async => {'kind': 'touchId', 'name': 'Touch ID'});
    expect(
      await keys.isAvailable(),
      const DeviceKeyAvailability(DeviceKeyKind.touchId, 'Touch ID'),
    );
  });

  test(
    'isAvailable: none, an unknown kind and an error offer nothing',
    () async {
      answer((_) async => {'kind': 'none', 'name': ''});
      expect(await keys.isAvailable(), DeviceKeyAvailability.none);
      answer((_) async => {'kind': 'retina', 'name': 'Retina'});
      expect((await keys.isAvailable()).available, isFalse);
      answer((_) async => throw PlatformException(code: 'failed'));
      expect(await keys.isAvailable(), DeviceKeyAvailability.none);
    },
  );

  test('create sends the alias and reads the public key', () async {
    final point = Uint8List(65)..[0] = 4;
    answer((_) async => {'alg': 'es256', 'publicKey': point});
    final pub = await keys.create('olena@plant', allowDeviceCredential: true);
    expect(pub.alg, 'es256');
    expect(pub.publicKey, point);
    expect(calls.single.method, 'create');
    expect(calls.single.arguments, {
      'alias': 'olena@plant',
      'allowDeviceCredential': true,
    });
  });

  test('create maps the platform error codes', () async {
    for (final code in DeviceKeyErrorCode.values) {
      answer(
        (_) async => throw PlatformException(code: code.name, message: 'm'),
      );
      await expectLater(
        keys.create('a'),
        throwsA(
          isA<DeviceKeyException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.message, 'message', 'm'),
        ),
      );
    }
    answer((_) async => throw PlatformException(code: 'odd'));
    await expectLater(
      keys.create('a'),
      throwsA(
        isA<DeviceKeyException>().having(
          (e) => e.code,
          'code',
          DeviceKeyErrorCode.failed,
        ),
      ),
    );
    answer((_) async => {'alg': 'es256'});
    await expectLater(keys.create('a'), throwsA(isA<DeviceKeyException>()));
  });

  test('sign sends bytes and reason and maps every result', () async {
    final sig = Uint8List.fromList([0x30, 1, 2]);
    answer((_) async => {'result': 'signed', 'signature': sig});
    final r = await keys.sign('a', Uint8List.fromList([1, 2]), 'Log in');
    expect(r, isA<Signed>().having((s) => s.signature, 'signature', sig));
    expect(calls.single.arguments, {
      'alias': 'a',
      'bytes': Uint8List.fromList([1, 2]),
      'reason': 'Log in',
      'cancelLabel': 'Cancel',
    });
    final cases = <String, Matcher>{
      'cancelled': isA<SignCancelled>(),
      'lockout': isA<SignLockout>(),
      'invalidated': isA<SignInvalidated>(),
      'unavailable': isA<SignUnavailable>(),
      'failed': isA<SignFailed>().having((f) => f.message, 'message', 'boom'),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      answer((_) async => {'result': key, 'message': 'boom'});
      expect(await keys.sign('a', Uint8List(1), 'r'), value, reason: key);
    }
  });

  test('a thrown sign error is a result, never an exception', () async {
    answer((_) async => throw PlatformException(code: 'invalidated'));
    expect(await keys.sign('a', Uint8List(1), 'r'), isA<SignInvalidated>());
    answer((_) async => throw PlatformException(code: 'odd', message: 'x'));
    expect(
      await keys.sign('a', Uint8List(1), 'r'),
      isA<SignFailed>().having((f) => f.message, 'message', 'x'),
    );
  });

  test('signed without a signature is a failure', () {
    expect(signResultOf({'result': 'signed'}), isA<SignFailed>());
    expect(signResultOf(null), isA<SignFailed>());
  });

  test('delete sends the alias', () async {
    answer((_) async => null);
    await keys.delete('a');
    expect(calls.single.method, 'delete');
    expect(calls.single.arguments, {'alias': 'a'});
  });

  test('no plugin: nothing offered, sign fails, delete is quiet', () async {
    expect(await keys.isAvailable(), DeviceKeyAvailability.none);
    expect(await keys.sign('a', Uint8List(1), 'r'), isA<SignFailed>());
    await keys.delete('a');
  });

  test('NoDeviceKey offers nothing', () async {
    const k = NoDeviceKey();
    expect(await k.isAvailable(), DeviceKeyAvailability.none);
    await expectLater(k.create('a'), throwsA(isA<DeviceKeyException>()));
    expect(await k.sign('a', Uint8List(1), 'r'), isA<SignUnavailable>());
  });

  test('DeviceKey() picks the platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(DeviceKey(), isA<NoDeviceKey>());
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(DeviceKey(), isA<MethodChannelDeviceKey>());
    debugDefaultTargetPlatformOverride = null;
  });
}
