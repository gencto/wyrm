import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

part 'user_device.freezed.dart';

// One device record of a gateway user (`GET /api/devices`,
// `/api/users/<u>/devices`; ADR 0050 §1.5), decoded once from the
// gateway's `GatewayDevice` (studio-rules §8). Its closed sets are enums
// with their wire names (rule 2).
//
// ignore: flutter_style_todos — the marker the wyrm_client typing greps for
// TODO(wyrm_client typing): replace DevicePlatform and DeviceRecordState
// with the wire enums of `wyrm_client`, and GatewayDevice's strings with
// them, once that package types its gateway records. They live here and
// not in `models` so that no second wire enum is left behind there.

/// The platform a device record names (`platform`), and the one Studio
/// runs on. The gateway takes `macos | windows | ios | android`; `linux`
/// and `web` are Studio's own (no device key there).
enum DevicePlatform {
  macos('macos'),
  windows('windows'),
  ios('ios'),
  android('android'),
  linux('linux'),
  web('web');

  const DevicePlatform(this.wire);

  /// The name on the wire.
  final String wire;

  /// The platform of [s], or null for a name Studio does not know.
  static DevicePlatform? fromWire(String s) =>
      values.where((p) => p.wire == s).firstOrNull;
}

/// The `state` of a device record.
enum DeviceRecordState {
  active('active'),

  /// Removed by an administrator: the user may forget it.
  removed('removed'),

  /// Ended by `Sign out everywhere`.
  signedOut('signed_out');

  const DeviceRecordState(this.wire);

  /// The name on the wire.
  final String wire;

  /// The state of [s], or null for a name Studio does not know.
  static DeviceRecordState? fromWire(String s) =>
      values.where((p) => p.wire == s).firstOrNull;
}

/// A device record as the state keeps it.
@freezed
abstract class UserDevice with _$UserDevice {
  const factory UserDevice({
    required String id,
    required String name,

    /// Null when the record names a platform Studio does not know.
    DevicePlatform? platform,

    /// Seconds since the Unix epoch; 0 when not known.
    @Default(0) int added,
    @Default(0) int lastUsed,
    @Default(0) int passwordDueAt,
    @Default(DeviceRecordState.active) DeviceRecordState state,

    /// The device of this session.
    @Default(false) bool thisDevice,

    /// The user who removed it (the `user:` of the subject taken off).
    String? removedBy,
  }) = _UserDevice;
}

/// A device record of the gateway as a [UserDevice]. A record with no id
/// is [Invalid]: nothing can be done with it. An unknown `state` reads as
/// `active`, as the gateway's own default.
Decoded<UserDevice> userDeviceOf(GatewayDevice d) {
  if (d.id.isEmpty) {
    return const Invalid('device record', 'id', 'missing');
  }
  return Valid(
    UserDevice(
      id: d.id,
      name: d.name,
      platform: DevicePlatform.fromWire(d.platform),
      added: d.added,
      lastUsed: d.lastUsed,
      passwordDueAt: d.passwordDueAt,
      state: DeviceRecordState.fromWire(d.state) ?? .active,
      thisDevice: d.thisSession,
      removedBy: d.removedBy?.replaceFirst('user:', ''),
    ),
  );
}

/// The device records of a list that decode, newest use first.
IList<UserDevice> userDevicesOf(List<GatewayDevice> ds) => ([
  for (final d in ds)
    if (userDeviceOf(d) case Valid(:final value)) value,
]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed))).lock;
