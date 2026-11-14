import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/broker_update/actions/close_broker_update_action.dart';
import 'package:business/redux/broker_update/actions/open_broker_update_action.dart';
import 'package:business/redux/broker_update/actions/rollback_broker_update_action.dart';
import 'package:business/redux/broker_update/actions/set_confirm_action.dart';
import 'package:business/redux/broker_update/actions/update_broker_action.dart';
import 'package:business/redux/system/actions/set_tab_action.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:ui/pages/system_page.dart';

import '../common/app_store.dart';
import '../common/broker_update_sheets.dart';
import 'backup_dialogs.dart';

class _Sel with Selectors {
  _Sel(this.state);

  @override
  final AppState state;
}

/// What the broker says of its own update, from the live values of `sys`
/// (ADR 0048 §2.4): `version`, `latest`, `update_state`, `update_last`, and
/// the attribute-like value `update_mode`.
BrokerUpdateData brokerUpdateIn(AppState state, {int lostSeconds = 0}) {
  final s = _Sel(state);
  final sys = '${s.site.root}/sys';
  Object? value(String k) => s.live.values['$sys/$k']?.value;
  String text(String k, String or) => switch (value(k)) {
    final String v when v.isNotEmpty => v,
    _ => or,
  };
  return BrokerUpdateData(
    site: s.site.viewed ?? '',
    version: text('version', ''),
    latest: text('latest', ''),
    follow: s.brokerUpdate.stage == 'follow',
    mode: text('update_mode', 'self'),
    updateState: text('update_state', 'none'),
    last: switch (value('update_last')) {
      final Map<String, Object?> m => {
        for (final e in m.entries)
          if (e.value != null) e.key: '${e.value}',
      },
      _ => const {},
    },
    connected: s.site.connected,
    lostSeconds: lostSeconds,
    confirm: s.brokerUpdate.confirm,
    busy:
        state.wait.isWaitingForType<UpdateBrokerAction>() ||
        state.wait.isWaitingForType<RollbackBrokerUpdateAction>(),
    reason: s.site.needs('config', sys),
  );
}

/// Opens the broker update dialog (boards `BrokerUpdate*`). Reached only
/// behind `Features.brokerUpdate`.
Future<void> showBrokerUpdateDialog(
  BuildContext context, {
  bool follow = false,
}) async {
  final store = AppStore.of(context)
    ..dispatchSync(OpenBrokerUpdateAction(follow: follow));
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BrokerUpdateDialog(store: store),
  );
  store.dispatchSync(CloseBrokerUpdateAction());
}

class _BrokerUpdateDialog extends StatefulWidget {
  const _BrokerUpdateDialog({required this.store});

  final Store<AppState> store;

  @override
  State<_BrokerUpdateDialog> createState() => _BrokerUpdateDialogState();
}

class _BrokerUpdateDialogState extends State<_BrokerUpdateDialog> {
  /// When the gateway was lost; the counter of the restart runs from it.
  DateTime? _lostAt;
  Timer? _tick;

  Store<AppState> get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final connected = _Sel(_store.state).site.connected;
      if (connected && _lostAt == null) {
        return;
      }
      setState(() => _lostAt = connected ? null : _lostAt ?? DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  BrokerUpdateData _data(AppState state) => brokerUpdateIn(
    state,
    lostSeconds: switch (_lostAt) {
      final t? => DateTime.now().difference(t).inSeconds,
      null => 0,
    },
  );

  void _close() => Navigator.of(context).pop();

  Future<void> _primary() async {
    final d = _data(_store.state);
    switch (d.stage) {
      case .review:
        await _store.dispatchAndWait(UpdateBrokerAction(d.latest));
      case .confirmed:
        if (await ConfirmDialog.ask(
          context,
          title: S.current.bupRollBackTitle(d.site, d.from),
          message: S.current.bupRollBackNote,
          confirm: S.current.updRollBack,
          cancel: S.current.cancel,
        )) {
          await _store.dispatchAndWait(RollbackBrokerUpdateAction());
        }
      case .rolledBack:
        _store.dispatchSync(SetTabAction(SystemPage.logTab));
        _close();
      case .external:
        // The navigator's own context outlives this dialog.
        final below = Navigator.of(context).context;
        _close();
        await showBackupDialog(below);
      case .restarting:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, AppState>(
    converter: (s) => s.state,
    builder: (context, state) => TaskSheet(
      vm: brokerUpdateSheet(_data(state)),
      dialog: true,
      width: 640,
      maxHeight: 840,
      onPrimary: () => unawaited(_primary()),
      onSecondary: _close,
      onText: (id, text) {
        if (id == 'confirm') {
          _store.dispatchSync(SetConfirmAction(text));
        }
      },
    ),
  );
}
