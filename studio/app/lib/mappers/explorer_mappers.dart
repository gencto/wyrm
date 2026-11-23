import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/explorer.dart';
import 'package:business/wyrm/labels.dart';
import 'package:business/wyrm/points.dart' show pollParam;
import 'package:models/driver_status.dart';
import 'package:models/explorer_command.dart';
import 'package:models/explorer_tab.dart';
import 'package:models/history_range.dart';
import 'package:models/link_mode.dart';
import 'package:models/link_state.dart';
import 'package:models/modbus_area.dart';
import 'package:models/node_kind.dart';
import 'package:models/point_mark.dart';
import 'package:models/point_param.dart';
import 'package:models/point_register.dart';
import 'package:models/quality.dart';
import 'package:models/read_failure.dart';
import 'package:models/word_order.dart';
import 'package:models/workspace.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/fail_chip.dart';
import 'package:ui/indicators/node_state.dart';
import 'package:ui/indicators/sample_mark.dart';
import 'package:ui/indicators/value_type.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/explorer_page.dart';
import 'package:ui/tables/points_table.dart';
import 'package:ui/theme/sizes.dart';
import 'package:wyrm_client/wyrm_client.dart' show TypeCode;

import '../common/forms.dart';
import '../common/trend.dart';
import '../common/value_viewer.dart';
import 'flow_mappers.dart';
import 'rights_mappers.dart';

export 'flow_mappers.dart' show FlowStateTagOf;
export 'rights_mappers.dart' show PermAccess;

// Explorer's domain as `ui` draws it (studio-rules §3): one exhaustive
// switch per domain enum, and the records of `business/lib/wyrm/explorer`
// as the page's render models, field for field. A new domain value is a
// compile error here, not a silent default on the screen.

extension LinkModeTagOf on LinkMode {
  LinkModeTag get tag => switch (this) {
    LinkMode.embedded => .embedded,
    LinkMode.process => .process,
    LinkMode.wasm => .wasm,
    LinkMode.external => .external,
  };
}

extension LinkStateNode on LinkState {
  /// A link on its way (installed, starting, stopping) draws as starting.
  NodeState get node => switch (this) {
    LinkState.connected => .connected,
    LinkState.failed => .failed,
    LinkState.stopped => .stopped,
    LinkState.installed ||
    LinkState.starting ||
    LinkState.stopping => .starting,
  };
}

extension LinkStateSampleNode on Decoded<LinkState> {
  /// A state this client cannot read draws as one on its way.
  NodeState get node => switch (this) {
    Valid(:final value) => value.node,
    Invalid() => .starting,
  };
}

extension NodeKindTagOf on NodeKind {
  NodeKindTag get tag => switch (this) {
    NodeKind.device => .device,
    NodeKind.connection => .connection,
    NodeKind.link => .link,
    NodeKind.flow => .dataflow,
    NodeKind.storage => .storage,
    NodeKind.broker => .broker,
    NodeKind.folder => .folder,
  };
}

extension ExplorerTabTagOf on ExplorerTab {
  ExplorerTabTag get tag => switch (this) {
    ExplorerTab.points => .points,
    ExplorerTab.children => .contents,
    ExplorerTab.params => .parameters,
    ExplorerTab.actions => .actions,
    ExplorerTab.history => .history,
    ExplorerTab.audit => .audit,
  };
}

extension ExplorerTabOf on ExplorerTabTag {
  ExplorerTab get tab => switch (this) {
    ExplorerTabTag.points => .points,
    ExplorerTabTag.contents => .children,
    ExplorerTabTag.parameters => .params,
    ExplorerTabTag.actions => .actions,
    ExplorerTabTag.history => .history,
    ExplorerTabTag.audit => .audit,
  };
}

extension HistoryRangeTagOf on HistoryRange {
  HistoryRangeTag get tag => switch (this) {
    HistoryRange.hour => .hour,
    HistoryRange.day => .day,
    HistoryRange.week => .week,
  };
}

extension HistoryRangeOf on HistoryRangeTag {
  HistoryRange get range => switch (this) {
    HistoryRangeTag.hour => .hour,
    HistoryRangeTag.day => .day,
    HistoryRangeTag.week => .week,
  };
}

extension PointMarkSample on PointMark {
  SampleMark get sample => switch (this) {
    PointMark.good => .good,
    PointMark.uncertain => .uncertain,
    PointMark.bad => .bad,
    PointMark.none => .none,
    PointMark.stale => .stale,
    PointMark.notApplied => .notApplied,
  };
}

extension QualitySample on Quality {
  SampleMark get sample => switch (this) {
    Quality.good => .good,
    Quality.uncertain => .uncertain,
    Quality.bad => .bad,
  };
}

extension ModbusAreaTag on ModbusArea {
  RegisterArea get area => switch (this) {
    ModbusArea.holding => .holding,
    ModbusArea.input => .input,
    ModbusArea.coil => .coil,
    ModbusArea.discrete => .discrete,
  };
}

extension PointRegisterVm on PointRegister {
  RegisterVm get vm => switch (this) {
    ModbusRegister(:final addr, :final area, :final table) => ModbusRegisterVm(
      addr: addr,
      area: area?.area,
      table: table,
    ),
    AddressRegister(:final text) => AddressRegisterVm(text),
    NoRegister() => const NoRegisterVm(),
  };
}

extension WordOrderTagOf on WordOrder {
  WordOrderTag get tag => switch (this) {
    WordOrder.abcd => .abcd,
    WordOrder.cdab => .cdab,
    WordOrder.badc => .badc,
    WordOrder.dcba => .dcba,
  };
}

extension PointParamWord on PointParam {
  PointFieldWord get word => switch (this) {
    PointParam.table => .area,
    PointParam.addr => .address,
    PointParam.dtype => .dataType,
    PointParam.bit => .bit,
    PointParam.regs => .registers,
    PointParam.wordOrder => .wordOrder,
    PointParam.unit => .unit,
    PointParam.scale => .scale,
    PointParam.offset => .offset,
    PointParam.precision => .precision,
    PointParam.poll => .poll,
    PointParam.writable => .writable,
    PointParam.writableByMaster => .writableByMaster,
  };
}

extension ReadFailureWhat on ReadFailure {
  ReadWhat get what => switch (this) {
    ReadFailure.value => .value,
    ReadFailure.list => .list,
    ReadFailure.meta => .meta,
  };
}

extension ReadFailsVm on List<ReadFail> {
  List<ReadFailed> get vm => [
    for (final f in this) ReadFailed(f.what.what, f.reason),
  ];
}

extension DriverStatusTone on DriverStatus? {
  /// A state with no tone of its own is neutral.
  Tone get tone => switch (this) {
    DriverStatus.connected => .good,
    DriverStatus.connecting || DriverStatus.unknown => .warn,
    DriverStatus.failed => .bad,
    null => .neutral,
  };
}

extension NoteWorkspaceOf on NoteWorkspace {
  Workspace get workspace => switch (this) {
    NoteWorkspace.links => .links,
    NoteWorkspace.access => .access,
    NoteWorkspace.sites => .sites,
    NoteWorkspace.system => .system,
  };
}

extension ReachDisabled on Reach {
  /// Why the control is disabled, null when it runs; a missing action is
  /// [missing] when the board says why in its own words.
  Disabled? disabled({Missing? missing}) => switch (this) {
    CanRun() => null,
    NoSuchAction(:final action) => switch (missing) {
      final m? => NotThere(m),
      null => NoAction(action),
    },
    LacksLevel(:final level, :final path) => NeedsLevel(level.access, path),
  };
}

extension TypeCodeValueType on TypeCode {
  ValueType get valueType => switch (this) {
    TypeCode.null_ => .null_,
    TypeCode.number => .number,
    TypeCode.string => .string,
    TypeCode.bool_ => .bool_,
    TypeCode.enum_ => .enum_,
    TypeCode.map => .map,
    TypeCode.array => .array,
    TypeCode.binary => .binary,
    TypeCode.dynamic_ => .dynamic_,
  };
}

extension TypeCodeKind on TypeCode {
  /// How a new value of this type is typed (an enum by its name).
  ParamKind get kind => switch (this) {
    TypeCode.bool_ => .toggle,
    TypeCode.number => .number,
    TypeCode.enum_ => .choice,
    TypeCode.null_ ||
    TypeCode.string ||
    TypeCode.map ||
    TypeCode.array ||
    TypeCode.binary ||
    TypeCode.dynamic_ => .text,
  };
}

extension ExplorerPointRowVm on ExplorerPointRow {
  PointRowVm get vm => PointRowVm(
    id: id,
    name: name,
    display: display,
    register: register.vm,
    dtype: dtype,
    type: type?.valueType,
    unit: unit,
    poll: poll,
    pollWas: pollWas,
    value: value,
    mark: mark.sample,
    failed: failed,
    writable: writable,
    checked: checked,
    selected: selected,
    staged: staged,
    stale: stale,
  );
}

extension ExplorerChildRowVm on ExplorerChildRow {
  ChildRowVm get vm => switch (this) {
    ExplorerValueRow(:final type, :final writable, :final value) =>
      ChildValueRowVm(
        key: key,
        name: name,
        display: display,
        selected: selected,
        type: type.valueType,
        writable: writable,
        value: value,
      ),
    ExplorerNodeRow(:final kind) => ChildNodeRowVm(
      key: key,
      name: name,
      display: display,
      selected: selected,
      kind: kind.tag,
    ),
  };
}

extension ExplorerFieldOf on ExplorerField {
  ExplorerFieldVm get vm {
    final kind = switch (spec) {
      final s? => paramField(s).kind,
      null => ParamKind.text,
    };
    return ExplorerFieldVm(
      code: code,
      label: label,
      word: param?.word,
      kind: kind,
      value: switch (value) {
        final WordOrder o => TextValue(o.tag.text),
        final v => heldValueOf(v, kind),
      },
      choices: spec?.choices.unlock ?? const [],
      choiceLabels: switch (spec) {
        final s? => choiceLabels(s.choices),
        null => const {},
      },
      description: description,
      missing: missing,
    );
  }
}

extension ExplorerSectionOf on ExplorerSection {
  ExplorerSectionVm get vm => switch (this) {
    FlowStateSection(:final flow) => FlowStateSectionVm(
      state: flow.tag,
      version: flow.version,
      deployedBy: flow.deployedBy,
      since: flow.since,
      problem: flow.problem,
    ),
    ParamsSection(:final key, :final fields, :final cfg, :final noEdit) =>
      ParamsSectionVm(
        node: key,
        fields: [for (final f in fields) f.vm],
        cfg: [for (final f in cfg) f.vm],
        noEdit: noEdit,
      ),
    AttributesSection(:final attr) => AttributesSectionVm([
      for (final f in attr) f.vm,
    ]),
    DiagnosticsSection(:final facts) => DiagnosticsSectionVm([
      for (final f in facts) f.vm,
    ]),
    PointFactsSection(:final type, :final unit, :final writable) =>
      PointFactsSectionVm(
        type: type?.valueType,
        unit: unit,
        level: writable?.access,
      ),
    RegisterSection(:final key, :final fields) => PointFieldsSectionVm(
      node: key,
      value: false,
      fields: [for (final f in fields) f.vm],
    ),
    ValueSection(:final key, :final fields) => PointFieldsSectionVm(
      node: key,
      value: true,
      fields: [for (final f in fields) f.vm],
    ),
    PollingSection(:final key, :final now, :final was, :final staged) =>
      PollingSectionVm(
        node: key,
        code: pollParam,
        rates: explorerPolls,
        now: now,
        was: was,
        staged: staged,
      ),
    WriteSection(:final key, :final fields, :final level) => WriteSectionVm(
      node: key,
      fields: [for (final f in fields) f.vm],
      level: level.access,
    ),
    PublishSection(
      :final type,
      :final unit,
      :final writable,
      :final sample,
      :final value,
    ) =>
      PublishSectionVm(
        type: type?.valueType,
        unit: unit,
        writable: writable,
        value: value,
        quality: sample?.quality.sample,
        time: sample?.time,
      ),
  };
}

extension ExplorerInspectorOf on ExplorerInspector {
  ExplorerInspectorVm get vm => switch (this) {
    final ActionInspector a => ActionInspectorVm(
      node: a.key,
      action: a.action.name,
      title: a.title,
      keyName: '…/${a.key.split('/').last}/~act/${a.action.name}',
      staged: a.staged,
      level: a.action.level.access,
      result: a.action.result,
      fields: paramFields(a.action.params),
      cli: a.cli,
      user: a.user,
      disabled: a.reach.disabled(),
    ),
    final PointInspector p => PointInspectorVm(
      name: p.name,
      display: p.display,
      value: p.value,
      mark: p.mark.sample,
      time: p.time,
      sections: [for (final s in p.sections) s.vm],
      key: p.key,
      fails: p.fails.vm,
      edit: p.edit?.kind,
      editValue: heldValueOf(p.editValue, p.edit?.kind ?? ParamKind.text),
      choices: p.choices,
      choiceLabels: choiceLabels(p.choices),
      readOnly: p.readOnly.disabled(),
    ),
    final NodeInspector n => NodeInspectorVm(
      kind: n.kind.tag,
      title: n.title,
      name: n.name,
      sections: [for (final s in n.sections) s.vm],
      key: n.key,
      fails: n.fails.vm,
    ),
  };
}

extension ExplorerMenuOf on ExplorerMenu {
  ExplorerMenuVm get vm => ExplorerMenuVm(
    key: key,
    name: name,
    driver: driver,
    kind: kind.tag,
    actions: actions,
    groups: [
      for (final g in groups)
        ExplorerMenuGroupVm(
          group: g.group,
          staged: g.staged,
          items: [
            for (final i in g.items)
              ExplorerMenuItemVm(
                name: i.action.name,
                label: i.label,
                level: i.action.level.access,
                form: i.action.params.isNotEmpty,
                danger: i.danger,
                disabled: i.reach.disabled(),
              ),
          ],
        ),
    ],
  );
}

extension ExplorerTrendVm on ExplorerTrend {
  /// One series of the raw rows read for the range (≤ 2000), zoomed on
  /// them without reading again (spec trend.md §4).
  TrendVm get vm => TrendVm(
    title: display ?? name,
    series: [
      TrendSeriesVm(
        id: point,
        name: name,
        label: display ?? '',
        color: TrendColor.byIndex(0),
        unit: unit ?? '',
        decimals: trendDecimals(rows, precision: precision),
        samples: trendSamples(rows),
        overview: trendSamples(rows),
      ),
    ],
    rangeStart: span.rangeStart,
    rangeEnd: span.rangeEnd,
    windowStart: span.windowStart,
    windowEnd: span.windowEnd,
    minWindow: span.minWindow,
    endsNow: true,
    following: span.following,
    loading: loading,
    card: false,
    hint: false,
    plotHeight: AppSizes.pointPlot,
    format: trendFormat(),
  );
}

extension ExplorerViewerVm on ExplorerViewer {
  /// Its value whole, with its unit and quality (stale offline).
  ValueViewerVm get vm => valueViewerOf(
    title: title,
    value: sample?.value,
    known: sample != null,
    unit: unit,
    choices: choices,
    quality: switch (sample) {
      null => null,
      _ when !connected => SampleMark.stale.vm(),
      final s => s.quality.sample.vm(at: s.time),
    },
  );
}

extension NodeFactVm on NodeFact {
  FactRowVm get vm => FactRowVm(name, label, value);
}

/// What a button of Explorer runs; null: the page runs it itself (Copy
/// keys, Set poll) or it is off (Apply profile, Record).
extension ExplorerToolCommand on ExplorerTool {
  ExplorerCommand? get command => switch (this) {
    ExplorerTool.ping => ExplorerCommand.ping,
    ExplorerTool.addPoint => ExplorerCommand.addPoint,
    ExplorerTool.importPoints => ExplorerCommand.importPoints,
    ExplorerTool.removeChecked => ExplorerCommand.removeChecked,
    ExplorerTool.copyKeys ||
    ExplorerTool.setPoll ||
    ExplorerTool.applyProfile ||
    ExplorerTool.record => null,
  };
}
