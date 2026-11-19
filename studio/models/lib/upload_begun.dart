import 'package:freezed_annotation/freezed_annotation.dart';

part 'upload_begun.freezed.dart';

@freezed
abstract class UploadBegun with _$UploadBegun {
  /// The answer of `restore_begin` (ADR 0028): the upload's id and the
  /// size of a part the broker asks for, never above its `max_part`.
  const factory UploadBegun({required String upload, required int partSize}) =
      _UploadBegun;
}
