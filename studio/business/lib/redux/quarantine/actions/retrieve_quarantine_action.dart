import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/param_spec.dart';
import 'package:models/quarantine_entry.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/param_spec_mapper.dart';
import '../../../wyrm/mappers/quarantine_entry_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads `sys/quarantine` of the site: each waiting connection by its full
/// meta (kind, first seen, relays, key) and the form of its `approve`
/// action (link entries ask for driver, name and role; brokers for the key
/// and the relays).
class RetrieveQuarantineAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/sys/quarantine';
    final nodes = await call(
      'Cannot list quarantine',
      () => api.children(base),
    );
    final entries = <QuarantineEntry>[];
    final forms = <String, IList<ParamSpec>>{};
    for (final c in nodes) {
      final m = await call(
        'Cannot read ${c.name}',
        () => api.meta('$base/${c.name}'),
      );
      entries.add(quarantineEntryOf(c.name, m));
      if (m.actions?['approve'] case final a?) {
        forms[c.name] = paramSpecsOf(a).lock;
      }
    }
    return state.copyWith.quarantine(
      table: IMap.fromValues(values: entries, keyMapper: (e) => e.node),
      view: [for (final e in entries) e.node].lock,
      forms: forms.lock,
    );
  }
}
