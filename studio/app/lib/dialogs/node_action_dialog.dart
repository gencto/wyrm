import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_node_detail_action.dart';
import 'package:business/wyrm/calls.dart' show clearedNames;
import 'package:business/wyrm/labels.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/panel_dialog.dart';

import '../common/app_store.dart';
import '../common/forms.dart';

/// Asks for [action] of the node [key]: a form made from its parameters
/// (or a confirmation when it has none and [confirm] is set), then runs it
/// ([InvokeNodeAction]; a refusal of the input goes back to the form, on
/// the field it names). Once it went through, [then] (when given) is
/// dispatched: the read that follows it. The node's actions are read
/// first, as they are now.
Future<void> runNodeAction(
  BuildContext context,
  String key,
  String action, {
  ReduxAction<AppState> Function()? then,
  String? confirm,
}) async {
  final store = AppStore.of(context);
  // The invoke's own status, so a refusal reaches the form; [then] only
  // after it went through.
  Future<ActionStatus> ranThen(Future<ActionStatus> sent) async {
    final ran = await sent;
    if (ran.isCompletedOk && then != null) {
      await store.dispatchAndWait(then());
    }
    return ran;
  }

  await store.dispatchAndWait(RetrieveNodeDetailAction(key));
  final a = store.state.nodes.detail[key]?.actions
      .where((x) => x.name == action)
      .firstOrNull;
  if (a == null || !context.mounted) {
    return;
  }
  if (a.params.isEmpty) {
    if (confirm != null &&
        !await ConfirmDialog.ask(
          context,
          title: labelOf(a.name, display: a.display),
          message: confirm,
          confirm: labelOf(a.name, display: a.display),
          cancel: S.current.cancel,
        )) {
      return;
    }
    await ranThen(store.dispatchAndWait(InvokeNodeAction(key, action)));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: labelOf(a.name, display: a.display),
      width: 600,
      note: confirm,
      child: ActionForm(
        fields: paramFields(a.params),
        submit: labelOf(a.name, display: a.display),
        onSubmit: (v) => sendForm(
          ranThen(
            store.dispatchAndWait(
              InvokeNodeAction(
                key,
                action,
                plainArgs(v),
                clearedNames(a.params),
              ),
            ),
          ),
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
