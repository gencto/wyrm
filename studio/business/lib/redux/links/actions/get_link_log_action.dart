import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/log_lines.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_links_action.dart';

/// `sys/links/<id>` ▸ `get_log {lines, level?, filter?}` (config) into
/// `links.log`, one line per record: `time level message`.
class GetLinkLogAction extends Action with WaitingAction {
  GetLinkLogAction(this.id, {this.lines = 200, this.level, this.filter});

  @override
  Action again() =>
      GetLinkLogAction(id, lines: lines, level: level, filter: filter);

  @override
  Action reload() => RetrieveLinksAction();

  final String id;
  final int lines;
  final String? level;
  final String? filter;

  @override
  Future<AppState> reduce() async {
    final rows = await askAll(
      deps.wyrm,
      '${site.root}/sys/links/$id',
      'get_log',
      Value.from({
        'lines': lines,
        'level': ?level,
        'filter': ?filter,
      }),
    );
    final key = '${site.root}/sys/links/$id';
    return state.copyWith.links(
      log: [
        for (final l in logLinesOf(rows).orRefuse(
          key: key,
          call: 'get_log',
          thing: id,
        ))
          [
            if (l.time.isNotEmpty) l.time,
            ?l.level?.wire.toUpperCase(),
            l.message,
          ].join('  '),
      ].lock,
    );
  }
}
