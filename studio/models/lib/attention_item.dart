import 'package:freezed_annotation/freezed_annotation.dart';

part 'attention_item.freezed.dart';

/// One thing on a broker that needs a look, from the values the broker
/// serves under `sys`: what a card of System's attention panel is about,
/// in the order the panel lists them (specs/system.md, Attention panel).
/// Each case holds exactly what its card says and where it opens.
@freezed
sealed class AttentionItem with _$AttentionItem {
  /// `standby_lag` > 0 or `standby_forks` > 0: the records behind ([lag])
  /// and the forks moved aside ([forks]).
  const factory AttentionItem.standbyBehind({
    required int lag,
    required int forks,
  }) = AttentionStandbyBehind;

  /// A link whose `sys/links/<id>/state` is failed: its id.
  const factory AttentionItem.linkFailed({required String link}) =
      AttentionLinkFailed;

  /// A link certificate waiting under `sys/quarantine`: its [node] there,
  /// its certificate CN (`link:field-gw`) and when it was first seen
  /// (null: the broker did not say).
  const factory AttentionItem.quarantine({
    required String node,
    required String cn,
    DateTime? since,
  }) = AttentionQuarantine;

  /// A downstream broker waiting for Authorize: its [node] under
  /// `sys/quarantine`, its certificate CN and how many sites it relays.
  const factory AttentionItem.brokerWaiting({
    required String node,
    required String cn,
    required int relays,
  }) = AttentionBrokerWaiting;

  /// A connection waiting under `sys/quarantine` whose entry Studio could
  /// not read: what it is (a link, a broker) is not known.
  const factory AttentionItem.waitingNotRead({
    required String node,
    required String cn,
  }) = AttentionWaitingNotRead;

  /// `acl_denied` has grown since the screen was last shown: by how much
  /// ([grown]) and the counter when last seen ([seen]).
  const factory AttentionItem.aclGrown({
    required int grown,
    required int seen,
  }) = AttentionAclGrown;

  /// `standby_connected` = 0.
  const factory AttentionItem.noStandby() = AttentionNoStandby;
}
