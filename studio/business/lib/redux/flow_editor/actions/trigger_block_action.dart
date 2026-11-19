import 'package:async_redux/async_redux.dart';
import 'package:models/error_hint.dart';
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
      // The broker's words as they came; where it sent none, the reason
      // Studio knows (the app says it).
      throw StudioException(
        refusalOf(
          e,
          key: '$root/dataflows/$id',
          call: const .known(.trigger),
          thing: node,
          write: true,
        ).copyWith(hint: e.message.isEmpty ? triggerHintOf(e.status) : null),
      );
    }
    return null;
  }
}

/// Why the broker did not run a block, when it sent no words: the case of
/// its status Studio can name (docs/design/specs/errors.md), else null.
ErrorHint? triggerHintOf(StatusCode status) => switch (status.known) {
  Status.permissionDenied => const ErrorHint.runDenied(),
  Status.notSupported => const ErrorHint.runNotRunning(),
  Status.notFound => const ErrorHint.runNoTrigger(),
  Status.invalidParameter => const ErrorHint.runNotByHand(),
  _ => null,
};
