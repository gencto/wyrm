import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

/// The status line under the gateway field (docs/design/specs/login.md §3.2):
/// what the line says, as typed values; [text] says it in the language in
/// use. `label` is the gateway's label (`plant`, `127.0.0.1:8446`).
sealed class GatewayNote extends Equatable {
  const GatewayNote();

  /// `<label> · answered in <n> ms`.
  const factory GatewayNote.answered(String label, int ms) = GatewayAnswered;

  /// `No answer from <label>`.
  const factory GatewayNote.noAnswer(String label) = GatewayNoAnswer;

  /// `<site> · picked from this network`.
  const factory GatewayNote.picked(String site) = GatewayPicked;

  /// `<site> · picked from this network · standby filled in`.
  const factory GatewayNote.pickedWithStandby(String site) =
      GatewayPickedWithStandby;

  /// The field is empty: type an address or find one.
  const factory GatewayNote.typeOrFind() = GatewayTypeOrFind;

  /// The line in the language in use.
  String get text => switch (this) {
    GatewayAnswered(:final label, :final ms) => S.current.gatewayAnswered(
      label,
      ms,
    ),
    GatewayNoAnswer(:final label) => S.current.gatewayNoAnswer(label),
    GatewayPicked(:final site) => S.current.pickedFrom(site),
    GatewayPickedWithStandby(:final site) => S.current.pickedWithStandby(site),
    GatewayTypeOrFind() => S.current.typeOrFind,
  };
}

final class GatewayAnswered extends GatewayNote {
  const GatewayAnswered(this.label, this.ms);
  final String label;
  final int ms;
  @override
  List<Object?> get props => [label, ms];
}

final class GatewayNoAnswer extends GatewayNote {
  const GatewayNoAnswer(this.label);
  final String label;
  @override
  List<Object?> get props => [label];
}

final class GatewayPicked extends GatewayNote {
  const GatewayPicked(this.site);
  final String site;
  @override
  List<Object?> get props => [site];
}

final class GatewayPickedWithStandby extends GatewayNote {
  const GatewayPickedWithStandby(this.site);
  final String site;
  @override
  List<Object?> get props => [site];
}

final class GatewayTypeOrFind extends GatewayNote {
  const GatewayTypeOrFind();
  @override
  List<Object?> get props => const [];
}
