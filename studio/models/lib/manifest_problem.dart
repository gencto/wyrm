import 'package:freezed_annotation/freezed_annotation.dart';

import 'manifest_fault.dart';

part 'manifest_problem.freezed.dart';

@freezed
abstract class ManifestProblem with _$ManifestProblem {
  /// Why a file a person brought (a manifest, a profile) cannot be read:
  /// the kind of fault, the field at fault by its path in the file
  /// (`link.mode`; empty for the file itself), the name the file holds
  /// there when it is one Studio does not know ([found]), and where the
  /// JSON stops being JSON ([offset], in characters).
  const factory ManifestProblem({
    required ManifestFault fault,
    @Default('') String field,
    String? found,
    int? offset,
  }) = _ManifestProblem;
}
