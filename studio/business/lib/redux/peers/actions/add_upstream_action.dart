import 'dart:async';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_peers_action.dart';

/// `sys/upstream` ▸ `add {name, url, ca, token?, enabled?, allow_config?}`
/// (config): this broker dials out to the upstream and asks it to authorize
/// it there (ADR 0015).
class AddUpstreamAction extends Action with WaitingAction {
  AddUpstreamAction(this.args);

  @override
  Action again() => AddUpstreamAction(args);

  @override
  Action reload() => RetrievePeersAction();

  final Map<String, Object?> args;

  @override
  Future<AppState?> reduce() async {
    final rows = await invokeAll(
      deps.wyrm,
      '${site.root}/sys/upstream',
      'add',
      valueOf({
        for (final e in args.entries)
          if (e.value != null && e.value != '') e.key: e.value,
      }),
    );
    for (final r in rows) {
      requireSuccess(
        r,
        '${site.root}/sys/upstream',
        'add',
        thing: switch (args['name']) {
          final String n => n,
          _ => null,
        },
      );
    }
    return null;
  }

  @override
  void after() {
    super.after();
    unawaited(dispatchAndWait(RetrievePeersAction()));
  }
}
