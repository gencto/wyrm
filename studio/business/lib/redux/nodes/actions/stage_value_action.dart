import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/change_op.dart';
import 'package:models/change_side.dart';
import 'package:models/staged_change.dart';
import 'package:models/staged_change_kind.dart';

import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/value_text.dart';
import '../../app_state.dart';
import '../../changes/actions/add_changes_action.dart';
import '../../common/action.dart';

/// Stages a `set` of the point [key] to [value] (Explorer › edit in place),
/// at the level its meta asks for (`write` or `config`). An enum value is
/// its index; the change shows its name.
class StageValueAction extends Action {
  StageValueAction(this.key, this._value, {String from = '—'})
    : was = from,
      _entered = false;

  /// The value as the inspector's form gives it: an enum by its name
  /// (staged as its index), the change's `from` the value read now.
  StageValueAction.entered(this.key, this._value) : was = null, _entered = true;

  final String key;
  final Object? _value;

  /// What the change shows it was; null: the value read now.
  final String? was;
  final bool _entered;

  List<String> get _choices {
    final d = state.nodes.detail[key]?.choices;
    return d != null && d.isNotEmpty
        ? d.unlock
        : state.nodes.table[key]?.choices.unlock ?? const [];
  }

  /// The value staged.
  Object? get value {
    final v = _value;
    if (!_entered || v is! String) {
      return v;
    }
    final i = _choices.indexOf(v);
    return i < 0 ? v : i;
  }

  /// What the change shows it was.
  String get from =>
      was ??
      switch (state.live.values[key]) {
        final v? => valueText(v.value, choices: _choices),
        null => '—',
      };

  @override
  AppState? reduce() {
    // a value whose meta names no level cannot be set: nothing is staged,
    // no level is assumed for it, and the user is told why (the app words
    // the refusal)
    final level =
        state.nodes.detail[key]?.writable ?? state.nodes.table[key]?.writable;
    if (level == null) {
      throw StudioException(notSettableOf(key));
    }
    dispatchSync(
      AddChangesAction(
        [
          StagedChange(
            id: StagedChangeKind.set.idOf(key),
            op: ChangeOp.edit,
            key: key,
            field: 'value',
            from: ChangeSide.text(from),
            to: ChangeSide.text(
              valueText(
                value,
                choices: state.nodes.detail[key]?.choices.unlock ?? const [],
              ),
            ),
            level: level,
            value: value,
          ),
        ].lock,
      ),
    );
    return null;
  }
}
