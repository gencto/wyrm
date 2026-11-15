import 'package:business/wyrm/device_keys.dart';
import 'package:models/device_tag.dart';
import 'package:ui/overlays/security_dialog.dart';

import 'device_mappers.dart';

// A device row of the state as Account › Security draws it (studio-rules
// §3): one exhaustive switch for the tag, and the row's fields as they
// are. What is computed from the record and the clock is computed in
// `business` (`deviceRowOf`, the selector `device.rowsAt`).

extension DeviceTagSecurity on DeviceTag {
  SecurityTag get security => switch (this) {
    DeviceTag.thisDevice => .thisDevice,
    DeviceTag.removed => .removed,
    DeviceTag.signedOut => .signedOut,
    DeviceTag.passwordDue => .passwordDue,
  };
}

extension DeviceRowSecurity on DeviceRow {
  SecurityDeviceVm get securityRow => SecurityDeviceVm(
    id: device.id,
    os: device.platform.os,
    name: device.name,
    tag: tag?.security,
    removedBy: removedBy,
    dueDays: dueDays,
    lastUsed: lastUsed,
    usedNow: usedNow,
    added: added,
    own: own,
  );
}
