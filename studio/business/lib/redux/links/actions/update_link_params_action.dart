import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/change_op.dart';
import 'package:models/change_side.dart';
import 'package:models/staged_change.dart';
import 'package:models/staged_change_kind.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../../../wyrm/decode/link_params.dart';
import '../../app_state.dart';
import '../../changes/actions/add_changes_action.dart';
import '../../common/action.dart';

/// Stages `sys/links/<id>` ▸ `update {params}` (config) with [json], the
/// link's whole parameter map: Edit params, applied with the others.
class UpdateLinkParamsAction extends Action with NonReentrant, WaitingAction {
  UpdateLinkParamsAction(this.id, this.json, {this.rev});

  final String id;

  /// The edited parameters, as JSON text.
  final String json;

  /// The revision it was edited from; null when none was read.
  final int? rev;

  @override
  AppState? reduce() {
    // The dialog checks the text as it is typed and says what is wrong
    // under the field ([linkParamsOf]); text that does not pass is not
    // staged.
    final Map<String, Object?> params;
    switch (linkParamsOf(json)) {
      case ParamsObject(params: final p):
        params = p;
      case ParamsNotObject() || ParamsNotJson():
        return null;
    }
    dispatchSync(
      AddChangesAction(
        [
          StagedChange(
            // the full key: the same link id on two sites is two changes
            id: StagedChangeKind.params.idOf('${site.root}/sys/links/$id'),
            op: ChangeOp.edit,
            key: '${site.root}/sys/links/$id',
            field: 'params',
            from: switch (rev) {
              final r? => ChangeSide.rev(r),
              null => const ChangeSide.none(),
            },
            to: ChangeSide.keys(params.length),
            level: Perm.config,
            action: 'update',
            args: {'params': params}.lock,
          ),
        ].lock,
      ),
    );
    return null;
  }
}
