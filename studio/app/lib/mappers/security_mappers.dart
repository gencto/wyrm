import 'package:ui/overlays/security_dialog.dart';
import 'package:wyrm_client/wyrm_client.dart'
    show GatewayDevice, GatewayDeviceState;

import 'device_mappers.dart';

// A device record as a row of Account › Security (studio-rules §3): which
// tag it shows is decided once, here, from the record's own state.

/// A moment given in seconds since the Unix epoch; null for 0 (not known).
DateTime? momentOf(int seconds) =>
    seconds <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

/// A use this recent is `used now` on this computer's own row.
const _usedNowS = 60;

/// A password due within this many days is tagged.
const _dueSoonDays = 7;

extension GatewayDeviceSecurityRow on GatewayDevice {
  /// This record as a row; [thisDeviceId] is this computer's device and
  /// [now] the clock.
  SecurityDeviceVm securityRow({
    required String? thisDeviceId,
    required DateTime now,
  }) {
    final own = thisSession || id == thisDeviceId;
    final nowS = now.millisecondsSinceEpoch ~/ 1000;
    final dueDays = passwordDueAt == 0
        ? null
        : ((passwordDueAt - nowS) / Duration.secondsPerDay).ceil();
    final tag = switch (state) {
      GatewayDeviceState.removed => SecurityTag.removed,
      _ when own => SecurityTag.thisDevice,
      GatewayDeviceState.signedOut => SecurityTag.signedOut,
      GatewayDeviceState.active
          when dueDays != null && dueDays <= _dueSoonDays =>
        SecurityTag.passwordDue,
      GatewayDeviceState.active => null,
    };
    return SecurityDeviceVm(
      id: id,
      os: platform.os,
      name: name,
      tag: tag,
      removedBy: removedByUser,
      dueDays: dueDays == null || dueDays < 0 ? 0 : dueDays,
      lastUsed: momentOf(lastUsed),
      usedNow: own && lastUsed > 0 && nowS - lastUsed < _usedNowS,
      added: momentOf(added),
      own: own,
    );
  }
}
