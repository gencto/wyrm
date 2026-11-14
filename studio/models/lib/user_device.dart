import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_device.freezed.dart';

/// One device record of a gateway user (`GET /api/devices`,
/// `/api/users/<u>/devices`; ADR 0050 §1.5).
@freezed
abstract class UserDevice with _$UserDevice {
  const factory UserDevice({
    required String id,
    required String name,

    /// `mac`, `windows`, `ios`, `android`.
    @Default('') String platform,

    /// Seconds since the Unix epoch; 0 when not known.
    @Default(0) int added,
    @Default(0) int lastUsed,
    @Default(0) int passwordDueAt,

    /// `active`, `removed` (by an administrator) or `signed_out`.
    @Default('active') String state,

    /// The device of this session.
    @Default(false) bool thisDevice,

    /// `user:<admin>` who removed it.
    String? removedBy,
  }) = _UserDevice;
}
