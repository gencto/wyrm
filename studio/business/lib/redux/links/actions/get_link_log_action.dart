import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/links/<id>` ▸ `get_log {lines, level?, filter?}` (config) into
/// `links.log`, one line per record: `time level message`.
class GetLinkLogAction extends Action with WaitingAction {
  GetLinkLogAction(this.id, {this.lines = 200, this.level, this.filter});

  final String id;
  final int lines;
  final String? level;
  final String? filter;

  @override
  Future<AppState> reduce() async {
    final rows = await invokeAll(
      deps.wyrm,
      '${site.root}/sys/links/$id',
      'get_log',
      Value.from({
        'lines': lines,
        'level': ?level,
        'filter': ?filter,
      }),
    );
    return state.copyWith.links(log: logLines(rows).lock);
  }
}

/// The records of a `get_log` answer (one array, or a row per record).
List<String> logLines(List<Value> rows) => [
  for (final r in rows)
    for (final e in switch (r) {
      VArray(:final v) => v,
      _ => [r],
    })
      [
        str(e['time']),
        str(e['level'])?.toUpperCase(),
        str(e['message']) ?? text(e),
      ].nonNulls.join('  '),
];
