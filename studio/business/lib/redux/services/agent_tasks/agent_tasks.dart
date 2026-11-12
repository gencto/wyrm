import 'dart:async';

import 'package:models/task_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';
import '../../../wyrm/mappers/agent_task_mapper.dart';
import '../../../wyrm/mappers/values.dart';

/// What [AgentTasksService] tells its listener.
abstract class AgentTasksServiceListener {
  /// Task [id] of the agent link is now in [state].
  void onTaskState(String id, TaskState state);
}

/// Follows the public `~val` of every task of one agent link
/// (`<agent>/tasks/*`: `{state}` only, ADR 0005). The full record is the
/// task's `~state` document, read on demand by the Assistant screen.
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
          _listener.onTaskState(id, taskStateOf(str(sample.v['state'])));
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
