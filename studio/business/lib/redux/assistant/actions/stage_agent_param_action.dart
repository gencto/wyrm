import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_params.dart';
import 'package:models/approval_mode.dart';
import 'package:models/error_kind.dart';
import 'package:models/staged_change.dart';
import 'package:models/staged_change_kind.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

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
    final staged = stagedAgentParamsOf(key);
    AgentParams revision;
    String rev;
    if (staged case (:final change, :final base, params: _)) {
      revision = base;
      rev = change.from.split(':').first;
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
        throw StudioException.said(
          ErrorKind.broker,
          'The parameters of the agent link could not be read, so nothing '
          'was staged.',
          key: key,
          call: 'history',
          thing: id,
        );
      }
      revision = params;
      rev = 'rev ${newest!.rev}';
    }
    final next = _edit(staged?.params ?? revision);
    final changed = [
      if (next.requireApproval != revision.requireApproval)
        (
          name: 'require_approval',
          was: revision.requireApproval?.wire,
          now: next.requireApproval?.wire,
        ),
      if (next.allowedPrefixes != revision.allowedPrefixes)
        (
          name: 'allowed_prefixes',
          was: _listed(revision.allowedPrefixes),
          now: _listed(next.allowedPrefixes),
        ),
    ];
    final cid = StagedChangeKind.params.idOf(key);
    final old = staged?.change.id;
    var table = changes.table;
    var view = changes.view;
    if (old != null && old != cid) {
      table = table.remove(old);
      view = view.remove(old);
    }
    if (changed.isEmpty) {
      return state.copyWith.changes(
        table: table.remove(cid),
        view: view.remove(cid),
      );
    }
    final change = StagedChange(
      id: cid,
      op: 'Edit',
      key: key,
      field: 'params · ${[for (final c in changed) c.name].join(', ')}',
      from:
          '$rev: ${[for (final c in changed) '${c.name} ${c.was ?? '—'}'].join(
            '; ',
          )}',
      to: [for (final c in changed) '${c.name} ${c.now ?? '—'}'].join('; '),
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

  /// A prefix list as the review card says it: `A, B`, `[]`; null when
  /// the params do not set it.
  static String? _listed(IList<String>? l) => switch (l) {
    null => null,
    final l when l.isEmpty => '[]',
    final l => l.join(', '),
  };
}
