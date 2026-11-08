import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'quarantine_entry.freezed.dart';

@freezed
abstract class QuarantineEntry with _$QuarantineEntry {
  /// A connection that waits in `sys/quarantine/<cn>`.
  const factory QuarantineEntry({
    required String cn,

    /// `link` or `broker`.
    @Default('link') String kind,
    String? from,
    DateTime? firstSeen,
    @Default(IListConst([])) IList<String> via,

    /// The broker key hash to compare (kind broker).
    String? key,
    @Default(false) bool deauthorized,
  }) = _QuarantineEntry;
}
