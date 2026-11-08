import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/peer.dart';

part 'peers_state.freezed.dart';

@freezed
abstract class PeersState with _$PeersState {
  const factory PeersState({
    @Default(IMapConst({})) IMap<String, Peer> table,
    @Default(IListConst([])) IList<String> view,
    String? selectedPeer,
  }) = _PeersState;
}
