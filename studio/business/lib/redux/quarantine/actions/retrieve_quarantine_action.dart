import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/param_spec.dart';
import 'package:models/quarantine_entry.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/param_spec.dart';
import '../../../wyrm/decode/peers.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/add_problem_action.dart';

/// Reads `sys/quarantine` of the site: each waiting connection by its full
/// meta (kind, first seen, relays, key) and the form of its `approve`
/// action (link entries ask for driver, name and role; brokers for the key
/// and the relays).
class RetrieveQuarantineAction extends Action with WaitingAction {
  @override
  Action again() => RetrieveQuarantineAction();

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/sys/quarantine';
    final nodes = await listOf(api, base);
    final entries = <QuarantineEntry>[];
    final unread = Unread();
    final forms = <String, IList<ParamSpec>>{};
    for (final c in nodes) {
      final m = await metaOf(api, '$base/${c.name}');
      // An entry this client cannot read is never shown as a kind it may
      // not be, and a connection that awaits a decision does not vanish:
      // it stays in the table as one that was not read (no Authorize is
      // offered for it), and the user is told of it.
      final entry = unread.take(
        quarantineEntryOf(c.name, m),
        name: c.name,
        where: '$base/${c.name}',
      );
      if (entry == null) {
        entries.add(
          QuarantineEntry(
            cn: m.displayName ?? c.name,
            node: c.name,
            // what it is, is not known
            kind: null,
          ),
        );
        continue;
      }
      entries.add(entry);
      if (m.actions?['approve'] case final a?) {
        forms[c.name] = paramSpecsOf(a).lock;
      }
    }
    if (unread.problem(key: base, call: 'list') case final p?) {
      dispatchSync(AddProblemAction(p));
    }
    return state.copyWith.quarantine(
      table: IMap.fromValues(values: entries, keyMapper: (e) => e.node),
      view: [for (final e in entries) e.node].lock,
      forms: forms.lock,
    );
  }
}
