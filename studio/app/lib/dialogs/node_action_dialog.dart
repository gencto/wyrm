import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
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

/// The one action that runs an action of a node with the [args] the form
/// gave, the names in [keep] sent even when empty.
typedef NodeRun = ReduxAction<AppState> Function(
  Map<String, Object?> args,
  Set<String> keep,
);

/// Asks for [action] of the node [key]: a form made from its parameters
/// (or a confirmation when it has none and [confirm] is set), then
/// dispatches the one action [run] makes of the answer. The node's actions
/// are read first, as they are now.
Future<void> runNodeAction(
  BuildContext context,
  String key,
  String action, {
  required NodeRun run,
  String? confirm,
}) async {
  final store = AppStore.of(context);
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
    await store.dispatchAndWait(run(const {}, const {}));
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
          store.dispatchAndWait(run(plainArgs(v), clearedNames(a.params))),
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
