import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/get_link_log_action.dart';
import 'package:business/redux/links/actions/grant_link_action.dart';
import 'package:business/redux/links/actions/retrieve_link_history_action.dart';
import 'package:business/redux/links/actions/rollback_link_params_action.dart';
import 'package:business/redux/links/actions/update_link_params_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/wyrm/decode/link_params.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/link_revision.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/log_view.dart';
import 'package:ui/overlays/panel_dialog.dart';
import 'package:ui/pages/links_data.dart';
import 'package:ui/theme/sizes.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../common/app_store.dart';
import '../common/forms.dart';
import '../mappers/rights_mappers.dart';
import 'backup_dialogs.dart';
import 'close_on_ok_action.dart';

/// The dialog [ask] names, of its link, opened over Links with its
/// [context]; [root] is the site's (`wy/<site>`).
Future<void> showLinkDialog(
  BuildContext context,
  LinkDialogAsk ask,
  String root,
) => switch (ask.dialog) {
  LinkDialog.log => showLinkLog(context, ask.link),
  LinkDialog.params => showLinkParams(context, ask.link),
  LinkDialog.history => showLinkHistory(context, ask.link),
  LinkDialog.secrets => showLinkSecrets(context, '$root/sys/links/${ask.link}'),
  LinkDialog.grant => showLinkGrant(context, ask.link, root),
  LinkDialog.backup => showBackupDialog(context, link: ask.link),
};

/// View log: the last lines of the link's own log (read as it opens, and
/// again by Refresh; each read has its own wait state).
Future<void> showLinkLog(BuildContext context, String id) {
  final store = AppStore.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => PanelDialog(
      title: S.current.logOf(id),
      width: 900,
      actions: [
        Button.quiet(
          label: S.current.refresh,
          onPressed: () => store.dispatch(GetLinkLogAction(id)),
        ),
      ],
      child: StoreConnector<AppState, (List<String>, bool)>(
        onInit: (s) => s.dispatch(GetLinkLogAction(id)),
        converter: (s) => (
          s.state.links.log.unlock,
          Waiting(s.isWaiting).linkLog,
        ),
        builder: (context, v) => SizedBox(
          height: AppSizes.logDialog,
          child: LogView(lines: v.$1, loading: v.$2, empty: S.current.logEmpty),
        ),
      ),
    ),
  );
}

/// Edit params: the parameters of the newest revision as JSON; Stage puts an
/// `update` into the staged changes.
Future<void> showLinkParams(BuildContext context, String id) async {
  final store = AppStore.of(context);
  await store.dispatchAndWait(RetrieveLinkHistoryAction(id));
  if (!context.mounted) {
    return;
  }
  final newest = store.state.links.revisions.firstOrNull;
  var text = newest?.params ?? '{}';
  // Checked as it is typed and said under the field; text that is not one
  // JSON object cannot be staged (docs/design/specs/errors.md §2:
  // validation is inline, never a dialog).
  String? problem(String json) => switch (linkParamsOf(json)) {
    ParamsObject() => null,
    ParamsNotObject() => S.current.paramsNotObject,
    ParamsNotJson(:final detail) => S.current.paramsNotJson(detail),
  };
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setState) {
        final wrong = problem(text);
        return PanelDialog(
          title: S.current.editParamsOf(id),
          width: 760,
          note: S.current.editParamsNote,
          actions: [
            Button.primary(
              label: S.current.stage,
              disabledReason: wrong,
              onPressed: wrong != null
                  ? null
                  : () => store.dispatch(
                      CloseOnOkAction(
                        UpdateLinkParamsAction(
                          id,
                          text,
                          rev: newest?.rev ?? 0,
                        ),
                        closed: () => _close(dialog),
                      ),
                    ),
            ),
          ],
          child: ParamForm(
            fields: [
              ParamFieldVm(
                id: _Field.params.key,
                label: S.current.paramsJson(newest?.rev ?? 0),
                kind: ParamKind.textarea,
                value: TextValue(text),
                error: wrong,
                onChanged: (v) => setState(() => text = v.shown ?? ''),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Params history: each revision, newest first, with Roll back.
Future<void> showLinkHistory(BuildContext context, String id) {
  final store = AppStore.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => PanelDialog(
      title: S.current.historyOf(id),
      width: 820,
      child: StoreConnector<AppState, (List<LinkRevision>, bool)>(
        onInit: (s) => s.dispatch(RetrieveLinkHistoryAction(id)),
        converter: (s) => (
          s.state.links.revisions.unlock,
          Waiting(s.isWaiting).linkHistory,
        ),
        builder: (context, v) => SizedBox(
          height: AppSizes.logDialog,
          child: v.$1.isEmpty
              ? LogView(
                  lines: const [],
                  loading: v.$2,
                  empty: S.current.noRevisions,
                )
              : ListView(
                  children: [
                    for (final (i, r) in v.$1.indexed)
                      ExpansionTile(
                        initiallyExpanded: i == 0,
                        title: Text(
                          i == 0
                              ? S.current.revisionNow(r.rev)
                              : S.current.revision(r.rev),
                        ),
                        trailing: i == 0
                            ? null
                            : Button.secondary(
                                label: S.current.rollBack,
                                size: .small,
                                onPressed: () async {
                                  if (await ConfirmDialog.ask(
                                    context,
                                    title: S.current.rollBackTo(r.rev),
                                    message: S.current.rollBackNote,
                                    confirm: S.current.rollBack,
                                    cancel: S.current.cancel,
                                    danger: false,
                                  )) {
                                    await store.dispatchAndWait(
                                      RollbackLinkParamsAction(id, r.rev),
                                    );
                                  }
                                },
                              ),
                        children: [
                          SizedBox(
                            height: AppSizes.logPane,
                            child: LogView(lines: r.params.split('\n')),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
      ),
    ),
  );
}

/// Secrets: set one (sealed, never shown again) or delete one by name.
Future<void> showLinkSecrets(BuildContext context, String key) {
  final store = AppStore.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: S.current.actSecrets,
      width: 520,
      note: S.current.secretsNote,
      child: ActionForm(
        fields: [
          ParamFieldVm(
            id: _Field.secretName.key,
            label: S.current.secretName,
            kind: ParamKind.text,
            required: true,
            hint: 'api_key',
            onChanged: (_) {},
          ),
          ParamFieldVm(
            id: _Field.secretValue.key,
            label: S.current.secretValue,
            kind: ParamKind.secret,
            onChanged: (_) {},
          ),
        ],
        submit: S.current.setSecret,
        onSubmit: (v) {
          final name = _textOf(v[_Field.secretName.key]);
          final value = _textOf(v[_Field.secretValue.key]);
          if (name == null) {
            return null;
          }
          return sendForm(
            store.dispatchAndWait(
              value == null
                  ? InvokeNodeAction(key, 'delete_secret', {'name': name})
                  : InvokeNodeAction(key, 'set_secret', {
                      'name': name,
                      'value': value.codeUnits,
                    }),
            ),
            onOk: () => _close(dialog),
          );
        },
      ),
    ),
  );
}

/// Grant access: read or write outside the link's own branch.
Future<void> showLinkGrant(BuildContext context, String id, String root) {
  final store = AppStore.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: S.current.grantFor(id),
      note: S.current.actGrantNote,
      child: ActionForm(
        fields: [
          ParamFieldVm(
            id: _Field.grantPath.key,
            label: S.current.grantPath,
            kind: ParamKind.text,
            required: true,
            hint: '$root/downstream/<link>/**',
            onChanged: (_) {},
          ),
          ParamFieldVm(
            id: _Field.grantLevel.key,
            label: S.current.grantLevel,
            kind: ParamKind.choice,
            required: true,
            value: TextValue(Perm.read.wire),
            choices: [for (final p in _grantLevels) p.wire],
            choiceLabels: {
              for (final p in _grantLevels) p.wire: p.access.label,
            },
            onChanged: (_) {},
          ),
        ],
        submit: S.current.actGrant,
        onSubmit: (v) {
          final path = _textOf(v[_Field.grantPath.key]);
          final level = switch (_textOf(v[_Field.grantLevel.key])) {
            final w? => Perm.fromWire(w),
            null => null,
          };
          if (path == null || level == null) {
            return null;
          }
          return sendForm(
            store.dispatchAndWait(
              GrantLinkAction(id, path: path, level: level),
            ),
            onOk: () => _close(dialog),
          );
        },
      ),
    ),
  );
}

/// The fields of a link's dialogs, keyed in their forms by [key].
enum _Field {
  params('params'),
  secretName('name'),
  secretValue('value'),
  grantPath('path'),
  grantLevel('level');

  const _Field(this.key);

  final String key;
}

/// The levels a grant gives (no `config`: a link never gets it).
const List<Perm> _grantLevels = [Perm.none, Perm.list, Perm.read, Perm.write];

/// What a text field of a form holds: its text, or none.
String? _textOf(Object? v) => switch (v) {
  final String s => s,
  _ => null,
};

void _close(BuildContext dialog) {
  if (dialog.mounted) {
    Navigator.of(dialog).pop();
  }
}
