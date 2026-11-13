import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A local file the user picked, read in parts: one part is in memory at a
/// time, whatever the file's size.
final class PickedFile {
  PickedFile._(this.name, this.size, this._file, this._bytes);

  final String name;
  final int size;
  final RandomAccessFile? _file;
  final Uint8List? _bytes;

  /// `length` bytes from `offset` (fewer at the end of the file).
  Future<Uint8List> read(int offset, int length) async {
    if (_bytes case final b?) {
      final end = (offset + length).clamp(0, b.length);
      return Uint8List.sublistView(b, offset.clamp(0, end), end);
    }
    final f = _file!;
    await f.setPosition(offset);
    return f.read(length);
  }

  Future<void> close() async => _file?.close();
}

/// The system's file dialog behind [pickFile]: the path of the file the
/// user picked, or null. A live test (`integration_test/`) puts its own
/// answer here: a native dialog cannot be driven from a test.
Future<String?> Function(List<String> extensions)? filePathPicker;

/// The same for the folder dialog behind [saveInto].
Future<String?> Function(String? dialogTitle)? directoryPicker;

/// Asks for one file with one of [extensions] (any when empty). A file
/// with a path is read from disk in parts; one without (a platform that
/// hands bytes only) is read whole.
Future<PickedFile?> pickFile({List<String> extensions = const []}) async {
  if (filePathPicker case final pick?) {
    final path = await pick(extensions);
    if (path == null) {
      return null;
    }
    final file = File(path);
    return PickedFile._(
      path.split(Platform.pathSeparator).last,
      await file.length(),
      await file.open(),
      null,
    );
  }
  final f = await FilePicker.pickFile(
    type: extensions.isEmpty ? FileType.any : FileType.custom,
    allowedExtensions: extensions.isEmpty ? null : extensions,
  );
  if (f == null) {
    return null;
  }
  if (f.path case final path?) {
    final file = File(path);
    return PickedFile._(f.name, await file.length(), await file.open(), null);
  }
  final bytes = await f.readAsBytes();
  return PickedFile._(f.name, bytes.length, null, bytes);
}

/// A file being written in parts into a folder the user chose.
final class SavingFile {
  SavingFile._(this.path, this._file, this._sink);

  final String path;
  final File _file;
  final IOSink _sink;

  Future<void> write(Uint8List part) async {
    _sink.add(part);
    await _sink.flush();
  }

  Future<void> close() => _sink.close();

  /// Closes it and removes what was written.
  Future<void> discard() async {
    await _sink.close();
    if (_file.existsSync()) {
      await _file.delete();
    }
  }
}

/// Asks for a folder and opens `<folder>/<name>` in it for writing. A file
/// of that name is never replaced: the new one gets ` (2)`, ` (3)`, …
/// before its extension. Null when the user chose nothing.
Future<SavingFile?> saveInto(String name, {String? dialogTitle}) async {
  final dir = await switch (directoryPicker) {
    final pick? => pick(dialogTitle),
    null => FilePicker.getDirectoryPath(dialogTitle: dialogTitle),
  };
  if (dir == null) {
    return null;
  }
  final file = File(freeName(dir, name, (p) => File(p).existsSync()));
  return SavingFile._(file.path, file, file.openWrite());
}

/// `<dir>/<name>`, or the first `<dir>/<stem> (n)<ext>` that is not
/// [taken].
String freeName(String dir, String name, bool Function(String path) taken) {
  final sep = Platform.pathSeparator;
  final dot = name.lastIndexOf('.');
  final stem = dot <= 0 ? name : name.substring(0, dot);
  final ext = dot <= 0 ? '' : name.substring(dot);
  var path = '$dir$sep$name';
  for (var n = 2; taken(path); n++) {
    path = '$dir$sep$stem ($n)$ext';
  }
  return path;
}
