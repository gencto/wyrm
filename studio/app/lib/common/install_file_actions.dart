import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/link_install/actions/back_install_step_action.dart';
import 'package:business/redux/link_install/actions/choose_install_source_action.dart';
import 'package:business/redux/link_install/actions/continue_install_action.dart';
import 'package:business/redux/link_install/actions/set_source_action.dart';
import 'package:business/redux/link_install/actions/set_step_action.dart';
import 'package:models/install_path.dart';
import 'package:models/install_source.dart';
import 'package:models/install_step.dart';
import 'package:models/package_method.dart';

import '../navigation/go_action.dart';
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

  /// The passphrase, forgotten as it is handed over: it is typed on the
  /// step that installs, and goes to that one install only.
  String takePassphrase() {
    final p = passphrase;
    passphrase = '';
    return p;
  }

  /// Holds [f], closing the one held before.
  Future<void> hold(PickedFile f) async {
    await _file?.close();
    _file = f;
  }

  /// Closes the file held and forgets the passphrase (the wizard goes,
  /// or starts over).
  Future<void> close() async {
    passphrase = '';
    await _file?.close();
    _file = null;
  }
}

/// Add a link starts over on [path] (a source card, *Add another*): the
/// backup held and its passphrase are forgotten first, then every answer.
class StartInstallOverAction extends ReduxAction<AppState> {
  StartInstallOverAction(this.held, this.path);

  final HeldBackup held;
  final InstallPath path;

  @override
  Future<AppState?> reduce() async {
    await held.close();
    dispatchSync(ChooseInstallSourceAction(path));
    return null;
  }
}

/// *Back* of Add a link, or a done step of its rail ([to]): the
/// passphrase typed on the step left is forgotten (its field comes back
/// empty), then the wizard goes back: to [to], else one step, else (on its
/// first step) off the screen. One intent, one dispatch.
class InstallBackAction extends ReduxAction<AppState> with Selectors {
  InstallBackAction(this.held, {this.to});

  final HeldBackup held;
  final InstallStep? to;

  @override
  AppState? reduce() {
    held.passphrase = '';
    dispatchSync(switch (to) {
      final step? => SetStepAction(step),
      null when installStep == installSteps.first => GoAction.pop(),
      null => BackInstallStepAction(),
    });
    return null;
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
