import 'package:async_redux/async_redux.dart';
import 'package:models/install_source.dart';
import 'package:models/link_mode.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';

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
    if (broker == null || name == null || name.isEmpty) {
      throw const UserException('Give the link a name.');
    }
    final accept = <String, Object?>{
      if (li.acceptRights) 'accept': true,
    };
    final (String action, Map<String, Object?> args) = switch (li.path) {
      'official' => _official(name, li.item ?? '', li.mode, accept),
      _ => switch (li.source) {
        InstallSourceZip(:final bytes) => (
          'install_zip',
          {'name': name, 'zip': bytes, ...accept},
        ),
        InstallSourceWasm(:final bytes) => (
          'install_wasm',
          {'name': name, 'wasm': bytes, ...accept},
        ),
        InstallSourceUrl(:final url) => (
          'install_url',
          {'name': name, 'url': url, ...accept},
        ),
        InstallSourceGit(:final url, :final ref) => (
          'install_git',
          {'name': name, 'url': url, 'ref': ?ref, ...accept},
        ),
        _ => throw const UserException('Bring a package first.'),
      },
    };
    dispatch(_Phase('installing'));
    String? message;
    var success = false;
    try {
      final rows = await deps.wyrm
          .invoke('wy/$broker/sys/links', action, Value.from(args))
          .toList();
      final last = rows.isEmpty ? const VNull() : rows.last;
      success = boolean(last['success']) ?? last is! VNull;
      message = str(last['message']) ?? (success ? null : text(last));
    } on WyrmException catch (e) {
      success = false;
      message = '${e.status.name}: ${e.message}';
    }
    if (success) {
      dispatch(RetrieveLinksAction());
    }
    return state.copyWith.linkInstall(
      phase: success ? 'done' : 'failed',
      message: message,
      step: li.path == 'official' ? 3 : 4,
    );
  }

  static (String, Map<String, Object?>) _official(
    String name,
    String item,
    LinkMode? mode,
    Map<String, Object?> accept,
  ) {
    final (kind, code) = (
      item.substring(0, item.indexOf(':').clamp(0, item.length)),
      item.substring(item.indexOf(':') + 1),
    );
    if (kind == 'package') {
      return ('install_repo', {'name': name, 'package': code, ...accept});
    }
    return (
      'install',
      {'id': name, 'driver': code, 'mode': (mode ?? LinkMode.embedded).name},
    );
  }
}

class _Phase extends Action {
  _Phase(this.phase);

  final String phase;

  @override
  AppState reduce() => state.copyWith.linkInstall(phase: phase, message: null);
}
