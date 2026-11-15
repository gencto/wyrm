import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wyrm_core/wyrm_core.dart';

part 'requested_right.freezed.dart';

/// One right a custom package asks for (its manifest's `capabilities` and
/// `requester` grants, docs/links.md §4).
@freezed
sealed class RequestedRight with _$RequestedRight {
  /// `capabilities.net`: the hosts and nets it may reach.
  const factory RequestedRight.network(List<String> hosts) = RightNetwork;

  /// `capabilities.store_mb`: its sealed store, in MiB.
  const factory RequestedRight.store(int mib) = RightStore;

  /// `capabilities.memory_mb`: its memory, in MiB.
  const factory RequestedRight.memory(int mib) = RightMemory;

  /// `capabilities.call_ms`: the time of one call, in ms.
  const factory RequestedRight.call(int ms) = RightCall;

  /// A `requester` grant: [level] on the keys of [path].
  const factory RequestedRight.grant({
    required Perm level,
    required String path,
  }) = RightGrant;
}
