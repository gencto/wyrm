import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The connections of the file-store link [link]: the child nodes of
/// `downstream/<link>` that are no values (a connection is a folder with
/// `files` in it).
class RetrieveSendConnectionsAction extends Action with WaitingAction {
  RetrieveSendConnectionsAction(this.link) : super(quiet: true);

  final String link;

  @override
  Future<AppState?> reduce() async {
    final children = await listOf(
      deps.wyrm,
      '${site.root}/downstream/$link',
    );
    final names = [
      for (final c in children)
        if (c.meta.ty == null) c.name,
    ];
    return state.copyWith.backups(
      connections: names.lock,
      sendConnection:
          backups.sendConnection ?? (names.length == 1 ? names.first : null),
    );
  }
}
