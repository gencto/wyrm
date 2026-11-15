import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/action_answer.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../redux/links/actions/retrieve_link_history_action.dart'
    show prettyJson;
import '../mappers/values.dart';

/// The rows a node's action answered (`invoke`, one per result) as the
/// Explorer shows them: a table when they are records (a row that is a map,
/// or an array of maps), else each row as indented JSON.
///
/// Any answer is one: the rows that are no records are its lines.
ActionAnswer actionAnswerOf(List<Value> rows) {
  final records = <Map<String, Value>>[
    for (final r in rows)
      ...switch (r) {
        VArray(:final v) => [
          for (final e in v)
            if (e case VMap(:final v)) v,
        ],
        VMap(:final v) => [v],
        _ => const <Map<String, Value>>[],
      },
  ];
  final lines = [for (final r in rows) prettyJson(toDart(r))];
  final columns = {for (final r in records) ...r.keys}.take(6).toList();
  final table = records.length == lines.length || records.length > 1;
  return ActionAnswer(
    columns: columns.lock,
    rows: table
        ? [
            for (final r in records.take(200))
              [for (final c in columns) _cell(r[c])].lock,
          ].lock
        : const IListConst([]),
    count: records.isEmpty ? lines.length : records.length,
    lines: [for (final l in lines) ...l.split('\n')].lock,
  );
}

/// A field as its JSON line reads it back: bytes in base64.
String _cell(Value? v) => switch (v) {
  null || VNull() => '',
  VBytes(:final v) => base64Encode(v),
  _ => '${toDart(v)}',
};
