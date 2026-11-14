import 'dart:async';

import 'package:models/task_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';
import '../../../wyrm/mappers/agent_task_mapper.dart';
import '../../../wyrm/mappers/values.dart';

/// What [AgentTasksService] tells its listener.
abstract class AgentTasksServiceListener {
  /// Task [id] of the agent link is now in [state]; its run is at step
  /// [step] and the latest step that ended is [finished] (both 0 before a
  /// run). [suggestions] is how many the model offers (their texts are in
  /// the record), [reviewing] says the model reads why the run stopped,
  /// [replacedBy] names the task that took this one's place.
  void onTaskState(
    String id,
    TaskState state, {
    int step = 0,
    int finished = 0,
    int suggestions = 0,
    bool reviewing = false,
    String? replacedBy,
  });
}

/// Follows the public `~val` of every task of one agent link
/// (`<agent>/tasks/*`: `{state, step, of, last: {n, ok, result},
/// suggestions?, reviewing?, replaced_by?}`, numbers, fixed words and task
/// ids only, ADR 0049 §7 and its amendment). The full record, with the text of
/// each step's result, is the task's `~state` document, read by the
/// Assistant screen on each change.
class AgentTasksService extends DisposableServiceInterface {
  AgentTasksService({required this._listener});

  final AgentTasksServiceListener _listener;
  WyrmApi? _api;
  StreamSubscription<ValEvent>? _sub;
  String? _agent;

  /// The agent link followed now (`wy/<site>/downstream/<agent>`), if any.
  String? get agent => _agent;

  /// Uses [api]; follows [agent] when it is given.
  void attach(WyrmApi api, {String? agent}) {
    _api = api;
    follow(agent);
  }

  /// Follows the tasks of [agent] (a full link key), or none for null.
  void follow(String? agent) {
    if (agent == _agent && _sub != null) {
      return;
    }
    unawaited(_sub?.cancel());
    _sub = null;
    _agent = agent;
    final api = _api;
    if (api == null || agent == null) {
      return;
    }
    final prefix = '$agent/tasks/';
    _sub = api.subscribe('$prefix*').listen(
      (e) {
        if (e
            case ValSample(
              :final key,
              :final sample,
            )
            when key.startsWith(prefix)) {
          final id = key.substring(prefix.length);
          _listener.onTaskState(
            id,
            taskStateOf(str(sample.v['state'])),
            step: integer(sample.v['step']) ?? 0,
            finished: integer(sample.v['last']?['n']) ?? 0,
            suggestions: suggestionCount(sample.v),
            reviewing: isReviewing(sample.v),
            replacedBy: replacedBy(sample.v),
          );
        }
      },
      onError: (Object e) => logger.fine('tasks of $agent: $e'),
    );
  }

  /// Stops following and forgets the session.
  void detach() {
    unawaited(_sub?.cancel());
    _sub = null;
    _api = null;
    _agent = null;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    detach();
  }
}
