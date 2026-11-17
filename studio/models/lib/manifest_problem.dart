import 'package:freezed_annotation/freezed_annotation.dart';

import 'manifest_fault.dart';

part 'manifest_problem.freezed.dart';

@freezed
abstract class ManifestProblem with _$ManifestProblem {
  /// Why a manifest cannot be read: the kind of fault, the field at fault
  /// by its path in the file (`link.mode`; empty for the file itself),
  /// and what the file holds there, when that helps (an unknown name, a
  /// parser's own words).
  const factory ManifestProblem({
    required ManifestFault fault,
    @Default('') String field,
    String? found,
  }) = _ManifestProblem;
}
