import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Runs block [node] of the deployed flow once: `dataflows/<id>` ▸
/// `trigger {node}` (ADR 0040 §2), the `Run` button of an unbound
/// `Trigger`. [node] is the engine's id: an inner node of a custom block is
/// `<instance>/<inner>`.
///
/// The broker asks `write` on the flow and the flow's level on the block's
/// own target. A refusal is said in words: `permission_denied` comes with
/// no text.
class TriggerBlockAction extends Action with NonReentrant {
  TriggerBlockAction(this.node);

  final String node;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    final id = flowEditor.flowId;
    if (root == null || id == null || id.isEmpty) {
      return null;
    }
    try {
      await deps.wyrm
          .invoke('$root/dataflows/$id', 'trigger', Value.from({'node': node}))
          .toList();
    } on WyrmException catch (e) {
      throw UserException('Cannot run $node', reason: triggerRefusal(e));
    }
    return state.copyWith.flowEditor(message: 'ran $node');
  }
}

/// Why the broker did not run a block, in words.
String triggerRefusal(WyrmException e) => switch (e.status.known) {
  Status.permissionDenied =>
    'You may not run it: this needs write on the flow and on what the '
        'block acts on.',
  Status.notSupported => 'The flow is not running.',
  Status.notFound => 'This broker has no trigger action (it needs ADR 0040).',
  Status.invalidParameter =>
    e.message.isEmpty ? 'This block cannot be run by hand.' : e.message,
  _ => e.message.isEmpty ? e.status.name : '${e.status.name}: ${e.message}',
};
