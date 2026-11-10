import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_links_action.dart';

/// `sys/quarantine` ▸ `deauthorize {link}` (config): an external link (or a
/// downstream broker) loses its rights now and its next connection waits in
/// quarantine; its tree stays.
class DeauthorizeLinkAction extends Action with WaitingAction {
  DeauthorizeLinkAction(this.id);

  @override
  Action again() => DeauthorizeLinkAction(id);

  @override
  Action reload() => RetrieveLinksAction();

  final String id;

  @override
  Future<AppState?> reduce() async {
    await invokeAll(
      deps.wyrm,
      '${site.root}/sys/quarantine',
      'deauthorize',
      Value.from({'link': id}),
    );
    return null;
  }
}
