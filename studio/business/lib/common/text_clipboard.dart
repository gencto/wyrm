import 'package:flutter/services.dart';

/// The system clipboard as text: platform I/O, reached through
/// `AppDependencies.clipboard` so that no screen calls the platform and a
/// test hands in its own.
abstract interface class TextClipboard {
  /// What the clipboard holds as text; null when it holds none or there
  /// is no clipboard here.
  Future<String?> read();

  /// Puts [text] on the clipboard; nothing happens where there is none.
  Future<void> write(String text);
}

/// The platform's clipboard (`Clipboard`). A platform without one reads
/// nothing and writes nothing: the flow editor's own clipboard still
/// pastes.
final class SystemClipboard implements TextClipboard {
  const SystemClipboard();

  @override
  Future<String?> read() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on Object {
      // No system clipboard here.
    }
  }
}
