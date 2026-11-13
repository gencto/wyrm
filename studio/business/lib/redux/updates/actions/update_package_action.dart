import 'dart:async';
import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/package_info_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../packages/actions/retrieve_packages_action.dart';

/// Updates the package of the sheet, then each package of its queue
/// (ADR 0048 §1, `docs/links.md` §5a).
///
/// An official package: `sys/packages/<name>` ▸ `update {accept,
/// restore_point, auto_rollback_s}`. A custom one, with the archive the user
/// brought ([zip]): `sys/links` ▸ `install_zip {name, zip, …}` with a link
/// that runs the package and the same three arguments.
///
/// Both answer `{success, message}` once the links restarted; the health
/// check then runs in the broker and the sheet follows `last_update`. An
/// answer without success changes nothing: when the new version asks for
/// more rights than the links have, its message lists them and the sheet
/// goes back to the review with *Accept* (the broker has no dry run of an
/// update; this answer is the review of the rights).
class UpdatePackageAction extends Action with NonReentrant, WaitingAction {
  UpdatePackageAction({this.zip, this.settle = const Duration(seconds: 2)});

  /// The archive of a custom package.
  final Uint8List? zip;

  /// How often the end of a health check is asked for between two packages
  /// of a queue.
  final Duration settle;

  @override
  Future<AppState?> reduce() async {
    final first = updates.package;
    final root = site.root;
    if (first == null || root == null) {
      return null;
    }
    final names = [first, ...updates.queue];
    final args = <String, Object?>{
      if (updates.acceptNew) 'accept': true,
      'restore_point': updates.takePoint,
      'auto_rollback_s': updates.autoRollback ? 120 : 0,
    };
    String? message;
    for (final (i, name) in names.indexed) {
      final key = '$root/sys/packages/$name';
      final before = updateReportOf(
        toDart(await readValue(deps.wyrm, '$key/last_update')),
      );
      dispatchSync(_Show(name, names.sublist(i + 1), before?.at ?? 0));
      final Value answer;
      try {
        if (zip case final bytes?) {
          final link = links.table.values
              .where((l) => l.driver == 'pkg:$name')
              .firstOrNull;
          if (link == null) {
            throw StateError('no link runs the package $name');
          }
          answer = await invokeOne(
            deps.wyrm,
            '$root/sys/links',
            'install_zip',
            valueOf({'name': link.id, 'zip': bytes, ...args}),
            name,
          );
        } else {
          answer = await invokeOne(deps.wyrm, key, 'update', valueOf(args));
        }
      } on Object {
        dispatchSync(_Review(null));
        rethrow;
      }
      message = str(answer['message']);
      if (boolean(answer['success']) == false) {
        // Nothing was installed: the broker's words stay in the review.
        return state.copyWith.updates(view: 'review', asks: message);
      }
      unawaited(dispatchAndWait(RetrievePackagesAction()));
      if (i + 1 < names.length) {
        await _settled('$key/last_update');
      }
    }
    return state.copyWith.updates(message: message);
  }

  /// Waits for the health check of the package to end (at most the longest
  /// check, 600 s, and the restart before it).
  Future<void> _settled(String key) async {
    final until = DateTime.now().add(const Duration(seconds: 700));
    while (DateTime.now().isBefore(until)) {
      final r = updateReportOf(toDart(await readValue(deps.wyrm, key)));
      if (r != null && r.result != 'checking' && r.at != updates.seenAt) {
        return;
      }
      await Future<void>.delayed(settle);
    }
  }
}

class _Show extends Action {
  _Show(this.package, this.queue, this.seenAt);

  final String package;
  final List<String> queue;
  final int seenAt;

  @override
  AppState reduce() => state.copyWith.updates(
    package: package,
    queue: queue.lock,
    view: 'follow',
    seenAt: seenAt,
    asks: null,
    message: null,
  );
}

class _Review extends Action {
  _Review(this.asks);

  final String? asks;

  @override
  AppState reduce() => state.copyWith.updates(view: 'review', asks: asks);
}
