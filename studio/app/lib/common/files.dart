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
    // One read may return fewer bytes than asked for (a large file, a
    // network volume): read on until the part is whole or the file ends.
    final out = BytesBuilder(copy: false);
    while (out.length < length) {
      final chunk = await f.read(length - out.length);
      if (chunk.isEmpty) {
        break;
      }
      out.add(chunk);
    }
    return out.takeBytes();
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

/// A file being written in parts into a folder the user chose. The parts
/// go into `<path>.part`; the file gets its name only by [commit], so a
/// download that stops half way (an error, a crash) never leaves a file
/// that looks whole.
final class SavingFile {
  SavingFile._(this.path, this._part, this._sink);

  /// The name the file gets when it is whole.
  final String path;
  final File _part;
  final IOSink _sink;

  Future<void> write(Uint8List part) async {
    _sink.add(part);
    await _sink.flush();
  }

  /// Closes the file and gives it its name. Called once what arrived was
  /// checked.
  Future<void> commit() async {
    await _sink.close();
    await _part.rename(path);
  }

  /// Closes it and removes what was written. It never throws: after a
  /// write error the close fails again, and the partial file must still
  /// go.
  Future<void> discard() async {
    try {
      await _sink.close();
    } on Object {
      // The error that ended the write; said by the caller.
    }
    try {
      if (_part.existsSync()) {
        await _part.delete();
      }
    } on Object {
      // Left behind; the next download of this name removes it.
    }
  }
}

/// The names Windows keeps for devices, whatever their extension.
const _reserved = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// [name] as a file name that stays in the folder it is written into, or
/// null when it cannot be one. A name that comes from a broker is data:
/// only its last path segment counts, and `.`, `..`, an empty name, a
/// control character, a character a file system refuses, or a device name
/// is refused.
String? safeFileName(String name) {
  final last = name.split(RegExp(r'[/\\]')).last.trim();
  if (last.isEmpty ||
      last == '.' ||
      last == '..' ||
      last.length > 200 ||
      last.endsWith('.') ||
      RegExp(r'[\x00-\x1f<>:"|?*]').hasMatch(last) ||
      _reserved.contains(last.split('.').first.toLowerCase())) {
    return null;
  }
  return last;
}

/// Asks for a folder and opens a file for `<folder>/<name>` in it. [name]
/// goes through [safeFileName]; one that is refused becomes [fallback]. A
/// file of that name is never replaced: the new one gets ` (2)`, ` (3)`, …
/// before its extension. A `.part` file left by an earlier download of the
/// name is removed. Null when the user chose nothing.
Future<SavingFile?> saveInto(
  String name, {
  required String fallback,
  String? dialogTitle,
}) async {
  final dir = await switch (directoryPicker) {
    final pick? => pick(dialogTitle),
    null => FilePicker.getDirectoryPath(dialogTitle: dialogTitle),
  };
  if (dir == null) {
    return null;
  }
  final path = freeName(
    dir,
    safeFileName(name) ?? fallback,
    (p) => File(p).existsSync(),
  );
  final part = File('$path.part');
  if (part.existsSync()) {
    await part.delete();
  }
  return SavingFile._(path, part, part.openWrite());
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
