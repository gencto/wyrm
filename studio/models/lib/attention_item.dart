import 'package:freezed_annotation/freezed_annotation.dart';

import 'attention_kind.dart';

part 'attention_item.freezed.dart';

/// One thing on a broker that needs a look, from the values the broker
/// serves under `sys`.
@freezed
abstract class AttentionItem with _$AttentionItem {
  const factory AttentionItem({
    required AttentionKind kind,

    /// What it is about: a link id, or the node under `sys/quarantine`.
    @Default('') String subject,

    /// The certificate CN of a quarantine entry (`link:field-gw`).
    @Default('') String name,

    /// Records behind (standby), sites relayed (broker), denials more
    /// (ACL).
    @Default(0) int count,

    /// Forks moved aside (standby); the ACL counter when last seen.
    @Default(0) int more,

    /// When a quarantine entry was first seen.
    DateTime? since,
  }) = _AttentionItem;
}
