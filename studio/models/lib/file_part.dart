import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'file_part.freezed.dart';

@freezed
abstract class FilePart with _$FilePart {
  /// One answer of `download_part` (ADR 0028): the bytes, the size of the
  /// whole file, and whether this was the last part.
  const factory FilePart({
    required Uint8List data,
    required int size,
    required bool eof,
  }) = _FilePart;
}
