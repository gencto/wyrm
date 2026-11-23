import 'package:business/redux/app_state.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_node_detail_action.dart';
import 'package:business/redux/peers/actions/add_upstream_action.dart';
import 'package:business/redux/peers/actions/authorize_broker_action.dart';
import 'package:business/redux/peers/actions/deauthorize_broker_action.dart';
import 'package:business/redux/peers/actions/issue_site_token_action.dart';
import 'package:business/redux/quarantine/actions/reject_quarantine_action.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/site_node.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/log_view.dart';
import 'package:ui/overlays/panel_dialog.dart';
import 'package:ui/theme/sizes.dart';

import '../common/app_store.dart';
import '../common/forms.dart';

/// The selectors over the store's state now.
class _Sel with Selectors, StateAlone {
  _Sel(this.state);

  @override
  final AppState state;
}

/// A field of the token form, by the id the form keys it with.
enum TokenField {
  count('count'),
  hours('hours');

  const TokenField(this.id);

  final String id;

  /// The whole number the form gave for this field, or [or].
  int numberIn(Map<String, Object?> values, int or) => switch (values[id]) {
    final num n => n.toInt(),
    _ => or,
  };
}

/// `Connect to an upstream`: the form of `sys/upstream ▸ add`, read from
/// the broker first, then one [AddUpstreamAction].
Future<void> connectUpstream(BuildContext context) async {
  final store = AppStore.of(context);
  final key = '${_Sel(store.state).site.root}/sys/upstream';
  await store.dispatchAndWait(RetrieveNodeDetailAction(key));
  // The detail just read, from the store as it is now.
  final add = store.state.nodes.detail[key]?.actions
      .where((x) => x.name == 'add')
      .firstOrNull;
  if (add == null || !context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: S.current.connectUpstream,
      width: AppSizes.wideFormDialog,
      note: S.current.connectNote(_Sel(store.state).site.viewed ?? ''),
      child: ActionForm(
        fields: paramFields(add.params),
        submit: S.current.connect,
        onSubmit: (v) => sendForm(
          store.dispatchAndWait(AddUpstreamAction(plainArgs(v))),
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

/// `Token for a site below`: its uses and hours, one
/// [IssueSiteTokenAction], then the token the broker gave, shown once.
Future<void> issueToken(BuildContext context) {
  final store = AppStore.of(context);
  final key = '${_Sel(store.state).site.root}/sys/tokens';
  var issued = false;
  return showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: S.current.tokenForBelow,
      width: AppSizes.wideFormDialog,
      note: S.current.tokenNote,
      child: StatefulBuilder(
        builder: (context, setState) {
          // The answer, from the store as it is now.
          final lines =
              store.state.nodes.results[InvokeNodeAction.resultId(key, 'add')];
          if (issued && lines != null) {
            return SizedBox(
              height: AppSizes.tokenLog,
              child: LogView(lines: lines.unlock),
            );
          }
          return ActionForm(
            fields: [
              ParamFieldVm(
                id: TokenField.count.id,
                label: S.current.tokenUses,
                kind: ParamKind.number,
                value: const NumberValue(1),
                onChanged: (_) {},
              ),
              ParamFieldVm(
                id: TokenField.hours.id,
                label: S.current.tokenHours,
                kind: ParamKind.number,
                value: const NumberValue(24),
                onChanged: (_) {},
              ),
            ],
            submit: S.current.issue,
            onSubmit: (v) => sendForm(
              store.dispatchAndWait(
                IssueSiteTokenAction(
                  count: TokenField.count.numberIn(v, 1),
                  hours: TokenField.hours.numberIn(v, 24),
                ),
              ),
              onOk: () => setState(() => issued = true),
            ),
          );
        },
      ),
    ),
  );
}

/// `Deauthorize` of the broker below picked, once the user said yes.
Future<void> deauthorizeBroker(BuildContext context) async {
  final store = AppStore.of(context);
  final name = _Sel(store.state).peers.sitePicked.name;
  if (await ConfirmDialog.ask(
    context,
    title: S.current.deauthorizeTitle(name),
    message: S.current.deauthorizeBrokerNote,
    confirm: S.current.actDeauthorize,
    cancel: S.current.cancel,
  )) {
    await store.dispatchAndWait(DeauthorizeBrokerAction(name));
  }
}

/// `Reject` of the broker waiting picked, once the user said yes.
Future<void> rejectWaiting(BuildContext context) async {
  final store = AppStore.of(context);
  final s = _Sel(store.state);
  final node = s.peers.sitePicked.name;
  if (await ConfirmDialog.ask(
    context,
    title: S.current.rejectTitle(s.quarantine.table[node]?.cn ?? node),
    message: S.current.rejectNote,
    confirm: S.current.reject,
    cancel: S.current.cancel,
  )) {
    await store.dispatchAndWait(RejectQuarantineAction(node));
  }
}

/// `Approve` of the broker waiting picked, with what its form gave; the
/// broker's refusal goes back to the form.
Future<FieldRefusal?> approveBroker(
  BuildContext context,
  Map<String, Object?> values,
) {
  final store = AppStore.of(context);
  final picked = _Sel(store.state).peers.sitePicked;
  // Only a connection waiting in quarantine has this form.
  if (picked.node != SiteNode.waiting) {
    return Future.value();
  }
  final node = picked.name;
  return sendForm(
    store.dispatchAndWait(AuthorizeBrokerAction(node, plainArgs(values))),
  );
}
