import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/staged_change.dart';

import '../../app_state.dart';
import '../../changes/actions/add_changes_action.dart';
import '../../common/action.dart';

/// Stages `sys/links/<id>` ▸ `update {params}` (config) with [json], the
/// link's whole parameter map: Edit params, applied with the others.
class UpdateLinkParamsAction extends Action with NonReentrant, WaitingAction {
  UpdateLinkParamsAction(this.id, this.json, {this.from = '—'});

  final String id;

  /// The edited parameters, as JSON text.
  final String json;

  /// The revision it was edited from (`rev 3`).
  final String from;

  @override
  Future<AppState?> reduce() async {
    final Object? params;
    try {
      params = jsonDecode(json);
    } on FormatException catch (e) {
      throw UserException('The parameters are not JSON.', reason: e.message);
    }
    if (params is! Map<String, Object?>) {
      throw const UserException('The parameters must be one JSON object.');
    }
    dispatch(
      AddChangesAction(
        [
          StagedChange(
            id: 'params:$id',
            op: 'Edit',
            key: '${site.root}/sys/links/$id',
            field: 'params',
            from: from,
            to: '${params.length} top-level keys',
            level: 'config',
            action: 'update',
            args: {'params': params}.lock,
          ),
        ].lock,
      ),
    );
    return null;
  }
}
