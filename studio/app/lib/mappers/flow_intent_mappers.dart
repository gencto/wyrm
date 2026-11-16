import 'package:business/redux/common/action.dart';
import 'package:business/redux/flow_editor/actions/bind_field_action.dart';
import 'package:business/redux/flow_editor/actions/flow_edit_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_form_action.dart';
import 'package:business/redux/flow_editor/actions/set_field_pin_action.dart';
import 'package:business/redux/flow_editor/actions/type_field_action.dart';
import 'package:business/wyrm/flow_view/flow_view.dart';
import 'package:models/field_id.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_intents.dart';

import 'flow_editor_mappers.dart';
import 'flow_inspector_mappers.dart';

// What a gesture of the flow editor does, as the action that does it, made
// from the view it was drawn from: the canvas reports a row by its place
// among a block's rows, the inspector a row by its index, and the view
// says which field stands there. Null: the gesture does nothing (the row
// is gone, nothing is selected).

/// The actions of the flow editor's gestures.
extension FlowViewIntents on FlowView {
  /// [act] on the field at the canvas's row [r].
  Action? onRow(RowRef r, Action Function(String block, FieldId row) act) =>
      switch (rowAt(r.block, r.row)) {
        final row? => act(r.block, row),
        null => null,
      };

  /// [act] on the field of the selected block at the inspector's row [i].
  Action? onField(int i, Action? Function(String block, RowId row) act) =>
      switch ((selected, inspector?.rowAt(i))) {
        (final at?, final row?) => act(at, row),
        _ => null,
      };

  /// The selected block's form picked ([BlockFormVm]).
  Action? form(BlockFormVm f) => switch (selected) {
    final at? => SetBlockFormAction(at, f.id),
    null => null,
  };

  /// The pin of an inspector row: a field only (the Form row has none).
  Action? fieldPin(RowPinned p) => switch ((
    selected,
    inspector?.rowAt(p.row),
  )) {
    (final at?, final FieldId id) => SetFieldPinAction(at, id, pinned: p.on),
    _ => null,
  };

  /// A text typed into an inspector row: a field's (a form is picked,
  /// [form]).
  Action? fieldTyped(RowTyped t) => onField(
    t.row,
    (at, row) => switch (row) {
      final FieldId field => TypeFieldAction(at, field, t.text),
      FormRow() => null,
    },
  );

  /// An output dropped on an inspector row.
  Action? fieldBound(RowBound b) =>
      onField(b.row, (at, row) => BindFieldAction(at, row, b.from.end));

  /// The viewer's Save: the text typed into the field it shows.
  Action? savedViewer(String text) => switch (questions.viewed) {
    FieldAt(:final block, row: final FieldId field) => TypeFieldAction(
      block,
      field,
      text,
    ),
    // The Form row's viewer only shows the form: it is picked, not typed.
    FieldAt(row: FormRow()) || null => null,
  };

  /// A command of the canvas the editor answers (the canvas and the page
  /// answer the rest).
  Action? command(CanvasCommand c) => switch (c.command.edit) {
    final e? => FlowEditAction(e, x: c.at?.dx, y: c.at?.dy),
    null => null,
  };
}
