import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/agent_config.dart';
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
    if (!site.can(Perm.config, '$key/~act/secrets')) {
      return state.copyWith.assistant(secrets: null);
    }
    try {
      final names = await askOne(deps.wyrm, key, 'secrets');
      if (assistant.agent != agent) {
        return null;
      }
      // an answer that is no list of names is logged: not known
      return state.copyWith.assistant(
        secrets: secretNamesOf(names).orWarn(key),
      );
    } on Object {
      // An older broker without the action, or no rights: not known.
      return state.copyWith.assistant(secrets: null);
    }
  }
}
