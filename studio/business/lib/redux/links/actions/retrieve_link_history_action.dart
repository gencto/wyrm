import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/link_revision.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_links_action.dart';

/// `sys/links/<id>` ▸ `history` (config): the revisions of the link's
/// parameters, newest first, into `links.revisions`.
class RetrieveLinkHistoryAction extends Action with WaitingAction {
  RetrieveLinkHistoryAction(this.id);

  @override
  Action again() => RetrieveLinkHistoryAction(id);

  @override
  Action reload() => RetrieveLinksAction();

  final String id;

  @override
  Future<AppState> reduce() async {
    final rows = await askAll(
      deps.wyrm,
      '${site.root}/sys/links/$id',
      'history',
    );
    final revs = <LinkRevision>[
      for (final r in rows)
        for (final e in switch (r) {
          VArray(:final v) => v,
          _ => [r],
        })
          LinkRevision(
            rev: integer(e['rev']) ?? 0,
            params: prettyJson(toDart(e['params'])),
          ),
    ]..sort((a, b) => b.rev.compareTo(a.rev));
    return state.copyWith.links(revisions: revs.lock);
  }
}

/// [v] as indented JSON; bytes as base64.
String prettyJson(Object? v) => JsonEncoder.withIndent(
  '  ',
  (o) => o is List<int> ? base64Encode(o) : '$o',
).convert(v);
