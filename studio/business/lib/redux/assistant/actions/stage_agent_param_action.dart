import 'dart:convert';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_link_history_action.dart';
import '../../links/actions/update_link_params_action.dart';

/// Stages one parameter of the agent link (`require_approval`,
/// `allowed_prefixes`) as an `update {params}` of `sys/links/<agent>`
/// (config), applied with the other staged changes in Review (spec
/// `assistant.md` §6). The other parameters are kept: the base is the
/// update already staged for the link, else its newest revision.
class StageAgentParamAction extends Action {
  StageAgentParamAction(this.name, this.value);

  final String name;
  final Object value;

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    if (agent == null) {
      return null;
    }
    final id = agent.split('/').last;
    final staged = changes.table['params:$id']?.args['params'];
    Map<String, Object?> base;
    String from;
    if (staged is Map<String, Object?>) {
      base = {...staged};
      from = changes.table['params:$id']!.from;
    } else {
      await dispatchAndWait(RetrieveLinkHistoryAction(id));
      final newest = links.revisions.firstOrNull;
      base = switch (jsonDecode(newest?.params ?? '{}')) {
        final Map<String, Object?> m => {...m},
        _ => {},
      };
      from = 'rev ${newest?.rev ?? 0}';
    }
    base[name] = value;
    await dispatchAndWait(
      UpdateLinkParamsAction(id, jsonEncode(base), from: from),
    );
    return null;
  }
}
