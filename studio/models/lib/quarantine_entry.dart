import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'quarantine_kind.dart';

part 'quarantine_entry.freezed.dart';

@freezed
abstract class QuarantineEntry with _$QuarantineEntry {
  /// A connection that waits in `sys/quarantine/<cn>`.
  const factory QuarantineEntry({
    required String cn,

    /// The node under `sys/quarantine` (the CN made a key segment).
    required String node,

    /// `link` or `broker`. Null: the entry was answered in a form this
    /// Studio does not read, so what waits is not known. It is listed so
    /// that it does not vanish, and is never taken for a link or a broker.
    @Default(QuarantineKind.link) QuarantineKind? kind,
    String? from,
    DateTime? firstSeen,
    @Default(IListConst([])) IList<String> via,

    /// The broker key hash to compare (kind broker).
    String? key,
    @Default(false) bool deauthorized,
  }) = _QuarantineEntry;
}
