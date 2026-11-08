import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_node_detail_action.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/panel_dialog.dart';

import '../common/forms.dart';

/// Runs [action] of the node [key] now, with a form made from its
/// parameters (or a confirmation when it has none and [confirm] is set).
/// True when it ran.
Future<bool> runNodeAction(
  BuildContext context,
  String key,
  String action, {
  String? confirm,
}) async {
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
  await store.dispatchAndWait(RetrieveNodeDetailAction(key));
  final a = store.state.nodes.detail[key]?.actions
      .where((x) => x.name == action)
      .firstOrNull;
  if (a == null || !context.mounted) {
    return false;
  }
  if (a.params.isEmpty) {
    if (confirm != null &&
        !await ConfirmDialog.ask(
          context,
          title: a.display ?? a.name,
          message: confirm,
          confirm: a.display ?? a.name,
          cancel: S.current.cancel,
        )) {
      return false;
    }
    final st = await store.dispatchAndWait(InvokeNodeAction(key, action));
    return st.isCompletedOk;
  }
  var ran = false;
  await showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: a.display ?? a.name,
      width: 600,
      note: confirm,
      child: ActionForm(
        fields: paramFields(a.params),
        submit: a.display ?? a.name,
        onSubmit: (v) async {
          final st = await store.dispatchAndWait(
            InvokeNodeAction(key, action, plainArgs(v)),
          );
          if (st.isCompletedOk && dialog.mounted) {
            ran = true;
            Navigator.of(dialog).pop();
          }
        },
      ),
    ),
  );
  return ran;
}
