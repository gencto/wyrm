import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Approve needs one human `ptok` per request key (ADR 0005); a gateway
/// user has no key, and the gateway does not add approvals yet
/// (docs/studio.md §10 item 1). Until it does, this refuses with that
/// reason; the Assistant shows Approve disabled.
class ApproveTaskAction extends Action with NonReentrant, WaitingAction {
  ApproveTaskAction(this.id);

  final String id;

  /// Why approving from Studio is not possible yet.
  static const reason =
      'Approving needs the gateway to sign the steps for you '
      '(docs/studio.md §10 item 1). Approve with wyrm-agent for now.';

  @override
  Future<AppState?> reduce() async => throw const UserException(reason);
}
