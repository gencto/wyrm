// The typed shapes of the gateway's HTTP API (crates/wyrm-gateway, ADR 0009,
// ADR 0050): the closed sets as enums and each reply as a model with one
// decoder, `fromValue`. A reply that does not have its shape throws a
// `DecodeError` naming the field; `WyrmGateway` turns it into a
// `WyrmException` with status `invalid_message`.
//
// The sources of truth, checked by `test/wire_sources_test.dart`:
// `devices.rs` (PLATFORMS, KeyAlg, StepUp, the record states), `http.rs`
// (the refusal codes), `lib.rs` (`/api/info`), ADR 0050 (`role`).

import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart';

part 'gateway_types.freezed.dart';

/// The platform of a device record (`devices.rs` `PLATFORMS`).
///
/// The set grows (`web` is planned for passkeys): a record with a platform
/// this client does not know decodes with `platform: null`, so one new
/// platform never fails a whole device list.
enum DevicePlatform implements WireName {
  macos('macos'),
  windows('windows'),
  ios('ios'),
  android('android');

  @override
  final String wire;
  const DevicePlatform(this.wire);

  static DevicePlatform? fromWire(String s) => wireByName(values, s);
}

/// The signature scheme of a device key (`devices.rs` `KeyAlg`). Closed: a
/// record with another one is a [DecodeError].
enum DeviceAlg implements WireName {
  /// ECDSA P-256 with SHA-256 (Secure Enclave, Android Keystore).
  es256('es256'),

  /// RSASSA-PKCS1-v1_5 with SHA-256 (Windows Hello).
  rs256('rs256');

  @override
  final String wire;
  const DeviceAlg(this.wire);

  static DeviceAlg? fromWire(String s) => wireByName(values, s);
}

/// The state of a device record (`/api/devices`). Closed.
enum GatewayDeviceState implements WireName {
  /// It can log in.
  active('active'),

  /// Removed by an admin (a tombstone) or by its owner.
  removed('removed'),

  /// Signed out everywhere, or its password is due.
  signedOut('signed_out');

  @override
  final String wire;
  const GatewayDeviceState(this.wire);

  static GatewayDeviceState? fromWire(String s) => wireByName(values, s);
}

/// `gateway.devices.step_up` (`devices.rs` `StepUp`). Closed.
enum StepUp implements WireName {
  /// Nothing more than the session.
  none('none'),

  /// Every request at `config` level needs a confirmed session.
  config('config');

  @override
  final String wire;
  const StepUp(this.wire);

  static StepUp? fromWire(String s) => wireByName(values, s);
}

/// The role of the broker behind a gateway (`/api/info` `role`, ADR 0036,
/// ADR 0050 §2). Closed.
enum GatewayRole implements WireName {
  active('active'),
  standby('standby');

  @override
  final String wire;
  const GatewayRole(this.wire);

  static GatewayRole? fromWire(String s) => wireByName(values, s);
}

/// The `code` of a gateway refusal (ADR 0050; `http.rs` `From<Refused>`).
///
/// The set grows: [WyrmException.refusal] is null for a code this client
/// does not know, and [WyrmException.code] keeps the text.
enum GatewayRefusal implements WireName {
  deviceRemoved('device_removed'),
  passwordChanged('password_changed'),
  passwordDue('password_due'),
  devicesOff('devices_off'),
  confirmRequired('confirm_required'),
  passwordRequired('password_required'),
  tooManyDevices('too_many_devices'),
  badPassword('bad_password');

  @override
  final String wire;
  const GatewayRefusal(this.wire);

  static GatewayRefusal? fromWire(String s) => wireByName(values, s);
}

/// `GET /api/info` (ADR 0050 §2.2, decision 10).
@freezed
abstract class GatewayInfo with _$GatewayInfo {
  const GatewayInfo._();

  const factory GatewayInfo({
    required String site,
    required String version,
    required bool tls,
    @Default(GatewayRole.active) GatewayRole role,

    /// The standby's `host:port`, when the active announces one.
    String? pair,

    /// The upstream sites of the broker.
    @Default(<String>[]) List<String> up,

    /// The oldest Studio the gateway serves.
    @Default('0') String minStudio,

    /// The CA code (32 hex digits), over TLS when the broker knows its CA.
    /// Sent by an untrusted server: a client computes its own from [ca].
    String? caFp,

    /// The CA certificate (DER).
    Uint8List? ca,

    /// The DNS and IP names of the gateway's certificate.
    @Default(<String>[]) List<String> names,
    @Default(DevicePolicy()) DevicePolicy devices,
  }) = _GatewayInfo;

  /// `site`, `version` and `tls` are required; the others are optional
  /// (`role` absent: `active`; `devices` absent: device keys off).
  factory GatewayInfo.fromValue(Value v) {
    final m = WireMap.of(v, 'GatewayInfo');
    return GatewayInfo(
      site: m.str('site'),
      version: m.str('version'),
      tls: m.boolean('tls'),
      role: m.nameOr('role', GatewayRole.values, GatewayRole.active),
      pair: m.strOrNull('pair'),
      up: m.stringsOr('up'),
      minStudio: m.strOr('min_studio', '0'),
      caFp: m.strOrNull('ca_fp'),
      ca: m.bytesOrNull('ca'),
      names: m.stringsOr('names'),
      devices: m.has('devices')
          ? DevicePolicy.fromValue(m['devices']!)
          : const DevicePolicy(),
    );
  }

  /// The old tolerant reader.
  @Deprecated('Use GatewayInfo.fromValue: it names a malformed field')
  factory GatewayInfo.of(Value v) => GatewayInfo.fromValue(v);
}

/// `gateway.devices` as `/api/info` tells it (`devices.rs` `DevicePolicy`).
@freezed
abstract class DevicePolicy with _$DevicePolicy {
  const DevicePolicy._();

  const factory DevicePolicy({
    @Default(false) bool enabled,
    @Default(5) int maxPerUser,
    @Default(30) int passwordEveryDays,
    @Default(30) int idleLockMaxMin,
    @Default(StepUp.none) StepUp stepUp,
    @Default(false) bool allowDeviceCredential,
  }) = _DevicePolicy;

  /// Every field is optional, with the defaults above.
  factory DevicePolicy.fromValue(Value v) {
    final m = WireMap.of(v, 'DevicePolicy');
    return DevicePolicy(
      enabled: m.booleanOr('enabled', false),
      maxPerUser: m.integerOr('max_per_user', 5),
      passwordEveryDays: m.integerOr('password_every_days', 30),
      idleLockMaxMin: m.integerOr('idle_lock_max_min', 30),
      stepUp: m.nameOr('step_up', StepUp.values, StepUp.none),
      allowDeviceCredential: m.booleanOr('allow_device_credential', false),
    );
  }

  /// The old tolerant reader; null gives the defaults.
  @Deprecated('Use DevicePolicy.fromValue: it names a malformed field')
  factory DevicePolicy.of(Value? v) =>
      v == null ? const DevicePolicy() : DevicePolicy.fromValue(v);
}

/// A device record (`GET /api/devices`, `devices.rs` `devices_of`).
@freezed
abstract class GatewayDevice with _$GatewayDevice {
  const GatewayDevice._();

  const factory GatewayDevice({
    required String id,
    required String name,

    /// Null: a platform this client does not know ([DevicePlatform]).
    required DevicePlatform? platform,
    @Default(DeviceAlg.es256) DeviceAlg alg,

    /// Seconds since the Unix epoch.
    @Default(0) int added,
    @Default(0) int lastUsed,
    @Default(0) int passwordAt,
    @Default(0) int passwordDueAt,
    @Default(GatewayDeviceState.active) GatewayDeviceState state,

    /// The device of this session.
    @Default(false) bool thisSession,
    String? removedBy,
    int? removedAt,
  }) = _GatewayDevice;

  /// `id`, `name`, `platform` and `state` are required; `alg` absent (a
  /// gateway older than it) is `es256`.
  factory GatewayDevice.fromValue(Value v, [String path = 'GatewayDevice']) {
    final m = WireMap.of(v, path);
    return GatewayDevice(
      id: m.str('id'),
      name: m.str('name'),
      platform: DevicePlatform.fromWire(m.str('platform')),
      alg: m.nameOr('alg', DeviceAlg.values, DeviceAlg.es256),
      added: m.integerOr('added', 0),
      lastUsed: m.integerOr('last_used', 0),
      passwordAt: m.integerOr('password_at', 0),
      passwordDueAt: m.integerOr('password_due_at', 0),
      state: m.name('state', GatewayDeviceState.values),
      thisSession: m.booleanOr('this', false),
      removedBy: m.strOrNull('removed_by'),
      removedAt: m.integerOrNull('removed_at'),
    );
  }

  /// An array of records.
  static List<GatewayDevice> listFromValue(Value v) => switch (v) {
    VArray(:final v) => [
      for (final (i, d) in v.indexed)
        GatewayDevice.fromValue(d, 'GatewayDevice[$i]'),
    ],
    _ => throw DecodeError.of('GatewayDevice[]', 'an array', v),
  };

  /// The old tolerant reader.
  @Deprecated('Use GatewayDevice.fromValue: it names a malformed field')
  factory GatewayDevice.of(Value v) => GatewayDevice.fromValue(v);
}

/// A user of the gateway (`GET /api/users`). Roles are the gateway's role
/// names, which an admin defines: text, not a closed set.
@freezed
abstract class GatewayUser with _$GatewayUser {
  const GatewayUser._();

  const factory GatewayUser(
    String name,
    List<String> roles, {
    @Default(false) bool disabled,

    /// Devices that can log in (ADR 0050).
    @Default(0) int devices,
  }) = _GatewayUser;

  /// `name` and `roles` are required.
  factory GatewayUser.fromValue(Value v, [String path = 'GatewayUser']) {
    final m = WireMap.of(v, path);
    return GatewayUser(
      m.str('name'),
      m.strings('roles'),
      disabled: m.booleanOr('disabled', false),
      devices: m.integerOr('devices', 0),
    );
  }

  /// An array of users.
  static List<GatewayUser> listFromValue(Value v) => switch (v) {
    VArray(:final v) => [
      for (final (i, u) in v.indexed)
        GatewayUser.fromValue(u, 'GatewayUser[$i]'),
    ],
    _ => throw DecodeError.of('GatewayUser[]', 'an array', v),
  };

  /// The old tolerant reader.
  @Deprecated('Use GatewayUser.fromValue: it names a malformed field')
  factory GatewayUser.of(Value v) => GatewayUser.fromValue(v);
}

/// Who the session is (`GET /api/me`): `{sub, roles, grants, max, exp,
/// site}`. Levels come as names; codes are read too.
@freezed
abstract class GatewayIdentity with _$GatewayIdentity {
  const GatewayIdentity._();

  const factory GatewayIdentity({
    /// `user:<name>` (or `user:<name>@<site>` below an upstream).
    required String sub,
    required List<String> roles,
    required List<Grant> grants,

    /// The highest level any grant gives.
    required Perm max,

    /// Session expiry, seconds since the Unix epoch.
    required int exp,

    /// The site this gateway serves.
    required String site,
  }) = _GatewayIdentity;

  factory GatewayIdentity.fromValue(Value v) {
    final m = WireMap.of(v, 'GatewayIdentity');
    return GatewayIdentity(
      sub: m.str('sub'),
      roles: m.strings('roles'),
      grants: m.list('grants', (g, path) {
        final x = WireMap.of(g, path);
        return Grant(x.str('k'), x.perm('p'));
      }),
      max: m.perm('max'),
      exp: m.integer('exp'),
      site: m.str('site'),
    );
  }
}

/// `{session, exp}` of a login (`/api/login`, `/api/device/login`).
@freezed
abstract class GatewaySession with _$GatewaySession {
  const GatewaySession._();

  const factory GatewaySession({
    required String session,

    /// Seconds since the Unix epoch; 0 when the gateway did not say.
    @Default(0) int exp,
  }) = _GatewaySession;

  factory GatewaySession.fromValue(Value v) {
    final m = WireMap.of(v, 'GatewaySession');
    return GatewaySession(
      session: m.str('session'),
      exp: m.integerOr('exp', 0),
    );
  }

  @override
  String toString() => 'GatewaySession(exp: $exp)';
}
