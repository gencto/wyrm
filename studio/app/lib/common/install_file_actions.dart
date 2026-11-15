import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/link_install/actions/continue_install_action.dart';
import 'package:business/redux/link_install/actions/set_source_action.dart';
import 'package:models/install_source.dart';
import 'package:models/package_method.dart';

import 'files.dart';

// The steps of Add a link that need the system's file dialog: each is one
// action, started by one dispatch (studio-rules §1, §9). In `app`: the file
// pickers are the app's.

/// The link backup Add a link holds open while the wizard is on screen,
/// and the passphrase typed for it: its bytes are read from the file in
/// parts when the check and the upload need them, and are in no state.
final class HeldBackup {
  PickedFile? _file;

  /// The passphrase as it is typed; it goes to the install and nowhere
  /// else.
  var passphrase = '';

  /// The file, to read in parts; null before one is picked.
  HeldFile? get file => switch (_file) {
    final f? => HeldFile(read: f.read, size: f.size),
    null => null,
  };

  /// Holds [f], closing the one held before.
  Future<void> hold(PickedFile f) async {
    await _file?.close();
    _file = f;
  }

  /// Closes the file held, when the wizard goes.
  Future<void> close() async {
    await _file?.close();
    _file = null;
  }
}

/// *Choose a package .zip* / *Choose a .wasm*: the file of the package's
/// [method] is picked and read whole (the broker takes it in one call).
/// Nothing when the user leaves the dialog.
class PickPackageFileAction extends ReduxAction<AppState> {
  PickPackageFileAction(this.method);

  final PackageMethod method;

  @override
  Future<AppState?> reduce() async {
    final wasm = method == PackageMethod.wasm;
    final f = await pickFile(extensions: [if (wasm) 'wasm' else 'zip']);
    if (f == null) {
      return null;
    }
    try {
      final bytes = await f.read(0, f.size);
      dispatchSync(
        SetSourceAction(
          wasm
              ? InstallSource.wasm(bytes: bytes, fileName: f.name)
              : InstallSource.zip(bytes: bytes, fileName: f.name),
        ),
      );
    } finally {
      await f.close();
    }
    return null;
  }
}

/// *Choose a link backup*: a `.wyrm-link` is picked and held open in
/// [held]; only its name and size go to the store. Nothing when the user
/// leaves the dialog.
class PickLinkBackupAction extends ReduxAction<AppState> {
  PickLinkBackupAction(this.held);

  final HeldBackup held;

  @override
  Future<AppState?> reduce() async {
    final f = await pickFile(extensions: const ['wyrm-link']);
    if (f == null) {
      return null;
    }
    await held.hold(f);
    dispatchSync(
      SetSourceAction(InstallSource.backup(fileName: f.name, size: f.size)),
    );
    return null;
  }
}
