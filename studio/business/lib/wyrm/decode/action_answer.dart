import 'package:models/action_answer.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

const _shape = 'action answer';

/// The answer of a `sys` action that says whether it did its work
/// (`install`, `install_repo`, `install_zip`, `install_url`, `install_git`,
/// `install_wasm`, `install_backup`): its last row counts.
///
/// No row, or a null one, is no success. A map is `{success, message}`;
/// without `success` the action ran. Any other answer (a text, a number)
/// is the action's own result: it ran, and says nothing more.
Decoded<ActionAnswer> actionAnswerOf(List<Value> rows) =>
    switch (rows.isEmpty ? const VNull() : rows.last) {
      VNull() => const Valid(ActionAnswer(success: false)),
      VMap(:final v) => _fromMap(v),
      _ => const Valid(ActionAnswer(success: true)),
    };

Decoded<ActionAnswer> _fromMap(Map<String, Value> m) {
  final bool success;
  switch (m['success']) {
    case null || VNull():
      success = true;
    case VBool(:final v):
      success = v;
    default:
      return const Invalid(_shape, 'success', 'not a bool');
  }
  return switch (m['message']) {
    null || VNull() => Valid(ActionAnswer(success: success)),
    VStr(:final v) => Valid(ActionAnswer(success: success, message: v)),
    _ => const Invalid(_shape, 'message', 'not a text'),
  };
}
