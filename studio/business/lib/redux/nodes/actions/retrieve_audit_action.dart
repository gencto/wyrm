import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/audit_entry.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/audit_entry.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Explorer › Audit: the records of the site's `sys/audit` ▸ `tail {n}`
/// whose key is [key] or below it, newest first. The tail needs `config` on
/// `sys/audit`; the tab says so when the user lacks it.
class RetrieveAuditAction extends Action with WaitingAction {
  RetrieveAuditAction(this.key, {this.n = 500});

  @override
  Action again() => RetrieveAuditAction(key, n: n);

  final String key;
  final int n;

  @override
  Future<AppState?> reduce() async {
    final out = await read(deps.wyrm, key, n: n);
    return state.copyWith.nodes(audit: out.lock);
  }

  /// The records of `sys/audit` ▸ `tail {n}` of [key]'s site whose key is
  /// [key] or below it, newest first (also the drawer's timeline marks).
  static Future<List<AuditEntry>> read(
    WyrmApi api,
    String key, {
    int n = 500,
  }) async {
    final root = key.split('/').take(2).join('/');
    final rows = await askAll(
      api,
      '$root/sys/audit',
      'tail',
      Value.from({'n': n}),
    );
    final out = [
      for (final r in auditEntriesOf(rows))
        if (r.orWarn('audit of $key') case final e?
            when e.key == key || e.key.startsWith('$key/'))
          e,
    ]..sort((a, b) => b.time.compareTo(a.time));
    return out;
  }
}
