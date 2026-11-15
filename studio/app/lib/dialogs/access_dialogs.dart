import 'package:async_redux/async_redux.dart';
import 'package:business/redux/access/actions/remove_user_action.dart';
import 'package:business/redux/access/actions/save_user_action.dart';
import 'package:business/redux/access/actions/set_grant_action.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/remove_device_action.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/user_info.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/panel_dialog.dart';
import 'package:ui/pages/access_page.dart';
import 'package:ui/theme/sizes.dart';
import 'package:wyrm_client/wyrm_client.dart'
    show GatewayDevice, GatewayDeviceState, Perm;

import '../common/app_store.dart';
import '../common/forms.dart';

/// A field of Access's forms, by the id the form keys it with.
enum AccessField {
  name('name'),
  password('password'),
  roles('roles'),
  role('role'),
  path('path'),
  level('level');

  const AccessField(this.id);

  final String id;

  /// The text the form gave for this field, trimmed; empty for none.
  String textIn(Map<String, Object?> values) => switch (values[id]) {
    final String s => s.trim(),
    _ => '',
  };

  /// The roles the form gave for this field: its text split at commas.
  List<String> rolesIn(Map<String, Object?> values) => [
    for (final s in textIn(values).split(','))
      if (s.trim().isNotEmpty) s.trim(),
  ];
}

/// The selectors over the store's state now.
class _Sel with Selectors {
  _Sel(this.state);

  @override
  final AppState state;
}

/// A form of Access in a panel: its [fields], submitted as the one action
/// [make] builds of what was typed. The gateway names the user `user`.
Future<void> _form(
  BuildContext context,
  String title,
  List<ParamFieldVm> fields,
  ReduxAction<AppState> Function(Map<String, Object?> values) make,
) {
  final store = AppStore.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: title,
      width: AppSizes.formDialog,
      child: ActionForm(
        fields: fields,
        submit: title,
        onSubmit: (v) => sendForm(
          store.dispatchAndWait(make(v)),
          fields: {'user': AccessField.name.id},
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

ParamFieldVm _text(
  AccessField f,
  String label, {
  String? value,
  String? hint,
}) => ParamFieldVm(
  id: f.id,
  label: label,
  kind: ParamKind.text,
  value: value,
  hint: hint,
  required: true,
  onChanged: (_) {},
);

ParamFieldVm _secret(AccessField f) => ParamFieldVm(
  id: f.id,
  label: S.current.password,
  kind: ParamKind.secret,
  required: true,
  onChanged: (_) {},
);

/// `Add a user`: a name, a password and roles.
Future<void> addUser(BuildContext context) {
  final roles = _Sel(AppStore.of(context).state).access.roleNames;
  return _form(
    context,
    S.current.addUser,
    [
      _text(AccessField.name, S.current.colUser),
      _secret(AccessField.password),
      _text(AccessField.roles, S.current.colRoles, hint: roles.join(', ')),
    ],
    (v) => SaveUserAction(
      AccessField.name.textIn(v),
      password: AccessField.password.textIn(v),
      roles: AccessField.roles.rolesIn(v),
      isNew: true,
    ),
  );
}

/// `Add a grant`: a role, a key pattern and a level.
Future<void> addGrant(BuildContext context) {
  final roles = _Sel(AppStore.of(context).state).access.roleNames;
  return _form(
    context,
    S.current.addGrant,
    [
      ParamFieldVm(
        id: AccessField.role.id,
        label: S.current.colRole,
        kind: ParamKind.choice,
        choices: roles,
        required: true,
        onChanged: (_) {},
      ),
      _text(
        AccessField.path,
        S.current.colKey,
        hint: 'wy/{site}/downstream/**',
      ),
      ParamFieldVm(
        id: AccessField.level.id,
        label: S.current.colLevel,
        kind: ParamKind.choice,
        choices: [for (final p in Perm.values) p.wire],
        value: Perm.read.wire,
        required: true,
        onChanged: (_) {},
      ),
    ],
    (v) => SetGrantAction(
      AccessField.role.textIn(v),
      AccessField.path.textIn(v),
      // The choice is one of Perm's wire names.
      Perm.fromWire(AccessField.level.textIn(v)) ?? Perm.read,
    ),
  );
}

/// A row of the inspector of the user picked: a form, a confirmation or
/// the change at once, then one action.
Future<void> changeUser(BuildContext context, AccessPick pick) async {
  final s = _Sel(AppStore.of(context).state);
  final u = s.access.pickedUser;
  if (u == null) {
    return;
  }
  switch (pick) {
    case ChangeUser(:final change):
      await _change(context, u, change, s.access.roleNames);
    case DropDevice(:final id):
      final d = s.device.userDevices[u.name]
          ?.where((d) => d.id == id)
          .firstOrNull;
      if (d != null) {
        await _dropDevice(context, u, d);
      }
  }
}

Future<void> _change(
  BuildContext context,
  UserInfo u,
  UserChange change,
  List<String> roles,
) async {
  final store = AppStore.of(context);
  switch (change) {
    case UserChange.roles:
      await _form(
        context,
        S.current.setRoles,
        [
          _text(
            AccessField.roles,
            S.current.colRoles,
            value: u.roles.join(', '),
            hint: roles.join(', '),
          ),
        ],
        (v) => SaveUserAction(u.name, roles: AccessField.roles.rolesIn(v)),
      );
    case UserChange.password:
      await _form(
        context,
        S.current.setPassword,
        [_secret(AccessField.password)],
        (v) => SaveUserAction(
          u.name,
          password: AccessField.password.textIn(v),
        ),
      );
    case UserChange.disabled:
      await store.dispatchAndWait(
        SaveUserAction(u.name, disabled: !u.disabled),
      );
    case UserChange.remove:
      if (await ConfirmDialog.ask(
        context,
        title: S.current.removeUserTitle(u.name),
        message: S.current.removeUserNote,
        confirm: S.current.remove,
        cancel: S.current.cancel,
      )) {
        await store.dispatchAndWait(RemoveUserAction(u.name));
      }
  }
}

/// Remove, or Forget once an administrator removed it (ADR 0050 §1.5).
Future<void> _dropDevice(
  BuildContext context,
  UserInfo u,
  GatewayDevice d,
) async {
  final store = AppStore.of(context);
  final forget = d.state == GatewayDeviceState.removed;
  if (await ConfirmDialog.ask(
    context,
    title: forget
        ? S.current.deviceForgetTitle(d.name)
        : S.current.deviceRemoveTitle(d.name),
    message: forget
        ? S.current.deviceForgetText
        : S.current.deviceRemoveText(u.name),
    confirm: forget ? S.current.securityForget : S.current.remove,
    cancel: S.current.cancel,
  )) {
    await store.dispatchAndWait(RemoveDeviceAction(d.id, user: u.name));
  }
}
