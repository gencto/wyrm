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

  /// Why [json] cannot be staged, for the line under the field: the
  /// parser's own message when it is not JSON, an empty string when it is
  /// JSON but not one object; null when it can be staged.
  static String? problemOf(String json) {
    try {
      return jsonDecode(json) is Map<String, Object?> ? null : '';
    } on FormatException catch (e) {
      return e.message.isEmpty ? 'not JSON' : e.message;
    }
  }

  @override
  Future<AppState?> reduce() async {
    // The dialog checks the text as it is typed and says what is wrong
    // under the field ([problemOf]); text that does not pass is not staged.
    if (problemOf(json) != null) {
      return null;
    }
    final params = jsonDecode(json) as Map<String, Object?>;
    dispatchSync(
      AddChangesAction(
        [
          StagedChange(
            // the full key: the same link id on two sites is two changes
            id: 'params:${site.root}/sys/links/$id',
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
