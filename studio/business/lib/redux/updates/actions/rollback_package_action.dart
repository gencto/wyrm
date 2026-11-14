import 'dart:async';

import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/package_info_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../packages/actions/retrieve_packages_action.dart';

/// `sys/packages/<name>` ▸ `rollback` (config): the kept version comes
/// back, each link gets the private data of its restore point. It also
/// stops a health check that runs (*Stop and roll back*). The rollback is
/// itself the package's next `last_update`, which the sheet follows.
class RollbackPackageAction extends Action with NonReentrant, WaitingAction {
  RollbackPackageAction(this.name);

  final String name;

  @override
  Future<AppState?> reduce() async {
    final key = '${site.root}/sys/packages/$name';
    final before = updateReportOf(
      toDart(await readValue(deps.wyrm, '$key/last_update')),
    );
    // While a check runs, the report it wrote is the one to wait past.
    final seen = before == null || before.result == 'checking' ? -2 : before.at;
    final answer = await invokeOne(deps.wyrm, key, 'rollback');
    requireSuccess(answer, key, 'rollback', thing: name);
    unawaited(dispatchAndWait(RetrievePackagesAction()));
    if (updates.package != name) {
      return null;
    }
    return state.copyWith.updates(
      view: 'follow',
      seenAt: seen,
      message: str(answer['message']),
    );
  }
}
