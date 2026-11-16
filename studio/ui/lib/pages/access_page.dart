import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/action_row.dart';
import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/detail_inspector.dart';
import '../containers/fact_grid.dart';
import '../containers/page_header.dart';
import '../indicators/device_os.dart';
import '../indicators/level_badge.dart';
import '../indicators/status_pill.dart';
import '../models/disabled.dart';
import '../models/tone.dart';
import '../overlays/log_view.dart';
import '../tables/row_table.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';

/// A tab of Access.
enum AccessView {
  users,
  grants,
  audit;

  String get label => switch (this) {
    users => S.current.tabUsers,
    grants => S.current.tabGrants,
    audit => S.current.tabAudit,
  };
}

/// Where a grant comes from, by its name on the broker (the same in every
/// language).
enum GrantFrom {
  acl('acl'),
  gateway('gateway'),
  link('link');

  const GrantFrom(this.word);

  final String word;
}

/// A change of the user picked, from the inspector.
enum UserChange { roles, password, disabled, remove }

/// What a row of Access's inspector does: a change of the user, or the
/// removal of one of their devices (by its id).
sealed class AccessPick extends Equatable {
  const AccessPick();
}

/// A change of the user picked.
final class ChangeUser extends AccessPick {
  const ChangeUser(this.change);

  final UserChange change;

  @override
  List<Object?> get props => [change];
}

/// The device [id] of the user picked: removed, or forgotten once removed.
final class DropDevice extends AccessPick {
  const DropDevice(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

/// A user of the gateway.
final class UserRowVm extends Equatable {
  const UserRowVm({
    required this.name,
    this.roles = const [],
    this.devices = 0,
    this.disabled = false,
  });

  final String name;
  final List<String> roles;

  /// Devices that can log in (ADR 0050 §1.5).
  final int devices;
  final bool disabled;

  @override
  List<Object?> get props => [name, roles, devices, disabled];
}

/// The level column of a grant: an access level, or the messages and
/// flows of a rule of the router's ACL in the broker's words.
sealed class GrantLevelVm extends Equatable {
  const GrantLevelVm();

  /// What the column says.
  String get word;
}

/// A role's or a link's grant: its access level.
final class GrantAccess extends GrantLevelVm {
  const GrantAccess(this.level);

  final AccessLevel level;

  @override
  String get word => level.label;

  @override
  List<Object?> get props => [level];
}

/// A rule of the router's ACL (`put, query (ingress/egress)`).
final class GrantRule extends GrantLevelVm {
  const GrantRule(this.text);

  final String text;

  @override
  String get word => text;

  @override
  List<Object?> get props => [text];
}

/// A grant of a role or subject on a key pattern, with its level.
final class GrantRowVm extends Equatable {
  const GrantRowVm({
    required this.subject,
    required this.path,
    required this.level,
    this.from,
  });

  final String subject;
  final String path;
  final GrantLevelVm level;
  final GrantFrom? from;

  @override
  List<Object?> get props => [subject, path, level, from];
}

/// One record of the audit tail, each part as the broker wrote it.
final class AuditRowVm extends Equatable {
  const AuditRowVm({
    this.time = '',
    this.who = '',
    this.what = '',
    this.result = '',
  });

  final String time;
  final String who;
  final String what;
  final String result;

  /// `time  who  what  result`, without the parts it has not.
  String get line =>
      [time, who, what, result].where((x) => x.isNotEmpty).join('  ');

  @override
  List<Object?> get props => [time, who, what, result];
}

/// A device of the user picked: its platform, whether an administrator
/// removed it (and who), when it was last used or else added.
final class UserDeviceVm extends Equatable {
  const UserDeviceVm({
    required this.id,
    required this.name,
    required this.os,
    this.removed = false,
    this.removedBy = '',
    this.lastUsed,
    this.added,
  });

  final String id;
  final String name;
  final DeviceOs os;
  final bool removed;
  final String removedBy;
  final DateTime? lastUsed;
  final DateTime? added;

  @override
  List<Object?> get props => [
    id,
    name,
    os,
    removed,
    removedBy,
    lastUsed,
    added,
  ];
}

/// The user picked, with the grants of their roles and their devices.
final class PickedUserVm extends Equatable {
  const PickedUserVm({
    required this.user,
    this.grants = const [],
    this.devices = const [],
  });

  final UserRowVm user;
  final List<GrantRowVm> grants;
  final List<UserDeviceVm> devices;

  @override
  List<Object?> get props => [user, grants, devices];
}

/// What Access draws.
final class AccessVm extends Equatable {
  const AccessVm({
    required this.site,
    required this.tab,
    this.users = const [],
    this.grants = const [],
    this.audit = const [],
    this.picked,
    this.usersLocked = false,
    this.grantsDisabled,
  });

  final String site;
  final AccessView tab;
  final List<UserRowVm> users;
  final List<GrantRowVm> grants;

  /// Newest first.
  final List<AuditRowVm> audit;
  final PickedUserVm? picked;

  /// Only the gateway's administrators manage users.
  final bool usersLocked;

  /// What the user lacks to change grants.
  final Disabled? grantsDisabled;

  @override
  List<Object?> get props => [
    site,
    tab,
    users,
    grants,
    audit,
    picked,
    usersLocked,
    grantsDisabled,
  ];
}

/// Board *Studio · Access*: the gateway's users, the grants of roles and
/// subjects, the audit tail; the inspector of the selected user.
class AccessPage extends StatelessWidget {
  const AccessPage({
    required this.vm,
    required this.onTab,
    required this.onUser,
    required this.onAddUser,
    required this.onAddGrant,
    required this.onPick,
    super.key,
  });

  final AccessVm vm;
  final ValueChanged<AccessView> onTab;

  /// A user picked, by name.
  final ValueChanged<String> onUser;
  final VoidCallback onAddUser;
  final VoidCallback onAddGrant;

  /// A row of the inspector.
  final ValueChanged<AccessPick> onPick;

  String _state(bool disabled) =>
      disabled ? S.current.userDisabled : S.current.userActive;

  Widget _table() => switch (vm.tab) {
    AccessView.audit => SizedBox(
      height: AppSizes.auditTail,
      child: LogView(
        lines: [for (final a in vm.audit) a.line],
        empty: S.current.noAudit,
      ),
    ),
    AccessView.grants => RowTable<int>(
      columns: [
        ColumnVm(S.current.colRole, flex: 2),
        ColumnVm(S.current.colKey, flex: 4),
        ColumnVm(S.current.colLevel),
        ColumnVm(S.current.colSource),
      ],
      rows: [
        for (final (i, g) in vm.grants.indexed)
          RowVm(
            id: i,
            cells: [
              CellVm(title: g.subject, strong: true),
              CellVm(title: g.path, monospace: true),
              CellVm(title: g.level.word, monospace: true),
              CellVm(title: g.from?.word ?? ''),
            ],
          ),
      ],
      empty: S.current.noGrants,
      rowHeight: AppSizes.accessRow,
    ),
    AccessView.users => RowTable<String>(
      columns: [
        ColumnVm(S.current.colUser, flex: 2),
        ColumnVm(S.current.colRoles, flex: 3),
        ColumnVm(S.current.colDevices),
        ColumnVm(S.current.colState),
      ],
      rows: [
        for (final u in vm.users)
          RowVm(
            id: u.name,
            selected: u.name == vm.picked?.user.name,
            cells: [
              CellVm(title: u.name, strong: true),
              CellVm(title: u.roles.join(', ')),
              // Devices that can log in (ADR 0050 §1.5).
              CellVm(title: '${u.devices}', monospace: true),
              CellVm(
                title: _state(u.disabled),
                tone: u.disabled ? Tone.neutral : Tone.good,
              ),
            ],
          ),
      ],
      onTap: onUser,
      empty: S.current.noUsers,
      rowHeight: AppSizes.accessRow,
    ),
  };

  /// `Touch ID · 5 min ago`, or `… · added 3 Nov` for one never used.
  static String _deviceLine(UserDeviceVm d) => S.current.deviceLine(
    d.os.method,
    switch (d.lastUsed) {
      final t? => Formats.ago(t, nowWord: S.current.unlockAgoNow),
      null => S.current.securityAdded(
        d.added == null ? '' : Formats.shortDate(d.added!),
      ),
    },
  );

  DetailInspectorVm<AccessPick>? get _inspector {
    final p = vm.picked;
    if (vm.tab != AccessView.users || p == null) {
      return null;
    }
    final u = p.user;
    return DetailInspectorVm(
      eyebrow: S.current.gatewayUser,
      title: u.name,
      pill: StatusPillVm(
        label: _state(u.disabled),
        tone: u.disabled ? Tone.neutral : Tone.good,
      ),
      facts: [
        FactVm(label: S.current.colRoles, value: u.roles.join(', ')),
        FactVm(
          label: S.current.factSubject,
          value: 'user:${u.name}',
          mono: true,
        ),
        FactVm(
          label: S.current.factGrants,
          value: [for (final g in p.grants) '${g.level.word} ${g.path}']
              .join('\n'),
          mono: true,
        ),
      ],
      groups: [
        ActionGroupVm(
          label: S.current.groupChange,
          actions: [
            ActionRowVm(
              id: const ChangeUser(UserChange.roles),
              icon: 'action_grant',
              title: S.current.setRoles,
              description: S.current.setRolesNote,
              code: 'roles',
            ),
            ActionRowVm(
              id: const ChangeUser(UserChange.password),
              icon: 'action_key',
              title: S.current.setPassword,
              description: S.current.setPasswordNote,
              code: 'password',
            ),
            ActionRowVm(
              id: const ChangeUser(UserChange.disabled),
              icon: 'action_block',
              title: u.disabled ? S.current.enableUser : S.current.disableUser,
              description: S.current.disableUserNote,
              code: 'disabled',
              tone: u.disabled ? Tone.neutral : Tone.warn,
            ),
          ],
        ),
        // The user's devices, each with Remove (Forget once an
        // administrator removed it), ADR 0050 §1.5.
        ActionGroupVm(
          label: S.current.groupDevices,
          actions: [
            for (final d in p.devices)
              ActionRowVm(
                id: DropDevice(d.id),
                icon: 'action_trash',
                title: d.removed
                    ? [
                        d.name,
                        S.current.securityRemovedBy(d.removedBy),
                      ].join(' · ')
                    : d.name,
                description: _deviceLine(d),
                code: d.removed
                    ? S.current.securityForget
                    : S.current.securityRemove,
                tone: Tone.bad,
              ),
          ],
        ),
        ActionGroupVm(
          label: S.current.groupRemove,
          actions: [
            ActionRowVm(
              id: const ChangeUser(UserChange.remove),
              icon: 'action_trash',
              title: S.current.removeUser,
              description: S.current.removeUserNote,
              code: 'DELETE',
              tone: Tone.bad,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final grants = vm.tab == AccessView.grants;
    final reason = grants
        ? vm.grantsDisabled?.text
        : (vm.usersLocked ? S.current.adminsOnly : null);
    final body = ListView(
      padding: Insets.workspace,
      children: [
        PageHeader(
          title: S.current.accessOn(vm.site),
          subtitle: S.current.accessSubtitle,
          trailing: vm.tab == AccessView.audit
              ? null
              : Button.primary(
                  label: grants ? S.current.addGrant : S.current.addUser,
                  icon: 'ui_add',
                  disabledReason: reason,
                  onPressed: reason != null
                      ? null
                      : (grants ? onAddGrant : onAddUser),
                ),
        ),
        Gaps.underHeader,
        SegmentedTabs(
          tabs: [
            TabItemVm(
              id: AccessView.users,
              label: AccessView.users.label,
              count: '${vm.users.length}',
            ),
            TabItemVm(
              id: AccessView.grants,
              label: AccessView.grants.label,
              count: '${vm.grants.length}',
            ),
            TabItemVm(id: AccessView.audit, label: AccessView.audit.label),
          ],
          selected: vm.tab,
          onSelect: onTab,
        ),
        Gaps.md,
        _table(),
      ],
    );
    final ins = _inspector;
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(child: body),
          if (ins != null && box.maxWidth >= 1000)
            DetailInspector(vm: ins, onAction: onPick),
        ],
      ),
    );
  }
}
