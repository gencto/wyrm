import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/links/<agent>` ▸ `secrets` (config, ADR 0049 §10): the names of
/// the agent link's secrets, never a value, so *What it may do* can say
/// whether the secret its `api_key_ref` names is set. Without `config` the
/// names stay unknown (`assistant.secrets` null) and the panel says why.
class RetrieveAgentSecretsAction extends Action {
  RetrieveAgentSecretsAction() : super(quiet: true);

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    final root = site.root;
    if (agent == null || root == null) {
      return null;
    }
    final key = '$root/sys/links/${agent.split('/').last}';
    if (site.grants.isNotEmpty && !site.can('config', '$key/~act/secrets')) {
      return state.copyWith.assistant(secrets: null);
    }
    try {
      final names = await askOne(deps.wyrm, key, 'secrets');
      if (assistant.agent != agent) {
        return null;
      }
      return state.copyWith.assistant(
        secrets: switch (names) {
          VArray(:final v) => {for (final n in v) ?str(n)}.lock,
          _ => const ISetConst({}),
        },
      );
    } on Object {
      // An older broker without the action, or no rights: not known.
      return state.copyWith.assistant(secrets: null);
    }
  }
}
