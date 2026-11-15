import 'package:wyrm_client/wyrm_client.dart';

import '../mappers/values.dart';
import 'decoded.dart';

/// What `dataflows` ▸ `validate {def}` answers (spec 06): whether the
/// engine takes the definition and, when not, its own words.
final class FlowCheck {
  const FlowCheck({required this.ok, this.error});

  final bool ok;

  /// The engine's message; null when it sent none.
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is FlowCheck && other.ok == ok && other.error == error;

  @override
  int get hashCode => Object.hash(ok, error);

  @override
  String toString() => 'FlowCheck($ok, $error)';
}

/// The rows of `validate`: `{ok, error?}` in the first. A map with no
/// `ok` takes nothing; a bare text or number is the engine's message (a
/// broker before `{ok, error}`). [Invalid] when there is no row, or the
/// row is neither.
Decoded<FlowCheck> flowCheckOf(List<Value> rows) => switch (rows) {
  [] || [VNull(), ...] => const Invalid('validate answer', '', 'empty'),
  [VMap() && final r, ...] => Valid(
    FlowCheck(ok: boolean(r['ok']) ?? false, error: str(r['error'])),
  ),
  [(VStr() || VInt() || VFloat() || VBool()) && final r, ...] => Valid(
    FlowCheck(ok: false, error: text(r)),
  ),
  _ => const Invalid('validate answer', '', 'not a map'),
};
