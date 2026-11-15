import 'package:freezed_annotation/freezed_annotation.dart';

part 'requested_right.freezed.dart';

/// One right a custom package asks for (its `capabilities` and `requester`
/// grants, docs/links.md §4), as its manifest says it: what it is
/// (`network`, `store`, a level such as `read`) and the rest of it
/// (`host:443`, `16 MiB`, `on wy/{site}/downstream/modbus`).
@freezed
abstract class RequestedRight with _$RequestedRight {
  const factory RequestedRight({
    required String what,
    required String detail,
  }) = _RequestedRight;
}
