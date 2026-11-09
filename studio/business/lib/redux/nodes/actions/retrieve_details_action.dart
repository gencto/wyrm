import 'dart:async';
import 'dart:collection';

import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/node_detail_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads the full `~meta` of each of [keys] into `nodes.detail`, with no
/// wait barrier and no error dialog: the points table reads one per point on
/// screen for its Register, Type and Poll columns, and a point that does not
/// answer keeps its `—`. A key already read (the cache) or being read is
/// skipped unless [force] (an apply changed it).
///
/// At most [maxInFlight] `meta` calls run at once across every dispatch of
/// this action, so a device with hundreds of points does not run into the
/// gateway's responder rate limit; the rest wait in a queue.
class RetrieveDetailsAction extends Action {
  RetrieveDetailsAction(this.keys, {this.force = false});

  final List<String> keys;
  final bool force;

  static const maxInFlight = 8;
  static final _pool = _Pool(maxInFlight);

  /// Runs one `meta` call within the same limit (the selected node's own
  /// meta, `RetrieveNodeDetailAction`, waits its turn too).
  static Future<T> inTurn<T>(Future<T> Function() call) => _pool.run(call);
  static final _reading = <String>{};

  @override
  Future<AppState?> reduce() async {
    final todo = [
      for (final k in keys.toSet())
        if ((force || !nodes.detail.containsKey(k)) && !_reading.contains(k)) k,
    ];
    if (todo.isEmpty) {
      return null;
    }
    _reading.addAll(todo);
    final api = deps.wyrm;
    Future<NodeMeta?> read(String k) => _pool.run(() async {
      try {
        return await api.meta(k);
      } on WyrmException {
        return null;
      } finally {
        _reading.remove(k);
      }
    });

    final metas = await Future.wait([for (final k in todo) read(k)]);
    var detail = state.nodes.detail;
    for (final (i, m) in metas.indexed) {
      if (m != null) {
        detail = detail.add(todo[i], nodeDetailOf(todo[i], m));
      }
    }
    return state.copyWith.nodes(detail: detail);
  }
}

/// Runs at most [size] calls at once; the others wait in order. A finishing
/// call hands its slot to the next one waiting, so the count never goes
/// over [size].
final class _Pool {
  _Pool(this.size);

  final int size;
  var _running = 0;
  final _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() call) async {
    if (_running < size) {
      _running++;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    try {
      return await call();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
