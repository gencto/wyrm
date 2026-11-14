import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'types.dart';

/// A signing key the OS keeps behind its biometric prompt (ADR 0050).
///
/// Make one with [DeviceKey.new]: the platform's own on macOS, iOS, Android
/// and Windows, and one that offers nothing elsewhere (Linux, web). Tests use
/// `FakeDeviceKey` from `package:device_key/testing.dart`.
///
/// An `alias` names one key of this app; the native side keeps it under its
/// own prefix, so aliases of other apps never meet it.
abstract interface class DeviceKey {
  factory DeviceKey() {
    if (kIsWeb) {
      return const NoDeviceKey();
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.windows => MethodChannelDeviceKey(),
      _ => const NoDeviceKey(),
    };
  }

  /// Whether a key can be made here and what the UI calls the prompt.
  Future<DeviceKeyAvailability> isAvailable();

  /// Make a key under [alias], replacing one that is there. No prompt on
  /// Apple platforms and Android; Windows Hello asks.
  ///
  /// [allowDeviceCredential] lets the device PIN or password stand in for
  /// the biometric (the gateway's `allow_device_credential`); such a key
  /// outlives an enrollment change. Throws [DeviceKeyException].
  Future<DeviceKeyPublic> create(
    String alias, {
    bool allowDeviceCredential = false,
  });

  /// Sign [bytes] with the key [alias] after the OS prompt, which shows
  /// [reason] (Apple platforms: the reason line; Android: the title; Windows
  /// Hello shows its own text). [cancelLabel] is the negative button of the
  /// Android prompt. Never throws.
  Future<SignResult> sign(
    String alias,
    Uint8List bytes,
    String reason, {
    String cancelLabel = 'Cancel',
  });

  /// Delete the key [alias]; nothing happens when there is none.
  Future<void> delete(String alias);
}

/// The platform's key over the channel `uk.gencto.device_key`.
class MethodChannelDeviceKey implements DeviceKey {
  MethodChannelDeviceKey({@visibleForTesting MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'uk.gencto.device_key';

  final MethodChannel _channel;

  @override
  Future<DeviceKeyAvailability> isAvailable() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('isAvailable');
      final kind = DeviceKeyKind.of(r?['kind'] as String?);
      if (kind == DeviceKeyKind.none) {
        return DeviceKeyAvailability.none;
      }
      return DeviceKeyAvailability(kind, (r?['name'] as String?) ?? '');
    } on PlatformException {
      return DeviceKeyAvailability.none;
    } on MissingPluginException {
      return DeviceKeyAvailability.none;
    }
  }

  @override
  Future<DeviceKeyPublic> create(
    String alias, {
    bool allowDeviceCredential = false,
  }) async {
    final Map<String, Object?>? r;
    try {
      r = await _channel.invokeMapMethod<String, Object?>('create', {
        'alias': alias,
        'allowDeviceCredential': allowDeviceCredential,
      });
    } on PlatformException catch (e) {
      throw DeviceKeyException(
        DeviceKeyErrorCode.of(e.code),
        e.message ?? e.code,
      );
    } on MissingPluginException catch (e) {
      throw DeviceKeyException(
        DeviceKeyErrorCode.unavailable,
        e.message ?? 'no device key on this platform',
      );
    }
    final alg = r?['alg'];
    final key = r?['publicKey'];
    if (alg is! String || key is! Uint8List || key.isEmpty) {
      throw const DeviceKeyException(
        DeviceKeyErrorCode.failed,
        'the platform gave no public key',
      );
    }
    return DeviceKeyPublic(alg: alg, publicKey: key);
  }

  @override
  Future<SignResult> sign(
    String alias,
    Uint8List bytes,
    String reason, {
    String cancelLabel = 'Cancel',
  }) async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('sign', {
        'alias': alias,
        'bytes': bytes,
        'reason': reason,
        'cancelLabel': cancelLabel,
      });
      return signResultOf(r);
    } on PlatformException catch (e) {
      return signResultOf({'result': e.code, 'message': e.message ?? e.code});
    } on MissingPluginException catch (e) {
      return SignFailed(e.message ?? 'no device key on this platform');
    }
  }

  @override
  Future<void> delete(String alias) async {
    try {
      await _channel.invokeMethod<void>('delete', {'alias': alias});
    } on MissingPluginException {
      // Nothing was ever made here.
    }
  }
}

/// The answer of the native `sign`: `{result, signature?, message?}`.
@visibleForTesting
SignResult signResultOf(Map<Object?, Object?>? r) {
  final message = (r?['message'] as String?) ?? '';
  switch (r?['result']) {
    case 'signed':
      final s = r?['signature'];
      return s is Uint8List && s.isNotEmpty
          ? Signed(s)
          : const SignFailed('the platform gave no signature');
    case 'cancelled':
      return const SignCancelled();
    case 'lockout':
      return const SignLockout();
    case 'invalidated':
      return const SignInvalidated();
    case 'unavailable':
      return const SignUnavailable();
    case 'failed':
      return SignFailed(message);
    case final Object? other:
      return SignFailed(message.isEmpty ? 'unknown result $other' : message);
  }
}

/// Linux, web and the rest: never offers a key.
class NoDeviceKey implements DeviceKey {
  const NoDeviceKey();

  @override
  Future<DeviceKeyAvailability> isAvailable() async =>
      DeviceKeyAvailability.none;

  @override
  Future<DeviceKeyPublic> create(
    String alias, {
    bool allowDeviceCredential = false,
  }) async => throw const DeviceKeyException(
    DeviceKeyErrorCode.unavailable,
    'no device key on this platform',
  );

  @override
  Future<SignResult> sign(
    String alias,
    Uint8List bytes,
    String reason, {
    String cancelLabel = 'Cancel',
  }) async => const SignUnavailable();

  @override
  Future<void> delete(String alias) async {}
}
