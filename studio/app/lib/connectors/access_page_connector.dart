import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/access/actions/poll_access_action.dart';
import 'package:business/redux/access/actions/remove_user_action.dart';
import 'package:business/redux/access/actions/retrieve_access_action.dart';
import 'package:business/redux/access/actions/save_user_action.dart';
import 'package:business/redux/access/actions/set_grant_action.dart';
import 'package:business/redux/access/actions/set_selected_action.dart';
import 'package:business/redux/access/actions/set_shown_action.dart';
import 'package:business/redux/access/actions/set_tab_action.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:ui/buttons/action_row.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/detail_inspector.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/panel_dialog.dart';
import 'package:ui/pages/access_page.dart';
import 'package:ui/tables/row_table.dart';

import '../common/every.dart';
import '../common/forms.dart';
import '../common/tab_visibility.dart';

const _levels = ['none', 'list', 'read', 'write', 'config'];

@RoutePage()
class AccessPageConnector extends StatelessWidget {
  const AccessPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      // `/api/users` has no stream: read again every 10 s while shown.
      child: Every(
        period: const Duration(seconds: 10),
        enabled: vm.polling,
        onTick: vm.onPoll,
        child: AccessPage(
          title: S.current.accessOn(vm.site),
          subtitle: S.current.accessSubtitle,
          tabs: [
            TabItemVm(
              id: 'users',
              label: S.current.tabUsers,
              count: '${vm.userCount}',
            ),
            TabItemVm(
              id: 'grants',
              label: S.current.tabGrants,
              count: '${vm.grantCount}',
            ),
            TabItemVm(id: 'audit', label: S.current.tabAudit),
          ],
          tab: vm.tab,
          onTab: vm.onTab,
          columns: vm.tab == 'grants'
              ? [
                  ColumnVm(S.current.colRole, flex: 2),
                  ColumnVm(S.current.colKey, flex: 4),
                  ColumnVm(S.current.colLevel),
                  ColumnVm(S.current.colSource),
                ]
              : [
                  ColumnVm(S.current.colUser, flex: 2),
                  ColumnVm(S.current.colRoles, flex: 3),
                  ColumnVm(S.current.colState),
                ],
          rows: vm.rows,
          onRow: vm.onRow,
          empty: vm.empty,
          audit: vm.audit,
          addLabel: vm.tab == 'grants' ? S.current.addGrant : S.current.addUser,
          addReason: vm.addReason,
          onAdd: () =>
              vm.onAction(context, vm.tab == 'grants' ? 'grant' : 'add-user'),
          inspector: vm.inspector,
          onAction: (a) => vm.onAction(context, a),
        ),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, AccessPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final a = access;
    final home = site.home ?? '';
    final sel = a.selected;
    final u = a.users.where((x) => x.name == sel).firstOrNull;
    final sysReason = site.needs('config', '$home/sys');
    final roles = {
      for (final g in a.grants)
        if (g.source == 'gateway') g.subject,
    };
    return _Vm(
      site: site.name ?? '',
      tab: a.tab,
      userCount: a.users.length,
      grantCount: a.grants.length,
      rows: a.tab == 'grants'
          ? [
              for (final (i, g) in a.grants.indexed)
                RowVm(
                  id: 'grant:$i',
                  cells: [
                    CellVm(title: g.subject, strong: true),
                    CellVm(title: g.path, monospace: true),
                    CellVm(title: g.level, monospace: true),
                    CellVm(title: g.source),
                  ],
                ),
            ]
          : [
              for (final x in a.users)
                RowVm(
                  id: x.name,
                  selected: x.name == sel,
                  cells: [
                    CellVm(title: x.name, strong: true),
                    CellVm(title: x.roles.join(', ')),
                    CellVm(
                      title: x.disabled
                          ? S.current.userDisabled
                          : S.current.userActive,
                      tone: x.disabled ? Tone.neutral : Tone.good,
                    ),
                  ],
                ),
            ],
      empty: a.tab == 'audit'
          ? S.current.noAudit
          : (a.tab == 'grants' ? S.current.noGrants : S.current.noUsers),
      audit: a.audit.unlock,
      addReason: a.tab == 'grants'
          ? sysReason
          : (site.can('config', '$home/sys') ? null : S.current.adminsOnly),
      inspector: a.tab != 'users' || u == null
          ? null
          : DetailInspectorVm(
              eyebrow: S.current.gatewayUser,
              title: u.name,
              pill: u.disabled
                  ? StatusPillVm(
                      label: S.current.userDisabled,
                      tone: Tone.neutral,
                    )
                  : StatusPillVm(label: S.current.userActive, tone: Tone.good),
              facts: [
                FactVm(label: S.current.colRoles, value: u.roles.join(', ')),
                FactVm(
                  label: S.current.factSubject,
                  value: 'user:${u.name}',
                  mono: true,
                ),
                FactVm(
                  label: S.current.factGrants,
                  value: [
                    for (final g in a.grants)
                      if (u.roles.contains(g.subject)) '${g.level} ${g.path}',
                  ].join('\n'),
                  mono: true,
                ),
              ],
              groups: [
                ActionGroupVm(
                  label: S.current.groupChange,
                  actions: [
                    ActionRowVm(
                      id: 'roles',
                      icon: 'action_grant',
                      title: S.current.setRoles,
                      description: S.current.setRolesNote,
                      code: 'roles',
                    ),
                    ActionRowVm(
                      id: 'password',
                      icon: 'action_key',
                      title: S.current.setPassword,
                      description: S.current.setPasswordNote,
                      code: 'password',
                    ),
                    ActionRowVm(
                      id: 'disable',
                      icon: 'action_block',
                      title: u.disabled
                          ? S.current.enableUser
                          : S.current.disableUser,
                      description: S.current.disableUserNote,
                      code: 'disabled',
                      tone: u.disabled ? Tone.neutral : Tone.warn,
                    ),
                  ],
                ),
                ActionGroupVm(
                  label: S.current.groupRemove,
                  actions: [
                    ActionRowVm(
                      id: 'remove',
                      icon: 'action_trash',
                      title: S.current.removeUser,
                      description: S.current.removeUserNote,
                      code: 'DELETE',
                      tone: Tone.bad,
                    ),
                  ],
                ),
              ],
            ),
      polling: access.shown,
      onShow: () {
        dispatchSync(SetShownAction(true));
        unawaited(dispatchAndWait(RetrieveAccessAction()));
      },
      onHide: () => dispatchSync(SetShownAction(false)),
      onPoll: () => unawaited(dispatchAndWait(PollAccessAction())),
      onTab: (t) => dispatchSync(SetTabAction(t)),
      onRow: (id) {
        if (!id.startsWith('grant:')) {
          dispatchSync(SetSelectedAction(id));
        }
      },
      onAction: (context, action) async {
        final roleChoices = roles.isEmpty
            ? const ['admin', 'engineer', 'operator', 'viewer']
            : roles.toList();
        switch (action) {
          case 'add-user':
            await _form(
              context,
              S.current.addUser,
              [
                ParamFieldVm(
                  id: 'name',
                  label: S.current.colUser,
                  kind: ParamKind.text,
                  required: true,
                  onChanged: (_) {},
                ),
                ParamFieldVm(
                  id: 'password',
                  label: S.current.password,
                  kind: ParamKind.secret,
                  required: true,
                  onChanged: (_) {},
                ),
                ParamFieldVm(
                  id: 'roles',
                  label: S.current.colRoles,
                  kind: ParamKind.text,
                  required: true,
                  hint: roleChoices.join(', '),
                  onChanged: (_) {},
                ),
              ],
              (v) => SaveUserAction(
                v['name']! as String,
                password: v['password'] as String?,
                roles: _split(v['roles']),
                isNew: true,
              ),
            );
          case 'roles' when u != null:
            await _form(
              context,
              S.current.setRoles,
              [
                ParamFieldVm(
                  id: 'roles',
                  label: S.current.colRoles,
                  kind: ParamKind.text,
                  value: u.roles.join(', '),
                  required: true,
                  hint: roleChoices.join(', '),
                  onChanged: (_) {},
                ),
              ],
              (v) => SaveUserAction(u.name, roles: _split(v['roles'])),
            );
          case 'password' when u != null:
            await _form(
              context,
              S.current.setPassword,
              [
                ParamFieldVm(
                  id: 'password',
                  label: S.current.password,
                  kind: ParamKind.secret,
                  required: true,
                  onChanged: (_) {},
                ),
              ],
              (v) => SaveUserAction(u.name, password: v['password'] as String?),
            );
          case 'disable' when u != null:
            await dispatchAndWait(
              SaveUserAction(u.name, disabled: !u.disabled),
            );
          case 'remove' when u != null:
            if (await ConfirmDialog.ask(
              context,
              title: S.current.removeUserTitle(u.name),
              message: S.current.removeUserNote,
              confirm: S.current.remove,
              cancel: S.current.cancel,
            )) {
              await dispatchAndWait(RemoveUserAction(u.name));
            }
          case 'grant':
            await _form(
              context,
              S.current.addGrant,
              [
                ParamFieldVm(
                  id: 'role',
                  label: S.current.colRole,
                  kind: ParamKind.choice,
                  choices: roleChoices,
                  required: true,
                  onChanged: (_) {},
                ),
                ParamFieldVm(
                  id: 'path',
                  label: S.current.colKey,
                  kind: ParamKind.text,
                  required: true,
                  hint: 'wy/{site}/downstream/**',
                  onChanged: (_) {},
                ),
                ParamFieldVm(
                  id: 'level',
                  label: S.current.colLevel,
                  kind: ParamKind.choice,
                  choices: _levels,
                  value: 'read',
                  required: true,
                  onChanged: (_) {},
                ),
              ],
              (v) => SetGrantAction(
                v['role']! as String,
                v['path']! as String,
                v['level']! as String,
              ),
            );
        }
      },
    );
  }

  static List<String> _split(Object? v) => [
    for (final s in '${v ?? ''}'.split(','))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  Future<void> _form(
    BuildContext context,
    String title,
    List<ParamFieldVm> fields,
    ReduxAction<AppState> Function(Map<String, Object?> v) make,
  ) => showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: title,
      width: 520,
      child: ActionForm(
        fields: fields,
        submit: title,
        // The gateway calls the user's name `user`.
        onSubmit: (v) => sendForm(
          dispatchAndWait(make(v)),
          fields: const {'user': 'name'},
          onOk: () {
            if (dialog.mounted) {
              Navigator.of(dialog).pop();
            }
          },
        ),
      ),
    ),
  );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.site,
    required this.tab,
    required this.userCount,
    required this.grantCount,
    required this.rows,
    required this.empty,
    required this.audit,
    required this.addReason,
    required this.inspector,
    required this.polling,
    required this.onShow,
    required this.onHide,
    required this.onPoll,
    required this.onTab,
    required this.onRow,
    required this.onAction,
  }) : super(
         equals: [
           site,
           tab,
           userCount,
           grantCount,
           rows,
           empty,
           audit,
           addReason,
           inspector,
           polling,
         ],
       );

  final String site;
  final String tab;
  final int userCount;
  final int grantCount;
  final List<RowVm> rows;
  final String empty;
  final List<String> audit;
  final String? addReason;
  final DetailInspectorVm? inspector;

  /// The tab is shown: Access reads again every 10 s.
  final bool polling;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final VoidCallback onPoll;
  final ValueChanged<String> onTab;
  final ValueChanged<String> onRow;
  final Future<void> Function(BuildContext context, String action) onAction;
}
