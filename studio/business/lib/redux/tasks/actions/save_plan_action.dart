import 'dart:convert';
import 'dart:typed_data';

import '../../../wyrm/mappers/agent_task_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Save as a plan: the plan of task [id] in the `wyrm-agent run` format
/// (`planFile`), written through [write] into a file the screen opened
/// (a folder the user picked). [onDone] gives the file its name; [onDiscard]
/// removes it after a write error and must not throw.
///
/// A secret argument (`PlanStep.secret`) is not written: the file names
/// the steps and the arguments left out (`secrets_left_out`, also
/// `secretsLeftOut` for the screen's note).
class SavePlanAction extends Action with WaitingAction {
  SavePlanAction(
    this.id, {
    required this.write,
    required this.onDone,
    required this.onDiscard,
  });

  final String id;
  final Future<void> Function(Uint8List part) write;
  final Future<void> Function() onDone;
  final Future<void> Function() onDiscard;

  @override
  Future<AppState?> reduce() async {
    final task = tasks.table[id];
    if (task == null) {
      return null;
    }
    final file = planFile(task);
    try {
      const json = JsonEncoder.withIndent('  ', _bytes);
      await write(utf8.encode('${json.convert(file)}\n'));
      await onDone();
    } on Object {
      await onDiscard();
      rethrow;
    }
    return null;
  }

  /// Binary in a value: its length (JSON has no bytes).
  static Object? _bytes(Object? v) =>
      v is Uint8List ? '<${v.length} bytes>' : '$v';
}
