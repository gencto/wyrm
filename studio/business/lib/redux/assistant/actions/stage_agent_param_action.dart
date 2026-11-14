import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_kind.dart';
import 'package:models/staged_change.dart';

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
class StageAgentParamAction extends Action {
  /// `require_approval` becomes [mode].
  StageAgentParamAction.mode(String mode)
    : _edit = ((p) => p['require_approval'] = mode);

  /// [prefix] joins `allowed_prefixes` (once).
  StageAgentParamAction.addPrefix(String prefix)
    : _edit = ((p) {
        final list = _prefixes(p);
        if (!list.contains(prefix)) {
          p['allowed_prefixes'] = [...list, prefix];
        }
      });

  /// [prefix] leaves `allowed_prefixes`.
  StageAgentParamAction.removePrefix(String prefix)
    : _edit = ((p) => p['allowed_prefixes'] = [
        for (final q in _prefixes(p))
          if (q != prefix) q,
      ]);

  final void Function(Map<String, Object?> params) _edit;

  static List<String> _prefixes(Map<String, Object?> p) =>
      switch (p['allowed_prefixes']) {
        final List<Object?> l => [for (final e in l) ?(e is String ? e : null)],
        _ => const [],
      };

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    if (agent == null) {
      return null;
    }
    final id = agent.split('/').last;
    final key = '${site.root}/sys/links/$id';
    final staged = stagedParamsOf(key);
    Map<String, Object?> revision;
    String rev;
    if (staged case (:final change, :final base) when base.isNotEmpty) {
      revision = base;
      rev = change.from.split(':').first;
    } else {
      // `links.revisions` is one list for every link: only a read of this
      // link's history that just succeeded is its base. Without it nothing
      // is staged: an update of the param alone would replace every other
      // param of the agent with its default.
      final read = await dispatchAndWait(RetrieveLinkHistoryAction(id));
      final newest = links.revisions.firstOrNull;
      final params = newest == null ? null : jsonDecode(newest.params);
      if (!read.isCompletedOk || params is! Map<String, Object?>) {
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
    final next = <String, Object?>{
      ...?(staged?.change.args['params'] as Map<String, Object?>?),
    };
    if (staged == null) {
      next.addAll(revision);
    }
    _edit(next);
    final changed = [
      for (final k in {...revision.keys, ...next.keys})
        if (jsonEncode(revision[k]) != jsonEncode(next[k])) k,
    ];
    final cid = 'params:$key';
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
    String shown(Object? v) => switch (v) {
      null => '—',
      final List<Object?> l => l.isEmpty ? '[]' : l.join(', '),
      final Object o => '$o',
    };
    final change = StagedChange(
      id: cid,
      op: 'Edit',
      key: key,
      field: 'params · ${changed.join(', ')}',
      from:
          '$rev: ${[for (final k in changed) '$k ${shown(revision[k])}'].join(
            '; ',
          )}',
      to: [for (final k in changed) '$k ${shown(next[k])}'].join('; '),
      level: 'config',
      action: 'update',
      args: {'params': next}.lock,
      // what the edits are measured against
      value: revision,
    );
    return state.copyWith.changes(
      table: table.add(cid, change),
      view: view.contains(cid) ? view : view.add(cid),
      message: null,
    );
  }
}
