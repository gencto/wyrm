import 'package:freezed_annotation/freezed_annotation.dart';

import 'self_update_state.dart';

part 'broker_self_update.freezed.dart';

/// What the broker says of its own update, from the live values of `sys`
/// (ADR 0048 §2.4): `version`, `latest`, `update_state`, `update_mode`
/// and `update_last`.
@freezed
abstract class BrokerSelfUpdate with _$BrokerSelfUpdate {
  const factory BrokerSelfUpdate({
    /// What runs now; empty before it arrived.
    @Default('') String version,

    /// The release the channel offers; empty when none.
    @Default('') String latest,
    @Default(SelfUpdateState.none) SelfUpdateState state,
    @Default(SelfUpdateMode.self) SelfUpdateMode mode,

    /// `update_last`: the last update's facts.
    @Default(UpdateLast()) UpdateLast last,
  }) = _BrokerSelfUpdate;

  const BrokerSelfUpdate._();

  /// The channel offers a release other than the one that runs.
  bool get newer => latest.isNotEmpty && latest != version;

  /// The broker says anything of its update: a release offered, or an
  /// update that runs or ended.
  bool get known => latest.isNotEmpty || state.runs;
}

/// `sys/update_last` (ADR 0048 §2.4): the facts of the last update, each
/// as the broker wrote it (a number as its digits); null when absent.
@freezed
abstract class UpdateLast with _$UpdateLast {
  const factory UpdateLast({
    /// The version updated from and to.
    String? from,
    String? to,

    /// Why it rolled back.
    String? reason,

    /// Seconds the broker was down.
    String? downS,

    /// Links back after the restart, of [links], in [backS] seconds.
    String? linksBack,
    String? links,
    String? backS,

    /// Until when a roll back is offered.
    String? rollbackUntil,
  }) = _UpdateLast;
}
