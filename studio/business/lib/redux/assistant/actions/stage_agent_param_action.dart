import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_params.dart';
import 'package:models/approval_mode.dart';
import 'package:models/change_op.dart';
import 'package:models/change_side.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/param_side.dart';
import 'package:models/staged_change.dart';
import 'package:models/staged_change_kind.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../../../wyrm/assistant_view.dart';
import '../../../wyrm/decode/agent_params.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_link_history_action.dart';

/// Stages one edit of the agent link's params (`require_approval`,
/// `allowed_prefixes`) as `sys/links/<agent>` ▸ `update {params}` (config),
/// applied with the other staged changes in Review (spec `assistant.md`
/// §6).
///
/// The edit is made on the params as they will be: the update already
/// staged for *this* link (its full key, so the same link id on another
/// site is never a base), else the link's newest revision, read now. The
/// prefix list is taken from that base, not from what the screen read
/// before, so a second edit keeps the first. An edit that brings every
/// param back to the revision unstages the update. The review card names
/// each param that changes, with what it was and what it will be.
class StageAgentParamAction extends Action with WaitingAction {
  /// `require_approval` becomes [mode].
  StageAgentParamAction.mode(ApprovalMode mode)
    : _edit = ((p) => p.copyWith(requireApproval: mode));

  /// [prefix] joins `allowed_prefixes` (once).
  StageAgentParamAction.addPrefix(String prefix)
    : _edit = ((p) {
        final list = p.allowedPrefixes ?? const IListConst<String>([]);
        return list.contains(prefix)
            ? p
            : p.copyWith(allowedPrefixes: list.add(prefix));
      });

  /// [prefix] leaves `allowed_prefixes`.
  StageAgentParamAction.removePrefix(String prefix)
    : _edit = ((p) => p.copyWith(
        allowedPrefixes: (p.allowedPrefixes ?? const IListConst<String>([]))
            .remove(prefix),
      ));

  final AgentParams Function(AgentParams params) _edit;

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    if (agent == null) {
      return null;
    }
    final id = agent.split('/').last;
    final key = '${site.root}/sys/links/$id';
    // What is staged for the link is read back once here, and what does
    // not read is recorded here: the selector that reads it on every
    // rebuild records nothing.
    for (final c in changes.table.values) {
      if (c.key == key && c.action == 'update') {
        agentParamsOf(c.args['params']).record(key);
        agentParamsOf(c.value).record(key);
      }
    }
    final staged = stagedAgentParamsOf(key);
    AgentParams revision;
    int rev;
    if (staged case StagedAgentParams(:final change, :final base)) {
      revision = base;
      rev = switch (change.from) {
        ChangeSideParams(:final rev?) => rev,
        _ => 0,
      };
    } else {
      // `links.revisions` is one list for every link: only a read of this
      // link's history that just succeeded is its base. Without it nothing
      // is staged: an update of the param alone would replace every other
      // param of the agent with its default.
      final read = await dispatchAndWait(RetrieveLinkHistoryAction(id));
      final newest = links.revisions.firstOrNull;
      final params = newest == null || !read.isCompletedOk
          ? null
          : agentParamsOf(jsonDecode(newest.params)).orWarn(key);
      if (params == null) {
        throw StudioException.hinted(
          ErrorKind.broker,
          const ErrorHint.agentParamsUnread(),
          key: key,
          call: const .known(.history),
          thing: id,
        );
      }
      revision = params;
      rev = newest!.rev;
    }
    final next = _edit(staged?.params ?? revision);
    final modeChanged = next.requireApproval != revision.requireApproval;
    final prefixesChanged = next.allowedPrefixes != revision.allowedPrefixes;
    // each changed param as it was, and as it will be
    IList<ParamSide> side(AgentParams p) => [
      if (modeChanged)
        ParamSide(name: 'require_approval', text: p.requireApproval?.wire),
      if (prefixesChanged)
        ParamSide(name: 'allowed_prefixes', list: p.allowedPrefixes),
    ].lock;
    final cid = StagedChangeKind.params.idOf(key);
    final old = staged?.change.id;
    var table = changes.table;
    var view = changes.view;
    if (old != null && old != cid) {
      table = table.remove(old);
      view = view.remove(old);
    }
    if (!modeChanged && !prefixesChanged) {
      return state.copyWith.changes(
        table: table.remove(cid),
        view: view.remove(cid),
      );
    }
    final change = StagedChange(
      id: cid,
      op: ChangeOp.edit,
      key: key,
      field: 'params',
      from: ChangeSide.params(side(revision), rev: rev),
      to: ChangeSide.params(side(next)),
      level: Perm.config,
      action: 'update',
      args: {'params': agentParamsJson(next)}.lock,
      // what the edits are measured against
      value: agentParamsJson(revision),
    );
    return state.copyWith.changes(
      table: table.add(cid, change),
      view: view.contains(cid) ? view : view.add(cid),
      message: null,
    );
  }
}
