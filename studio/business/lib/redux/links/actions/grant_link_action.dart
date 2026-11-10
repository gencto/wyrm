import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_links_action.dart';

/// `sys/links/<id>` ▸ `grant {path, level}` (config): read or write outside
/// the link's own branch (ADR 0013); `none` takes a grant back.
class GrantLinkAction extends Action with WaitingAction {
  GrantLinkAction(this.id, {required this.path, required this.level});

  @override
  Action again() => GrantLinkAction(id, path: path, level: level);

  @override
  Action reload() => RetrieveLinksAction();

  final String id;
  final String path;
  final String level;

  @override
  Future<AppState?> reduce() async {
    await invokeAll(
      deps.wyrm,
      '${site.root}/sys/links/$id',
      'grant',
      Value.from({'path': path, 'level': level}),
    );
    return null;
  }
}
