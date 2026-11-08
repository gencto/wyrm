import 'package:freezed_annotation/freezed_annotation.dart';

part 'link_revision.freezed.dart';

/// One revision of a link's parameters (`sys/links/<id>` ▸ `history`).
@freezed
abstract class LinkRevision with _$LinkRevision {
  const factory LinkRevision({
    required int rev,

    /// The parameters as indented JSON (secrets are sealed, not here).
    required String params,
  }) = _LinkRevision;
}
