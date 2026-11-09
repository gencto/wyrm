import 'package:models/link_mode.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Picks [item] of the official list: its first run mode, a link name not
/// taken yet, rights not accepted.
class SetItemAction extends Action {
  SetItemAction(this.item);

  final String? item;

  @override
  AppState reduce() {
    final it = linkInstall.catalog.where((c) => c.id == item).firstOrNull;
    final mode = switch (it?.modes.firstOrNull) {
      'process' => LinkMode.process,
      'external' => LinkMode.external,
      'wasm' => LinkMode.wasm,
      _ => LinkMode.embedded,
    };
    var name = it?.code.replaceAll(RegExp(r'-process$'), '') ?? '';
    final base = name;
    for (var n = 2; links.table.containsKey(name); n++) {
      name = '$base-$n';
    }
    return state.copyWith.linkInstall(
      item: item,
      mode: mode,
      name: name.isEmpty ? null : name,
      acceptRights: false,
      message: null,
      rights: null,
    );
  }
}
