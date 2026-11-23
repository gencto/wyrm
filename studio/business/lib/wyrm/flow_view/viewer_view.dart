import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/node_type.dart';
import 'package:models/quality.dart';

import '../decode/table_value.dart';
import '../mappers/block_cfg.dart';
import '../mappers/csv_table.dart';
import '../mappers/flow_canvas.dart';
import '../mappers/flow_fields.dart';

/// How the viewer's Edit mode types a value.
enum ViewerEditMode { choice, toggle, number, table, json, text }

/// The viewer's Edit mode: how, and the text it starts with.
final class ViewerEdit extends Equatable {
  const ViewerEdit(
    this.mode, {
    required this.text,
    this.choices = const IListConst([]),
  });

  final ViewerEditMode mode;
  final String text;
  final IList<String> choices;

  @override
  List<Object?> get props => [mode, text, choices];
}

/// A table typed in the viewer's grid: [value] as the config holds it, or
/// none yet ([empty]: a grid with no columns).
final class ViewerTable extends Equatable {
  const ViewerTable(this.value) : empty = false;
  const ViewerTable.empty() : value = null, empty = true;

  final Object? value;
  final bool empty;

  @override
  List<Object?> get props => [value, empty];
}

/// How `table_from_csv` reads its text ([delimiter], [header]); [wired]: a
/// wire brings one of them now.
final class CsvRules extends Equatable {
  const CsvRules({
    required this.delimiter,
    required this.header,
    required this.wired,
  });

  final String delimiter;
  final bool header;
  final bool wired;

  @override
  List<Object?> get props => [delimiter, header, wired];
}

/// The open viewer of a field (owner request 2026-11-09), live.
sealed class ViewerView extends Equatable {
  const ViewerView(this.block);

  /// The block whose field it shows: the title is `<block>.<field>`.
  final String block;
}

/// The viewer of the `Form` row: the form's name.
final class FormViewerView extends ViewerView {
  const FormViewerView(super.block, this.form);

  final BlockFormId form;

  @override
  List<Object?> get props => [block, form];
}

/// The viewer of a field: titled `<block>.<engine name>`, the value
/// [fieldValue] shows, whole.
final class FieldViewerView extends ViewerView {
  const FieldViewerView(
    super.block, {
    required this.field,
    required this.value,
    required this.known,
    required this.shownTable,
    this.table,
    this.rowsOfMaps = false,
    this.date = false,
    this.unit,
    this.choices = const IListConst([]),
    this.quality,
    this.edit,
    this.locked,
    this.csv,
  });

  /// The engine's name of the field.
  final String field;
  final Object? value;
  final bool known;

  /// The value shown is the typed [table] (the field has no value of its
  /// own yet): its grid's JSON.
  final bool shownTable;

  /// A table typed in the grid (editable); null: none.
  final ViewerTable? table;
  final bool rowsOfMaps;
  final bool date;
  final String? unit;
  final IList<String> choices;
  final Quality? quality;
  final ViewerEdit? edit;
  final FieldLocked? locked;
  final CsvRules? csv;

  @override
  List<Object?> get props => [
    block,
    field,
    value,
    known,
    shownTable,
    table,
    rowsOfMaps,
    date,
    unit,
    choices,
    quality,
    edit,
    locked,
    csv,
  ];
}

/// The viewer of the row [row] of block [b] (its fields [all]), or null
/// when the row is gone.
ViewerView? viewerViewOf(
  FlowBlock b,
  RowId row,
  List<FlowField> all,
  FlowDraft d,
  LiveValue? Function(String) live, {
  required NodeType? type,
  required NodeInfo? info,
}) {
  if (row is FormRow) {
    return switch (formOf(b, d.edges)) {
      final form? => FormViewerView(b.id, form.id),
      null => null,
    };
  }
  final f = all.where((f) => f.id == row).firstOrNull;
  if (f == null) {
    return null;
  }
  final at = f.kind == FieldKind.input || f.kind == FieldKind.output;
  final v = fieldValue(b, f, d, live);
  final how = fieldEditOf(b, f, d.edges);
  final text = fieldEditText(b, f);
  final tabled = holdsTable(type, f);
  // A typed table (the `table` variable's Value, a table typed into a
  // table input) edits in the viewer's grid, from what the config holds;
  // an empty one starts with no columns (owner request 2026-11-11), except
  // the input of `table_from_json`, which takes a JSON text.
  final typedTable =
      tabled && (how.edit == FieldEdit.json || how.edit == FieldEdit.any)
      ? switch (fieldEditValue(b, f)) {
          JsonNull() || JsonText(text: '')
              when b.type.known != KnownBlock.tableFromJson =>
            const ViewerTable.empty(),
          final x when tableValueOf(x.raw, rowsOfMaps: true) != null =>
            ViewerTable(
              x.raw,
            ),
          _ => null,
        }
      : null;
  final shownTable = v.raw == null && typedTable != null;
  return FieldViewerView(
    b.id,
    field: f.name,
    value: v.raw,
    known: shownTable || v.raw != null || v.live,
    shownTable: shownTable,
    table: typedTable,
    // A table's rows (ADR 0044 §2) and a date (µs, §3) by the field.
    rowsOfMaps: tabled,
    date: isTimeField(b.type, f.port),
    unit: at ? info?.unit : null,
    choices: at ? info?.choices ?? const IListConst([]) : const IListConst([]),
    quality: v.quality,
    edit: switch (how.edit) {
      null => null,
      FieldEdit.choice => ViewerEdit(
        ViewerEditMode.choice,
        text: text,
        choices: f.spec?.choices ?? const IListConst([]),
      ),
      FieldEdit.toggle => ViewerEdit(
        ViewerEditMode.toggle,
        text: '${bool.tryParse(text) ?? false}',
      ),
      FieldEdit.number => ViewerEdit(ViewerEditMode.number, text: text),
      _ when typedTable != null => ViewerEdit(
        ViewerEditMode.table,
        text: text,
      ),
      FieldEdit.json => ViewerEdit(ViewerEditMode.json, text: text),
      FieldEdit.text || FieldEdit.any => ViewerEdit(
        ViewerEditMode.text,
        text: text,
      ),
    },
    locked: how.locked,
    csv: b.type.known == KnownBlock.tableFromCsv && f.port == EnginePort.in_
        ? _csvRules(b, all, d, live)
        : null,
  );
}

/// How `table_from_csv` [b] reads its text: its `delimiter` and
/// `with_header` as typed (their defaults `,` and true), or as a wire
/// brings them now.
CsvRules _csvRules(
  FlowBlock b,
  List<FlowField> all,
  FlowDraft d,
  LiveValue? Function(String) live,
) {
  var wired = false;
  JsonValue read(BlockCfgKey key) {
    final f = all.where((x) => x.spec?.key == key).firstOrNull;
    if (f == null) {
      return b.param(key.wire);
    }
    final shown = fieldValue(b, f, d, live);
    wired = wired || shown.bound;
    return switch (shown.json) {
      null || JsonNull() => b.paramOr(key.wire, f.spec?.defaultValue),
      final v => v,
    };
  }

  final delimiter = read(BlockCfgKey.delimiter);
  final header = read(BlockCfgKey.withHeader);
  return CsvRules(
    delimiter: csvDelimiter(delimiter.raw),
    header: switch (header) {
      JsonBool(:final value) => value,
      _ => true,
    },
    wired: wired,
  );
}
