/// A software [DeviceKey] for tests: real P-256 keys made in Dart, signatures
/// the gateway accepts (`es256`, ASN.1 DER over SHA-256), and answers a test
/// sets: cancelled, lockout, invalidated, unavailable, failed.
///
/// ```dart
/// final keys = FakeDeviceKey();
/// final pub = await keys.create('olena@plant');
/// keys.answer = FakeAnswer.cancelled; // every sign now answers cancelled
/// keys.invalidate('olena@plant');     // as if fingerprints changed
/// ```
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'device_key.dart';

export 'device_key.dart';

/// What [FakeDeviceKey.sign] answers.
enum FakeAnswer { sign, cancelled, lockout, invalidated, unavailable, failed }

class FakeDeviceKey implements DeviceKey {
  FakeDeviceKey({
    this.availability = const DeviceKeyAvailability(
      DeviceKeyKind.touchId,
      'Touch ID',
    ),
  });

  /// What [isAvailable] answers.
  DeviceKeyAvailability availability;

  /// What every [sign] answers until a test changes it. With
  /// [FakeAnswer.sign] a key that is not there (or was [invalidate]d)
  /// answers [SignInvalidated], as the platforms do.
  FakeAnswer answer = FakeAnswer.sign;

  /// When set, the next [create] throws it (and clears it).
  DeviceKeyException? createError;

  /// The reasons of every prompt, in order.
  final List<String> reasons = [];

  final Map<String, AsymmetricKeyPair<ECPublicKey, ECPrivateKey>> _keys = {};
  final Set<String> _invalid = {};

  static final ECDomainParameters _p256 = ECCurve_secp256r1();

  /// Whether a key [alias] exists (an invalidated one counts until deleted).
  bool has(String alias) => _keys.containsKey(alias);

  /// The 65-byte public point of [alias], or null.
  Uint8List? publicKey(String alias) => _keys[alias]?.publicKey.Q?.getEncoded(
    false,
  );

  /// The key [alias] can never sign again, as after an enrollment change.
  void invalidate(String alias) => _invalid.add(alias);

  @override
  Future<DeviceKeyAvailability> isAvailable() async => availability;

  @override
  Future<DeviceKeyPublic> create(
    String alias, {
    bool allowDeviceCredential = false,
  }) async {
    final error = createError;
    if (error != null) {
      createError = null;
      throw error;
    }
    if (!availability.available) {
      throw const DeviceKeyException(
        DeviceKeyErrorCode.unavailable,
        'no device key here',
      );
    }
    final random = Random.secure();
    final seed = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final gen = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(_p256),
          FortunaRandom()..seed(KeyParameter(seed)),
        ),
      );
    final pair = gen.generateKeyPair();
    _keys[alias] = AsymmetricKeyPair(
      pair.publicKey as ECPublicKey,
      pair.privateKey as ECPrivateKey,
    );
    _invalid.remove(alias);
    return DeviceKeyPublic(alg: 'es256', publicKey: publicKey(alias)!);
  }

  @override
  Future<SignResult> sign(
    String alias,
    Uint8List bytes,
    String reason, {
    String cancelLabel = 'Cancel',
  }) async {
    reasons.add(reason);
    switch (answer) {
      case FakeAnswer.cancelled:
        return const SignCancelled();
      case FakeAnswer.lockout:
        return const SignLockout();
      case FakeAnswer.invalidated:
        return const SignInvalidated();
      case FakeAnswer.unavailable:
        return const SignUnavailable();
      case FakeAnswer.failed:
        return const SignFailed('fake failure');
      case FakeAnswer.sign:
        break;
    }
    final key = _keys[alias];
    if (key == null || _invalid.contains(alias)) {
      return const SignInvalidated();
    }
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(key.privateKey));
    final sig = (signer.generateSignature(bytes) as ECSignature).normalize(
      _p256,
    );
    return Signed(_der(sig.r, sig.s));
  }

  @override
  Future<void> delete(String alias) async {
    _keys.remove(alias);
    _invalid.remove(alias);
  }

  /// Check an `es256` [signature] (DER) over [message] with a 65-byte
  /// [publicKey], as the gateway does.
  static bool verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) {
    final rs = _unDer(signature);
    if (rs == null) {
      return false;
    }
    try {
      final q = _p256.curve.decodePoint(publicKey);
      final v = ECDSASigner(SHA256Digest())
        ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, _p256)));
      return v.verifySignature(message, ECSignature(rs.$1, rs.$2));
    } on Object {
      return false;
    }
  }
}

/// `SEQUENCE { INTEGER r, INTEGER s }`.
Uint8List _der(BigInt r, BigInt s) {
  final body = [..._derInt(r), ..._derInt(s)];
  return Uint8List.fromList([0x30, ..._derLen(body.length), ...body]);
}

List<int> _derInt(BigInt v) {
  var bytes = <int>[];
  var x = v;
  while (x > BigInt.zero) {
    bytes.insert(0, (x & BigInt.from(0xff)).toInt());
    x >>= 8;
  }
  if (bytes.isEmpty) {
    bytes = [0];
  }
  if (bytes.first & 0x80 != 0) {
    bytes.insert(0, 0);
  }
  return [0x02, ..._derLen(bytes.length), ...bytes];
}

List<int> _derLen(int n) => n < 0x80 ? [n] : [0x81, n];

(BigInt, BigInt)? _unDer(Uint8List d) {
  var i = 0;
  int? len() {
    if (i >= d.length) {
      return null;
    }
    final b = d[i++];
    if (b < 0x80) {
      return b;
    }
    if (b == 0x81 && i < d.length) {
      return d[i++];
    }
    return null;
  }

  BigInt? integer() {
    if (i >= d.length || d[i++] != 0x02) {
      return null;
    }
    final n = len();
    if (n == null || i + n > d.length) {
      return null;
    }
    var v = BigInt.zero;
    for (final b in d.sublist(i, i + n)) {
      v = (v << 8) | BigInt.from(b);
    }
    i += n;
    return v;
  }

  if (d.isEmpty || d[i++] != 0x30 || len() == null) {
    return null;
  }
  final r = integer();
  final s = integer();
  return r == null || s == null || i != d.length ? null : (r, s);
}
