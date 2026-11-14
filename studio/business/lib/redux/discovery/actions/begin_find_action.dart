import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// A browse or a range probe starts over: the panel opens, the rows of the
/// last search go and its late answers are ignored (`scan` moves on).
class BeginFindAction extends Action {
  BeginFindAction({this.network, this.subnet, this.probing = false});

  /// A range probe, not a browse.
  final bool probing;

  /// The interface it looks on, `en0`; null when there is none.
  final String? network;

  /// The /24 around this computer's address, for the panel title and the
  /// default range.
  final String? subnet;

  @override
  AppState reduce() => state.copyWith.discovery(
    open: true,
    scanning: true,
    probing: probing,
    ended: false,
    scan: discovery.scan + 1,
    found: const IMapConst({}),
    picked: null,
    trustPending: null,
    trustRefused: null,
    network: network ?? discovery.network,
    subnet: subnet ?? discovery.subnet,
  );
}
