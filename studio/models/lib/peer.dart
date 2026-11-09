import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'peer_kind.dart';

part 'peer.freezed.dart';

@freezed
abstract class Peer with _$Peer {
  /// A site or a device on the Sites map.
  const factory Peer({
    required String site,
    required PeerKind kind,

    /// The site it is relayed through, or the broker it hangs from.
    String? parent,
    @Default(false) bool connected,
    String? url,
    String? status,
    bool? allowConfig,
    num? valHz,
    @Default(IListConst([])) IList<String> via,

    /// Platform upstreams: mqtt, sparkplug, thingsboard, azure, aws.
    String? platform,
  }) = _Peer;
}
