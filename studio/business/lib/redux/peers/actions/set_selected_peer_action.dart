import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedPeerAction extends Action {
  SetSelectedPeerAction(this.selectedPeer);

  final String? selectedPeer;

  @override
  AppState reduce() => state.copyWith.peers(selectedPeer: selectedPeer);
}
