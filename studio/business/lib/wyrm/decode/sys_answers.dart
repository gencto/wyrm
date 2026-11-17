import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/link_revision.dart';
import 'package:models/watch_group.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../redux/links/actions/retrieve_link_history_action.dart'
    show prettyJson;
import '../mappers/values.dart';
import 'decoded.dart';
import 'fields.dart';

/// The answer of `sys/tokens` ▸ `add`: one row `{token}` per token made,
/// as the tokens. A row of another shape is [Invalid]: a token is shown
/// once, so nothing else is shown in its place.
Decoded<List<String>> issuedTokensOf(List<Value> rows) => decoding(
  'issued token',
  () => [for (final r in rows) Fields.of(r).text('token')],
);

/// The answer of `sys/links/<id>` ▸ `history`: records `{rev, params}`,
/// each row one record or an array of them, newest first. `params` is
/// kept as indented JSON (bytes as base64): Studio shows a revision's
/// parameters as text and reads nothing out of them.
Decoded<List<LinkRevision>> linkRevisionsOf(List<Value> rows) =>
    decoding('link revision', () {
      final out = [
        for (final r in rows)
          for (final e in switch (r) {
            VArray(:final v) => v,
            _ => [r],
          })
            switch (Fields.of(e)) {
              final f => LinkRevision(
                rev: f.whole('rev'),
                params: prettyJson(toDart(f.raw('params'))),
              ),
            },
      ]..sort((a, b) => b.rev.compareTo(a.rev));
      return out;
    });

/// One group of `sys/history` with the values of its leaves ([values], by
/// leaf: `logging_type`, `interval`, `buffer_flush_time`) and its watches
/// ([watches]: the children that are folders, named by the key they
/// record). A leaf of another type is [Invalid] with its name.
Decoded<WatchGroup> watchGroupOf(
  String name,
  Map<String, Value> values,
  List<Child> watches,
) => decoding('watch group', () {
  final f = Fields.values(values);
  final folders = [
    for (final w in watches)
      if (w.meta.ty == null) w,
  ];
  return WatchGroup(
    name: name,
    loggingType: f.textOr('logging_type') ?? '',
    interval: f.numberOr('interval'),
    flush: f.numberOr('buffer_flush_time'),
    watchIds: [for (final w in folders) w.name].lock,
    keys: [for (final w in folders) w.meta.displayName ?? w.name].lock,
  );
});

/// One value of `sys/history/*` as the text the statistics show: a text,
/// a number (a whole float without its `.0`) or a bool. A value of
/// another shape is [Invalid] with its leaf.
Decoded<String> historianStatOf(String leaf, Value value) => switch (value) {
  VStr(:final v) => Valid(v),
  VInt(:final v) => Valid('$v'),
  VFloat(:final v) when v == v.truncateToDouble() && v.abs() < 1e15 => Valid(
    '${v.toInt()}',
  ),
  VFloat(:final v) => Valid('$v'),
  VBool(:final v) => Valid('$v'),
  VNull() => const Valid(''),
  _ => Invalid('historian', leaf, 'not a text, a number or a bool'),
};
