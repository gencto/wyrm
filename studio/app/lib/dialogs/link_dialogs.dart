import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/get_link_log_action.dart';
import 'package:business/redux/links/actions/grant_link_action.dart';
import 'package:business/redux/links/actions/retrieve_link_history_action.dart';
import 'package:business/redux/links/actions/rollback_link_params_action.dart';
import 'package:business/redux/links/actions/update_link_params_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:models/link_revision.dart';
import 'package:ui/buttons/button.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/log_view.dart';
import 'package:ui/overlays/panel_dialog.dart';

/// View log: the last lines of the link's own log.
Future<void> showLinkLog(BuildContext context, String id) {
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
  unawaited(store.dispatchAndWait(GetLinkLogAction(id)));
  return showDialog<void>(
    context: context,
    builder: (_) => PanelDialog(
      title: S.current.logOf(id),
      width: 900,
      actions: [
        Button.quiet(
          label: S.current.refresh,
          onPressed: () =>
              unawaited(store.dispatchAndWait(GetLinkLogAction(id))),
        ),
      ],
      child: StoreConnector<AppState, (List<String>, bool)>(
        converter: (s) => (
          s.state.links.log.unlock,
          SelectLinks(s.state).isReadingLog,
        ),
        builder: (context, v) => SizedBox(
          height: 480,
          child: LogView(lines: v.$1, loading: v.$2, empty: S.current.logEmpty),
        ),
      ),
    ),
  );
}

/// Edit params: the parameters of the newest revision as JSON; Stage puts an
/// `update` into the staged changes.
Future<void> showLinkParams(BuildContext context, String id) async {
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
  await store.dispatchAndWait(RetrieveLinkHistoryAction(id));
  if (!context.mounted) {
    return;
  }
  final newest = store.state.links.revisions.firstOrNull;
  var text = newest?.params ?? '{}';
  await showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: S.current.editParamsOf(id),
      width: 760,
      note: S.current.editParamsNote,
      actions: [
        Button.primary(
          label: S.current.stage,
          onPressed: () async {
            final status = await store.dispatchAndWait(
              UpdateLinkParamsAction(id, text, from: 'rev ${newest?.rev ?? 0}'),
            );
            if (status.isCompletedOk && dialog.mounted) {
              Navigator.of(dialog).pop();
            }
          },
        ),
      ],
      child: ParamForm(
        fields: [
          ParamFieldVm(
            id: 'params',
            label: S.current.paramsJson(newest?.rev ?? 0),
            kind: ParamKind.textarea,
            value: text,
            onChanged: (v) => text = v as String? ?? '',
          ),
        ],
      ),
    ),
  );
}

/// Params history: each revision, newest first, with Roll back.
Future<void> showLinkHistory(BuildContext context, String id) {
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
  unawaited(store.dispatchAndWait(RetrieveLinkHistoryAction(id)));
  return showDialog<void>(
    context: context,
    builder: (_) => PanelDialog(
      title: S.current.historyOf(id),
      width: 820,
      child: StoreConnector<AppState, (List<LinkRevision>, bool)>(
        converter: (s) => (
          s.state.links.revisions.unlock,
          SelectLinks(s.state).isReadingHistory,
        ),
        builder: (context, v) => SizedBox(
          height: 480,
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
                            height: 260,
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
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
  return showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: S.current.actSecrets,
      width: 520,
      note: S.current.secretsNote,
      child: ActionForm(
        fields: [
          ParamFieldVm(
            id: 'name',
            label: S.current.secretName,
            kind: ParamKind.text,
            required: true,
            hint: 'api_key',
            onChanged: (_) {},
          ),
          ParamFieldVm(
            id: 'value',
            label: S.current.secretValue,
            kind: ParamKind.secret,
            onChanged: (_) {},
          ),
        ],
        submit: S.current.setSecret,
        onSubmit: (v) async {
          final name = v['name'] as String?;
          final value = v['value'] as String?;
          if (name == null) {
            return;
          }
          final status = await store.dispatchAndWait(
            value == null
                ? InvokeNodeAction(key, 'delete_secret', {'name': name})
                : InvokeNodeAction(key, 'set_secret', {
                    'name': name,
                    'value': value.codeUnits,
                  }),
          );
          if (status.isCompletedOk && dialog.mounted) {
            Navigator.of(dialog).pop();
          }
        },
      ),
    ),
  );
}

/// Grant access: read or write outside the link's own branch.
Future<void> showLinkGrant(BuildContext context, String id, String root) {
  final store = StoreProvider.backdoorInheritedWidget<AppState>(context);
  return showDialog<void>(
    context: context,
    builder: (dialog) => PanelDialog(
      title: S.current.grantFor(id),
      note: S.current.actGrantNote,
      child: ActionForm(
        fields: [
          ParamFieldVm(
            id: 'path',
            label: S.current.grantPath,
            kind: ParamKind.text,
            required: true,
            hint: '$root/downstream/<link>/**',
            onChanged: (_) {},
          ),
          ParamFieldVm(
            id: 'level',
            label: S.current.grantLevel,
            kind: ParamKind.choice,
            required: true,
            value: 'read',
            choices: const ['none', 'list', 'read', 'write'],
            onChanged: (_) {},
          ),
        ],
        submit: S.current.actGrant,
        onSubmit: (v) async {
          final status = await store.dispatchAndWait(
            GrantLinkAction(
              id,
              path: v['path']! as String,
              level: v['level']! as String,
            ),
          );
          if (status.isCompletedOk && dialog.mounted) {
            Navigator.of(dialog).pop();
          }
        },
      ),
    ),
  );
}
