import 'package:async_redux/async_redux.dart';
import 'package:models/action_answer.dart';
import 'package:models/catalog_item.dart';
import 'package:models/error_kind.dart';
import 'package:models/install_field.dart';
import 'package:models/install_path.dart';
import 'package:models/install_phase.dart';
import 'package:models/install_source.dart';
import 'package:models/install_step.dart';
import 'package:models/link_mode.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/action_answer.dart';
import '../../../wyrm/decode/install_field.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import 'installing_action.dart';

/// Install: one call on `wy/<broker>/sys/links` (config) by the source:
/// `install {id, driver, mode}` · `install_repo {name, package}` ·
/// `install_zip {name, zip}` · `install_url {name, url}` · `install_git
/// {name, url, ref}` · `install_wasm {name, wasm}`, each package one with
/// `accept` when the rights were accepted. The broker's `{success,
/// message}` is kept verbatim: `phase` is `done` or `failed`.
class InstallLinkAction extends Action with NonReentrant, WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final li = linkInstall;
    final broker = li.broker ?? site.viewed;
    final name = li.name;
    // No name, no package: the page says so under the field and keeps
    // Install disabled (docs/design/specs/errors.md §2: validation is
    // inline, never a dialog), so there is nothing to send and nothing to
    // say here.
    if (broker == null || name == null || name.isEmpty) {
      return null;
    }
    final accept = <String, Object?>{
      if (li.acceptRights) 'accept': true,
    };
    final call = switch (li.path) {
      InstallPath.official => switch (installItem) {
        final item? => _official(name, item, li.mode, accept),
        null => null,
      },
      InstallPath.custom ||
      InstallPath.backup => _custom(name, li.source, accept),
    };
    if (call == null) {
      return null;
    }
    dispatchSync(InstallingAction());
    ActionAnswer answer;
    InstallField? refusedField;
    String? refusedSaid;
    try {
      final rows = await deps.wyrm
          .invoke('wy/$broker/sys/links', call.action, Value.from(call.args))
          .toList();
      answer =
          actionAnswerOf(rows).orWarn('${call.action} on $broker') ??
          const ActionAnswer(success: false);
    } on WyrmException catch (e) {
      answer = ActionAnswer(
        success: false,
        message: '${e.status.name}: ${e.message}',
      );
      // The parameter the broker named, as the field of the wizard that
      // holds it: *Change answers* goes back to it with the broker's words
      // under it (docs/design/specs/errors.md §3, *Back to the form*).
      final named = kindOf(e.status) == ErrorKind.input
          ? fieldOf(e.message)
          : null;
      refusedField = named == null
          ? null
          : installFieldOf(named, git: li.source is InstallSourceGit);
      if (refusedField != null) {
        refusedSaid = saidOf(e.message, named!);
      }
    }
    if (answer.success) {
      // the new link is in the tables when the result is shown
      await dispatchAndWait(RetrieveLinksAction());
    }
    return state.copyWith.linkInstall(
      phase: answer.success ? InstallPhase.done : InstallPhase.failed,
      message: answer.message,
      refusedField: refusedField,
      refusedSaid: refusedSaid,
      step: InstallStep.result,
    );
  }

  /// The call for a package the user brought; null when nothing that can
  /// be sent was brought.
  static ({String action, Map<String, Object?> args})? _custom(
    String name,
    InstallSource? source,
    Map<String, Object?> accept,
  ) => switch (source) {
    InstallSourceZip(:final bytes) => (
      action: 'install_zip',
      args: {'name': name, 'zip': bytes, ...accept},
    ),
    InstallSourceWasm(:final bytes) => (
      action: 'install_wasm',
      args: {'name': name, 'wasm': bytes, ...accept},
    ),
    InstallSourceUrl(:final url) => (
      action: 'install_url',
      args: {'name': name, 'url': url, ...accept},
    ),
    InstallSourceGit(:final url, :final ref) => (
      action: 'install_git',
      args: {'name': name, 'url': url, 'ref': ?ref, ...accept},
    ),
    InstallSourceBuiltIn() ||
    InstallSourceRepository() ||
    InstallSourceBackup() ||
    null => null,
  };

  /// A driver built into the broker (`install`) or a package of its
  /// repository (`install_repo`).
  static ({String action, Map<String, Object?> args}) _official(
    String name,
    CatalogItem item,
    LinkMode? mode,
    Map<String, Object?> accept,
  ) => item.builtIn
      ? (
          action: 'install',
          args: {
            'id': name,
            'driver': item.code,
            'mode': (mode ?? LinkMode.embedded).wire,
          },
        )
      : (
          action: 'install_repo',
          args: {'name': name, 'package': item.code, ...accept},
        );
}
