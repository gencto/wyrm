import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/install_source.dart';
import 'package:models/link_mode.dart';

import '../../../wyrm/package_check.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The Check step of a custom package: the rules of docs/links.md §4 run
/// here on a zip or a component the user picked (the broker runs them again
/// on install); a URL or a Git repository is checked by the broker alone.
class CheckPackageAction extends Action {
  CheckPackageAction({this.backup});

  /// The bytes of a link backup small enough to read here ([backupReadMax]);
  /// null for a larger one, which the broker alone checks. They are an
  /// argument of this run and are kept nowhere.
  final Uint8List? backup;

  /// The largest link backup whose manifest Studio reads itself.
  static const int backupReadMax = 64 << 20;

  @override
  Future<AppState?> reduce() async {
    final source = linkInstall.source;
    if (source == null) {
      return null;
    }
    final host = linkInstall.targets
        .where((t) => t.site == linkInstall.broker)
        .firstOrNull
        ?.host;
    final report = switch (source) {
      InstallSourceZip(:final bytes) => checkZip(bytes, host: host),
      InstallSourceWasm(:final bytes) => checkWasm(bytes),
      InstallSourceBackup(:final size) => switch (backup) {
        final bytes? => checkBackup(bytes),
        null => checkLargeBackup(size),
      },
      InstallSourceUrl(:final url) => checkRemote(url),
      InstallSourceGit(:final url) => checkRemote(url),
      _ => checkRemote('it'),
    };
    final fileName = switch (source) {
      // A backup names its link; its file name says nothing.
      InstallSourceBackup() => null,
      InstallSourceZip(:final fileName) ||
      InstallSourceWasm(:final fileName) => fileName.split('.').first,
      _ => null,
    };
    return state.copyWith.linkInstall(
      checks: report.checks.lock,
      manifest: report.manifest,
      rights: report.rights,
      name: linkInstall.name ?? report.name ?? fileName,
      mode: switch (report.kind) {
        'wasm' => LinkMode.wasm,
        'embedded' when source is InstallSourceBackup => LinkMode.embedded,
        'external' when source is InstallSourceBackup => LinkMode.external,
        _ => LinkMode.process,
      },
    );
  }
}
