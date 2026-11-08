import 'package:models/node_detail.dart';

import '../../../wyrm/mappers/node_detail_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads the full `~meta` of listed enum points into `nodes.detail`: a list
/// (`~meta?view=list`) carries no enum names (spec 02 key 3), and a value
/// shows its name, not its index. A key read once is not read again; a
/// meta that fails leaves the point showing its number, without a dialog.
class RetrieveEnumNamesAction extends Action {
  RetrieveEnumNamesAction(this.keys);

  final Iterable<String> keys;

  @override
  Future<AppState?> reduce() async {
    final todo = {
      for (final k in keys)
        if (!nodes.detail.containsKey(k)) k,
    };
    final read = await Future.wait(todo.map(_read));
    var detail = state.nodes.detail;
    for (final d in read) {
      if (d != null && !detail.containsKey(d.key)) {
        detail = detail.add(d.key, d);
      }
    }
    return detail == state.nodes.detail
        ? null
        : state.copyWith.nodes(detail: detail);
  }

  Future<NodeDetail?> _read(String key) async {
    try {
      return nodeDetailOf(key, await deps.wyrm.meta(key));
    } on Object {
      return null;
    }
  }
}
