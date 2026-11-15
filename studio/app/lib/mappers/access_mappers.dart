import 'package:business/wyrm/device_keys.dart';
import 'package:models/access_tab.dart';
import 'package:models/audit_line.dart';
import 'package:models/grant_source.dart';
import 'package:models/role_grant.dart';
import 'package:models/user_info.dart';
import 'package:ui/pages/access_page.dart';
import 'package:wyrm_client/wyrm_client.dart' show GatewayDeviceState;

import 'device_mappers.dart';

/// A tab of Access as its bar draws it.
extension AccessTabView on AccessTab {
  AccessView get view => switch (this) {
    AccessTab.users => .users,
    AccessTab.grants => .grants,
    AccessTab.audit => .audit,
  };
}

/// A tab of Access's bar as the tab it opens.
extension AccessViewTab on AccessView {
  AccessTab get tab => switch (this) {
    AccessView.users => .users,
    AccessView.grants => .grants,
    AccessView.audit => .audit,
  };
}

extension GrantSourceFrom on GrantSource {
  GrantFrom get from => switch (this) {
    GrantSource.acl => .acl,
    GrantSource.gateway => .gateway,
    GrantSource.link => .link,
  };
}

extension UserInfoRow on UserInfo {
  UserRowVm get row => UserRowVm(
    name: name,
    roles: roles.unlock,
    devices: devices,
    disabled: disabled,
  );
}

extension RoleGrantRow on RoleGrant {
  GrantRowVm get row => GrantRowVm(
    subject: subject,
    path: path,
    level: level,
    from: source?.from,
  );
}

extension AuditLineRow on AuditLine {
  AuditRowVm get row =>
      AuditRowVm(time: time, who: who, what: what, result: result);
}

/// A device of a user as Access's inspector draws it.
extension DeviceRowAccess on DeviceRow {
  UserDeviceVm get accessRow => UserDeviceVm(
    id: device.id,
    name: device.name,
    os: device.platform.os,
    removed: device.state == GatewayDeviceState.removed,
    removedBy: removedBy,
    lastUsed: lastUsed,
    added: added,
  );
}
