import '../../app_state.dart';
import '../../common/action.dart';

class SetAclSeenAction extends Action {
  SetAclSeenAction(this.aclSeen);

  final int? aclSeen;

  @override
  AppState reduce() => state.copyWith.system(aclSeen: aclSeen);
}
