import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Runs block [node] of the deployed flow once: `dataflows/<id>` ▸
/// `trigger {node}` (ADR 0040 §2), the `Run` button of an unbound
/// `Trigger` of a command block or a reader (ADR 0044 §4). [node] is the
/// engine's id: an inner node of a custom block is `<instance>/<inner>`.
///
/// The broker asks `write` on the flow; for a command, the flow's level on
/// the block's own target; for a reader, read on its key and its scope; and
/// for every `set` and `invoke` downstream of the block, the flow's level
/// on that block's target. A refusal shows the broker's words as they came
/// (`p1 (downstream of r): …: the caller does not hold write on it`);
/// Studio says it in its own words only when the broker sent none.
class TriggerBlockAction extends Action with NonReentrant {
  TriggerBlockAction(this.node);

  @override
  Action again() => TriggerBlockAction(node);

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
      // The status stays as data; Studio adds its sentence only where the
      // broker sent none.
      throw StudioException.refused(
        WyrmException(e.status, triggerRefusal(e)),
        key: '$root/dataflows/$id',
        call: 'trigger',
        thing: node,
        write: true,
      );
    }
    return state.copyWith.flowEditor(message: 'ran $node');
  }
}

/// Why the broker did not run a block: its own message, else a sentence
/// for the status (docs/design/specs/errors.md: the broker's message is
/// shown as it came).
String triggerRefusal(WyrmException e) => e.message.isNotEmpty
    ? e.message
    : switch (e.status.known) {
        Status.permissionDenied =>
          'You may not run it: this needs write on the flow, and the rights '
              'of what the block and the blocks after it act on.',
        Status.notSupported => 'The flow is not running.',
        Status.notFound =>
          'This broker has no trigger action (it needs ADR 0040).',
        Status.invalidParameter => 'This block cannot be run by hand.',
        _ => '',
      };
