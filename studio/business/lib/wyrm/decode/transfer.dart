import 'dart:math' as math;
import 'dart:typed_data';

import 'package:models/file_part.dart';
import 'package:models/upload_begun.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'fields.dart';

/// The answer of `restore_begin` (ADR 0028): `{upload, part_size,
/// max_part}`, as the upload's id and the size of a part to send: the
/// broker's `part_size`, never above its `max_part`. Each is required; an
/// empty id or a size below one byte is [Invalid].
Decoded<UploadBegun> uploadBegunOf(Value answer) =>
    decoding('upload begun', () {
      final f = Fields.of(answer);
      final upload = f.text('upload');
      if (upload.isEmpty) {
        throw const BadField('upload', 'empty');
      }
      final part = f.whole('part_size');
      final max = f.whole('max_part');
      if (part < 1) {
        throw const BadField('part_size', 'below one byte');
      }
      if (max < 1) {
        throw const BadField('max_part', 'below one byte');
      }
      return UploadBegun(upload: upload, partSize: math.min(part, max));
    });

/// One answer of `download_part` (ADR 0028): `{data, offset, size, eof}`.
/// The bytes, the size and `eof` are required; the part must start at
/// [offset], where it was asked for.
Decoded<FilePart> filePartOf(Value answer, int offset) =>
    decoding('file part', () {
      final f = Fields.of(answer);
      if (f.whole('offset') != offset) {
        throw const BadField('offset', 'not the offset asked for');
      }
      return FilePart(
        data: Uint8List.fromList(f.bytes('data')),
        size: f.whole('size'),
        eof: f.flag('eof'),
      );
    });

/// The value `sys/backups/<id>/sha256`: the digest as text, or null when
/// no value came. A value that is not a text is [Invalid].
Decoded<String?> backupDigestOf(Value? value) => switch (value) {
  null || VNull() => const Valid(null),
  VStr(:final v) => Valid(v),
  _ => const Invalid('backup', 'sha256', 'not a text'),
};
