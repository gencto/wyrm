import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'quarantine_entry.freezed.dart';

/// A connection that waits in `sys/quarantine/<cn>`: a link's certificate,
/// a downstream broker asking for Authorize, or an entry answered in a
/// form this Studio does not read. Each case holds what its kind has.
@freezed
sealed class QuarantineEntry with _$QuarantineEntry {
  const QuarantineEntry._();

  /// A link's certificate: where it connects from, when it was first
  /// seen, and whether Deauthorize holds it back.
  const factory QuarantineEntry.link({
    required String cn,

    /// The node under `sys/quarantine` (the CN made a key segment).
    required String node,
    String? from,
    DateTime? firstSeen,
    @Default(false) bool deauthorized,
  }) = QuarantineLink;

  /// A downstream broker: as a link, with the sites it relays ([via]) and
  /// the key hash to compare ([key]).
  const factory QuarantineEntry.broker({
    required String cn,
    required String node,
    String? from,
    DateTime? firstSeen,
    @Default(IListConst([])) IList<String> via,
    String? key,
    @Default(false) bool deauthorized,
  }) = QuarantineBroker;

  /// An entry answered in a form this Studio does not read: what waits is
  /// not known. It is listed so that it does not vanish, and is never
  /// taken for a link or a broker.
  const factory QuarantineEntry.notRead({
    required String cn,
    required String node,
  }) = QuarantineNotRead;

  /// Held back by Deauthorize: it does not wait. One that was not read is
  /// not known to be held.
  bool get held => switch (this) {
    QuarantineLink(:final deauthorized) ||
    QuarantineBroker(:final deauthorized) => deauthorized,
    QuarantineNotRead() => false,
  };
}
