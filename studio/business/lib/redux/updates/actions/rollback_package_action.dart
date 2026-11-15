import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:models/update_result.dart';
import 'package:models/update_view.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/package_info.dart';
import '../../../wyrm/decode/sys_verdict.dart';
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
      await readValue(deps.wyrm, '$key/last_update'),
      where: '$key/last_update',
    ).orWarn('$key/last_update');
    // While a check runs, the report it wrote is the one to wait past.
    final seen = before == null || before.result == UpdateResult.checking
        ? -2
        : before.at;
    final answer = await invokeOne(deps.wyrm, key, 'rollback');
    requireSuccess(answer, key, 'rollback', thing: name);
    await dispatchAndWait(RetrievePackagesAction());
    if (updates.package != name) {
      return null;
    }
    return state.copyWith.updates(
      view: UpdateView.follow,
      seenAt: seen,
      message: sysRunOf(answer, where: '$key ▸ rollback').message,
    );
  }
}
