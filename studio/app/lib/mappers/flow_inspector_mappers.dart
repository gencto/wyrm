import 'package:business/wyrm/flow_view/inspector_view.dart';
import 'package:business/wyrm/flow_view/off.dart';
import 'package:business/wyrm/flow_view/summary_view.dart';
import 'package:business/wyrm/flow_view/viewer_view.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:models/flow_problem.dart';
import 'package:models/flow_problem_kind.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_viewer.dart';
import 'package:ui/flows/rows_editor.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/tables/table_edits.dart';

import '../common/value_viewer.dart';
import 'flow_editor_mappers.dart';
import 'rights_mappers.dart';

// The inspector, the flow's summary and the value viewer of the flow
// editor's business view (business/lib/wyrm/flow_view/) as `ui` draws them:
// one exhaustive switch per domain enum, and builders that only map. The
// words are `ui`'s.

/// What the inspector says the block is.
extension InspectorKindOf on InspectorKind {
  InspectorKindVm get vm => switch (this) {
    InspectorKind.ports => InspectorKindVm.ports,
    InspectorKind.node => InspectorKindVm.node,
    InspectorKind.logic => InspectorKindVm.logic,
    InspectorKind.sink => InspectorKindVm.sink,
    InspectorKind.action => InspectorKindVm.action,
    InspectorKind.my => InspectorKindVm.my,
  };
}

/// The note under the inspector's title.
extension InspectorNoteOf on InspectorNote {
  InspectorNoteVm get vm => switch (this) {
    InspectorNote.inputs => InspectorNoteVm.inputs,
    InspectorNote.outputs => InspectorNoteVm.outputs,
    InspectorNote.treeNode => InspectorNoteVm.treeNode,
    InspectorNote.actionBlock => InspectorNoteVm.actionBlock,
    InspectorNote.action => InspectorNoteVm.action,
    InspectorNote.catalog => InspectorNoteVm.catalog,
  };
}

/// The group a field is listed under; none: no heading.
extension FieldGroupOf on FieldGroup {
  FieldGroupVm? get vm => switch (this) {
    FieldGroup.none => null,
    FieldGroup.target => FieldGroupVm.target,
    FieldGroup.arguments => FieldGroupVm.arguments,
    FieldGroup.behaviour => FieldGroupVm.behaviour,
    FieldGroup.events => FieldGroupVm.events,
    FieldGroup.state => FieldGroupVm.state,
  };
}

/// A block's form, both ways.
extension BlockFormIdVm on BlockFormId {
  BlockFormVm get vm => switch (this) {
    BlockFormId.linear => BlockFormVm.linear,
    BlockFormId.range => BlockFormVm.range,
  };
}

extension BlockFormVmId on BlockFormVm {
  BlockFormId get id => switch (this) {
    BlockFormVm.linear => BlockFormId.linear,
    BlockFormVm.range => BlockFormId.range,
  };
}

/// Why `Run` is off.
extension RunOffReasonVm on RunOffReason {
  FlowOffReason get vm => switch (this) {
    RunOffReason.noBroker => FlowOffReason.runNoBroker,
    RunOffReason.notDeployed => FlowOffReason.runNotDeployed,
    RunOffReason.draft => FlowOffReason.runDraft,
    RunOffReason.noInstance => FlowOffReason.runNoInstance,
    RunOffReason.off => FlowOffReason.runOff,
  };
}

/// `Run`'s [Off] as `ui`'s reason.
extension RunOffDisabled on Off<RunOffReason> {
  Disabled get disabled => switch (this) {
    OffFor(:final reason) => FlowOff(reason.vm),
    OffNeeds(:final right) => right.disabled,
  };
}

/// How a parameter is typed.
extension ParamRowEditorVm on ParamRowEditor {
  FieldEditorVm get vm => switch (this) {
    ParamRowEditor.rows => FieldEditorVm.rows,
    ParamRowEditor.suggest => FieldEditorVm.suggest,
    ParamRowEditor.choice => FieldEditorVm.choice,
    ParamRowEditor.toggle => FieldEditorVm.toggle,
    ParamRowEditor.duration => FieldEditorVm.duration,
    ParamRowEditor.text => FieldEditorVm.text,
  };
}

/// How an argument is typed.
extension ArgRowEditorVm on ArgRowEditor {
  FieldEditorVm get vm => switch (this) {
    ArgRowEditor.choice => FieldEditorVm.choice,
    ArgRowEditor.toggle => FieldEditorVm.toggle,
    ArgRowEditor.text => FieldEditorVm.text,
  };
}

/// The head of the inspector of a block.
extension InspectorViewHead on InspectorView {
  InspectorHeadVm get head => InspectorHeadVm(
    kind: kind.vm,
    id: id,
    boundary: boundary?.vm,
    note: note.vm,
    description: description,
  );

  /// Its rows, in the order the inspector draws them.
  List<InspectorRowVm> get rowVms => [for (final r in rows) r.vm];
}

/// A list of maps typed a line per item.
extension RowsEditorViewVm on RowsEditorView {
  RowsEditorVm vm(String id) => RowsEditorVm(
    id: id,
    columns: [
      for (final c in columns)
        RowsColumnVm(c.key, c.label, choices: c.choices.unlock),
    ],
    rows: [for (final r in rows) r.unlock],
  );
}

/// One row of the inspector.
extension InspectorRowOf on InspectorRow {
  InspectorRowVm get vm {
    final id = this.id.key;
    InspectorRowVm row(
      FieldEditorVm editor, {
      String? value = '',
      bool on = false,
      List<String> choices = const [],
      String? source,
      bool writes = false,
      List<String> targets = const [],
      Disabled? off,
      String? confirm,
      RowsEditorVm? rows,
      BlockFormVm? form,
      List<BlockFormVm> forms = const [],
      String? hint,
    }) => InspectorRowVm(
      id: id,
      name: name,
      editor: editor,
      engine: engine,
      value: value,
      on: on,
      choices: choices,
      sourceBlock: source,
      writes: writes,
      targets: targets,
      inPort: inPort,
      hint: hint ?? this.hint,
      pinned: pinned,
      pinLocked: pinLocked,
      group: group.vm,
      off: off,
      confirm: confirm,
      error: switch (this) {
        ParamRowView(:final scopeError?) => scopeError.vm,
        _ => null,
      },
      rows: rows,
      form: form,
      forms: forms,
    );
    return switch (this) {
      FormRowView(:final form, :final forms) => row(
        FieldEditorVm.form,
        form: form.vm,
        forms: [for (final f in forms) f.vm],
      ),
      BoundRowView(:final value, :final source, :final writes) => row(
        FieldEditorVm.bound,
        value: value,
        source: source,
        writes: writes,
      ),
      RunRowView(:final off) => row(FieldEditorVm.run, off: off?.disabled),
      CommandRowView() => row(FieldEditorVm.command),
      DefaultRowView(:final value) => row(FieldEditorVm.defaults, value: value),
      ParamRowView(
        :final editor,
        :final value,
        :final on,
        :final choices,
        :final rows,
        :final confirm,
      ) =>
        row(
          editor.vm,
          value: value,
          on: on,
          choices: choices.unlock,
          rows: rows?.vm(id),
          confirm: confirm,
        ),
      ArgRowView(:final editor, :final value, :final on, :final choices) => row(
        editor.vm,
        value: value,
        on: on,
        choices: choices.unlock,
      ),
      OperandRowView(:final value, :final range) => row(
        range ? FieldEditorVm.suggest : FieldEditorVm.text,
        value: value,
        choices: range ? rangeChoices : const [],
      ),
      OutputRowView(:final value, :final targets) => row(
        FieldEditorVm.output,
        value: value,
        targets: targets.unlock,
      ),
      SampleRowView(:final value) => row(FieldEditorVm.sample, value: value),
    };
  }
}

/// What a problem of the last validation is about.
extension FlowProblemKindOf on FlowProblemKind {
  FlowProblemKindVm get vm => switch (this) {
    FlowProblemKind.unnamed => FlowProblemKindVm.unnamed,
    FlowProblemKind.broker => FlowProblemKindVm.broker,
    FlowProblemKind.unread => FlowProblemKindVm.unread,
  };
}

/// A problem, or the draft's preview refused (`preview`).
extension FlowProblemOf on FlowProblem {
  FlowProblemVm vm({bool preview = false}) =>
      FlowProblemVm(kind.vm, message: message, block: block, preview: preview);
}

/// Where the values come from.
extension ValuesFromOf on ValuesFrom {
  ValuesFromVm get vm => switch (this) {
    ValuesFrom.preview => ValuesFromVm.preview,
    ValuesFrom.deployed => ValuesFromVm.deployed,
  };
}

/// The flow's summary.
extension FlowSummaryViewVm on FlowSummaryView {
  FlowSummaryVm get vm => FlowSummaryVm(
    name: name,
    facts: [
      FactVersion(version),
      if (deployedBy case final by?) FactDeployedBy(by, at: deployedAt),
      if (mayWrite case final level?) FactMayWrite(level.access),
      if (values case final from?) FactValues(from.vm),
      if (liveRefused) const FactLiveRefused(),
      if (reads.isNotEmpty) FactReads(reads.unlock),
      if (writes.isNotEmpty) FactWrites(writes.unlock),
    ],
    problems: [
      if (previewProblem case final p?) p.vm(preview: true),
      for (final p in problems) p.vm(),
    ],
  );
}

/// Why a field cannot be typed in the viewer.
extension FieldLockedVm on FieldLocked {
  ViewerLockVm get vm => switch (this) {
    FieldLocked.bound => ViewerLockVm.bound,
    FieldLocked.output => ViewerLockVm.output,
    FieldLocked.input => ViewerLockVm.input,
  };
}

/// What is wrong with a text typed in the viewer.
extension FieldEditErrorVm on FieldEditError {
  ViewerTextProblemVm get vm => switch (this) {
    FieldEditError.number => ViewerTextProblemVm.number,
    FieldEditError.json => ViewerTextProblemVm.json,
    FieldEditError.toggle => ViewerTextProblemVm.toggle,
  };
}

/// How the viewer's Edit mode types the value.
extension ViewerEditModeVm on ViewerEditMode {
  ViewerEditKind get vm => switch (this) {
    ViewerEditMode.choice => ViewerEditKind.choice,
    ViewerEditMode.toggle => ViewerEditKind.toggle,
    ViewerEditMode.number => ViewerEditKind.number,
    ViewerEditMode.table => ViewerEditKind.table,
    ViewerEditMode.json => ViewerEditKind.json,
    ViewerEditMode.text => ViewerEditKind.text,
  };
}

/// A table typed in the viewer's grid, as the grid holds it.
extension ViewerTableData on ViewerTable {
  TableDataVm? get data =>
      empty ? TableDataVm.empty() : tableDataOf(value, rowsOfMaps: true);
}

/// The open viewer of a field, or of the Form row.
extension ViewerViewVm on ViewerView {
  FlowViewerVm get vm => switch (this) {
    FormViewerView(:final block, :final form) => FormViewerVm(block, form.vm),
    final FieldViewerView v => FieldViewerVm(v._field),
  };
}

extension on FieldViewerView {
  ValueViewerVm get _field {
    final grid = table?.data;
    return valueViewerOf(
      title: '$block.$field',
      value: shownTable ? grid?.toJson() : value,
      known: known,
      editable: table != null,
      rowsOfMaps: rowsOfMaps,
      date: date,
      unit: unit,
      choices: choices.unlock,
      quality: switch (quality) {
        final q? => qualityMarkOf(q),
        null => null,
      },
    ).typed(
      edit: switch (edit) {
        final e? => ViewerEditVm(
          kind: e.mode.vm,
          text: e.text,
          choices: e.choices.unlock,
          table: e.mode == ViewerEditMode.table ? grid : null,
        ),
        null => null,
      },
      locked: locked?.vm,
      csv: switch (csv) {
        final r? => ViewerCsvVm(
          delimiter: r.delimiter,
          header: r.header,
          wired: r.wired,
        ),
        null => null,
      },
    );
  }
}
