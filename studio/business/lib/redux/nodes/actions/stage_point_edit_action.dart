import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_kind.dart';
import 'package:models/staged_change.dart';

import '../../../wyrm/failures.dart';
import '../../../wyrm/points.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Stages one parameter of the point [key]'s `edit` action (poll, register,
/// unit, writable; docs/design/specs/explorer.md §7). All the edits of one
/// point are one change, `edit:<key>`, applied as one `edit` whose arguments
/// are the action's own defaults (the point's current `cfg`, typed) with the
/// edited parameters over them, so an edit never resets a parameter it did
/// not touch. Setting a parameter back to its current value unstages it.
class StagePointEditAction extends Action {
  StagePointEditAction(this.key, this.param, this.value);

  final String key;
  final String param;
  final Object? value;

  static String idOf(String key) => 'edit:$key';

  @override
  AppState? reduce() {
    final edit = nodes.detail[key]?.actions
        .where((a) => a.name == 'edit')
        .firstOrNull;
    if (edit == null) {
      throw StudioException.said(
        ErrorKind.gone,
        'This node has no edit action.',
        key: key,
        call: 'edit',
      );
    }
    final current = {for (final p in edit.params) p.name: p.defaultValue};
    final id = idOf(key);
    final before = changes.table[id];
    final args = {...(before?.args.unlock ?? current), param: value};
    final changed = [
      for (final p in edit.params)
        if (!_same(args[p.name], current[p.name])) p.name,
    ];
    if (changed.isEmpty) {
      return state.copyWith.changes(
        table: changes.table.remove(id),
        view: changes.view.remove(id),
      );
    }
    final change = StagedChange(
      id: id,
      op: 'Edit',
      key: key,
      field: changed.map(editFieldName).join(', '),
      from: [for (final p in changed) editFieldText(p, current[p])].join(', '),
      to: [for (final p in changed) editFieldText(p, args[p])].join(', '),
      level: edit.level,
      action: 'edit',
      args: {
        for (final e in args.entries)
          if (e.value != null) e.key: e.value,
      }.lock,
    );
    return state.copyWith.changes(
      table: changes.table.add(id, change),
      view: before == null ? changes.view.add(id) : changes.view,
      message: null,
    );
  }

  static bool _same(Object? a, Object? b) =>
      a == b || (a is num && b is num && a.toDouble() == b.toDouble());
}
