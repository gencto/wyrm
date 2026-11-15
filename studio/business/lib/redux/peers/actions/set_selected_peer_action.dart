import 'package:models/site_pick.dart';

import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedPeerAction extends Action {
  SetSelectedPeerAction(this.selectedPeer);

  final SitePick? selectedPeer;

  @override
  AppState reduce() => state.copyWith.peers(selectedPeer: selectedPeer);
}
