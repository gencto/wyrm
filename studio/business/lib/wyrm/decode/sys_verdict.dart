import 'package:models/sys_verdict.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

const _shape = 'sys verdict';

/// The answer of a `sys` action that says whether it did its work
/// (`install`, `install_repo`, `install_zip`, `install_url`, `install_git`,
/// `install_wasm`, `install_backup`): its last row counts.
///
/// No row, or a null one, is no success. A map is `{success, message}`;
/// without `success` the action ran. Any other answer (a text, a number)
/// is the action's own result: it ran, and says nothing more.
///
/// Each field is read on its own, and a failure is never read as a
/// success: a `success` that is no bool is a failure, a `message` that is
/// no text is left out; each is logged with its field and [where].
SysVerdict sysVerdictOf(List<Value> rows, {required String where}) =>
    switch (rows.isEmpty ? const VNull() : rows.last) {
      VNull() => const SysVerdict(success: false),
      VMap(:final v) => _fromMap(v, where),
      _ => const SysVerdict(success: true),
    };

SysVerdict _fromMap(Map<String, Value> m, String where) {
  final success = switch (m['success']) {
    null || VNull() => true,
    VBool(:final v) => v,
    // An answer that does not say it succeeded did not, as far as Studio
    // can tell.
    _ =>
      const Invalid<bool>(_shape, 'success', 'not a bool').orWarn(where) ??
          false,
  };
  final message = switch (m['message']) {
    null || VNull() => null,
    VStr(:final v) => v,
    _ => const Invalid<String>(_shape, 'message', 'not a text').orWarn(where),
  };
  return SysVerdict(success: success, message: message);
}

/// The one answer of a `sys` action that runs at once (`update`,
/// `rollback`): `{success, message}`; no answer, or a null one, is a run
/// that said nothing.
SysVerdict sysRunOf(Value answer, {required String where}) => switch (answer) {
  VNull() => const SysVerdict(success: true),
  _ => sysVerdictOf([answer], where: where),
};
