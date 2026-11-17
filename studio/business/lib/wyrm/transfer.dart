import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wyrm_client/wyrm_client.dart';

import 'calls.dart';
import 'decode/transfer.dart';
import 'decode/unreadable.dart';

/// Reads `length` bytes of a local file from `offset`.
typedef PartReader = Future<Uint8List> Function(int offset, int length);

/// Takes the next part of a download, in order.
typedef PartWriter = Future<void> Function(Uint8List part);

/// The user stopped a transfer.
final class TransferCancelled implements Exception {
  const TransferCancelled();

  @override
  String toString() => 'cancelled';
}

/// What one `download_part` asks for when the caller names no size: the
/// broker's own default (4 MiB; it takes at most 16 MiB).
const int downloadPart = 4 << 20;

/// Sends a local file to the broker in parts (ADR 0048 §3, the shape of
/// ADR 0028): `[key]` ▸ `restore_begin {size}` → `{upload, part_size,
/// max_part}`, then `restore_part {upload, offset, data}` in order. The
/// parts are of the broker's `part_size`, never above its `max_part`; one
/// is in memory at a time (arguments above a WebSocket frame go by the
/// gateway's `POST /api/invoke`, which the client does by itself).
///
/// [onProgress] gets the bytes sent so far. When [cancelled] says so, or a
/// part fails, the upload is dropped on the broker (`restore_abort`) and
/// the error leaves. An answer of `restore_begin` this client cannot read
/// is refused before a byte is sent. Returns the upload's id.
Future<String> uploadParts(
  WyrmApi api,
  String key, {
  required int size,
  required PartReader read,
  void Function(int sent)? onProgress,
  bool Function()? cancelled,
}) async {
  final begun = uploadBegunOf(
    await invokeOne(api, key, 'restore_begin', valueOf({'size': size})),
  ).orRefuse(key: key, call: 'restore_begin');
  final upload = begun.upload;
  final part = begun.partSize;
  var offset = 0;
  try {
    while (offset < size) {
      if (cancelled?.call() ?? false) {
        throw const TransferCancelled();
      }
      final data = await read(offset, math.min(part, size - offset));
      if (data.isEmpty) {
        throw StateError('the file ended at $offset of $size bytes');
      }
      await invokeOne(
        api,
        key,
        'restore_part',
        valueOf({'upload': upload, 'offset': offset, 'data': data}),
      );
      offset += data.length;
      onProgress?.call(offset);
    }
  } on Object {
    await abortUpload(api, key, upload);
    rethrow;
  }
  return upload;
}

/// Drops an upload on the broker; a failure of it is not said (the broker
/// removes an upload without a new part after an hour).
Future<void> abortUpload(WyrmApi api, String key, String upload) async {
  try {
    await api
        .invoke(key, 'restore_abort', valueOf({'upload': upload}))
        .toList();
  } on Object {
    // Nothing to do: it expires by itself.
  }
}

/// Reads a file of the broker in parts: `[key]` ▸ `download_part {offset,
/// len}` → `{data, offset, size, eof}` from offset 0 until `eof`. Each part
/// goes to [write] before the next is asked for. [onProgress] gets the
/// bytes so far and the size. A part this client cannot read (no bytes,
/// no size, no `eof`, another offset) is refused: nothing of it is
/// written. Returns the bytes read.
Future<int> downloadParts(
  WyrmApi api,
  String key, {
  required PartWriter write,
  void Function(int done, int size)? onProgress,
  bool Function()? cancelled,
  int part = downloadPart,
}) async {
  var offset = 0;
  while (true) {
    if (cancelled?.call() ?? false) {
      throw const TransferCancelled();
    }
    final got = filePartOf(
      await askOne(
        api,
        key,
        'download_part',
        valueOf({'offset': offset, 'len': part}),
      ),
      offset,
    ).orRefuse(key: key, call: 'download_part');
    final data = got.data;
    await write(data);
    offset += data.length;
    onProgress?.call(offset, got.size);
    if (got.eof) {
      return offset;
    }
    if (data.isEmpty) {
      throw StateError('the broker sent an empty part before the end');
    }
  }
}
