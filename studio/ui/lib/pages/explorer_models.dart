import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../alerts/read_fail.dart';
import '../containers/action_card.dart';
import '../forms/param_form.dart';
import '../indicators/fail_chip.dart';
import '../indicators/sample_mark.dart';
import '../indicators/status_pill.dart';
import '../models/disabled.dart';
import '../models/tone.dart';

// What the Explorer page draws, as the connector hands it: typed values
// (enums, numbers, times) and the domain's own text (a node's name, a
// broker's message). The words are said here and in the page
// (studio-rules §3, §5).

/// A button of the header, the points toolbar, the empty state or the
/// selection bar.
enum ExplorerTool {
  ping(null),
  addPoint('ui_add'),
  importPoints('ui_upload', quiet: true),
  applyProfile('ui_profile', quiet: true),
  copyKeys('ui_copy'),
  setPoll(null),
  record(null),
  removeChecked(null);

  const ExplorerTool(this.icon, {this.quiet = false});

  final String? icon;

  /// A quieter outline (Import, Apply profile).
  final bool quiet;

  String get label => switch (this) {
    ping => S.current.ping,
    addPoint => S.current.addPoint,
    importPoints => S.current.importPoints,
    applyProfile => S.current.applyProfile,
    copyKeys => S.current.copyKeys,
    setPoll => S.current.setPoll,
    record => S.current.recordInHistory,
    removeChecked => S.current.removeEllipsis,
  };
}

/// A [ExplorerTool] on screen: disabled with the reason, or not.
final class ToolButtonVm extends Equatable {
  const ToolButtonVm(this.tool, {this.disabled});

  final ExplorerTool tool;

  /// Null when the button works.
  final Disabled? disabled;

  @override
  List<Object?> get props => [tool, disabled];
}

/// A tab of the node on screen (docs/design/specs/explorer.md "Frames by
/// node kind").
enum ExplorerTabTag {
  points,
  contents,
  parameters,
  actions,
  history,
  audit;

  String get label => switch (this) {
    points => S.current.tabPoints,
    contents => S.current.tabContents,
    parameters => S.current.tabParameters,
    actions => S.current.tabActions,
    history => S.current.tabHistory,
    audit => S.current.tabAudit,
  };
}

/// A tab with its count, where it has one.
final class ExplorerTabVm extends Equatable {
  const ExplorerTabVm(this.tag, {this.count});

  final ExplorerTabTag tag;
  final int? count;

  @override
  List<Object?> get props => [tag, count];
}

/// The kind of a node: the word in a subtitle and the Contents tab, the
/// eyebrow of its inspector.
enum NodeKindTag {
  device,
  connection,
  link,
  dataflow,
  storage,
  broker,
  folder;

  String get word => switch (this) {
    device => S.current.kindDevice,
    connection => S.current.kindConnection,
    link => S.current.kindLink,
    dataflow => S.current.kindDataflow,
    storage => S.current.kindStorage,
    broker => S.current.kindBroker,
    folder => S.current.kindFolder,
  };

  String get eyebrow => switch (this) {
    device => S.current.insDevice,
    connection => S.current.insConnection,
    link => S.current.insLink,
    dataflow => S.current.dataflow,
    storage => S.current.insStorage,
    broker => S.current.insBroker,
    folder => S.current.insFolder,
  };
}

/// The workspaces the tree's note links to.
enum NoteWorkspace {
  links,
  access,
  sites,
  system;

  String get label => switch (this) {
    links => S.current.wsLinks,
    access => S.current.wsAccess,
    sites => S.current.wsSites,
    system => S.current.wsSystem,
  };
}

/// The span of the History tab.
enum HistoryRangeTag {
  hour,
  day,
  week;

  String get label => switch (this) {
    hour => S.current.historyRange1h,
    day => S.current.historyRange24h,
    week => S.current.historyRange7d,
  };
}

/// Why the points table is empty.
enum PointsEmpty {
  /// The device can have points added.
  noPointsYet,
  noPoints;

  String get text => switch (this) {
    noPointsYet => S.current.noPointsYet,
    noPoints => S.current.noPoints,
  };
}

/// A flow's state: its tone and words (`v2 deployed`, `v3 · error`, `v1
/// stopped`, `not deployed`).
enum FlowStateTag {
  error(Tone.bad),
  deployed(Tone.good),
  stopped(Tone.neutral),
  notDeployed(Tone.neutral);

  const FlowStateTag(this.tone);

  final Tone tone;

  String label(int? version) => switch (this) {
    error => S.current.flowError(version ?? 0),
    deployed => S.current.flowDeployed(version ?? 0),
    stopped => S.current.flowStopped(version ?? 0),
    notDeployed => S.current.notDeployed,
  };

  StatusPillVm pill(int? version) =>
      StatusPillVm(label: label(version), tone: tone);
}

/// The line under the node's name: `modbus device · unit 1 ·
/// 127.0.0.1:5020 · last read 12:00:03`, `dataflow · deployed by admin`,
/// `folder · 3 children`, then a flow's description.
final class ExplorerSubtitleVm extends Equatable {
  const ExplorerSubtitleVm({
    required this.kind,
    this.driver,
    this.deployedBy,
    this.problem,
    this.unit,
    this.host,
    this.port,
    this.serialPort,
    this.root,
    this.children,
    this.lastRead,
    this.description,
  });

  final NodeKindTag kind;
  final String? driver;
  final String? deployedBy;
  final String? problem;
  final String? unit;
  final String? host;
  final String? port;
  final String? serialPort;
  final String? root;
  final int? children;
  final DateTime? lastRead;
  final String? description;

  String get text => [
    [?driver, kind.word].join(' '),
    if (deployedBy case final who?) S.current.deployedByWho(who),
    ?problem,
    if (unit case final u?) S.current.unitNumber(u),
    if (host case final h?)
      if (port case final p?) '$h:$p' else h,
    ?serialPort,
    ?root,
    if (children case final n?) S.current.childCount(n),
    if (lastRead case final t?) S.current.lastRead(Formats.clockSeconds(t)),
    ?description,
  ].join(' · ');

  @override
  List<Object?> get props => [
    kind,
    driver,
    deployedBy,
    problem,
    unit,
    host,
    port,
    serialPort,
    root,
    children,
    lastRead,
    description,
  ];
}

/// The bar that replaces the points toolbar while 2 or more rows are
/// checked (§6): `<n> selected`, its buttons, Clear.
final class SelectionBarVm extends Equatable {
  const SelectionBarVm({required this.count, required this.buttons});

  final int count;
  final List<ToolButtonVm> buttons;

  @override
  List<Object?> get props => [count, buttons];
}

/// One row of the Contents tab: a child value (its [type]) or node (its
/// [kind]).
final class ChildRowVm extends Equatable {
  const ChildRowVm({
    required this.key,
    required this.name,
    this.display,
    this.type,
    this.writable = false,
    this.kind,
    this.value,
    this.selected = false,
  });

  final String key;
  final String name;
  final String? display;
  final String? type;
  final bool writable;
  final NodeKindTag? kind;

  /// A value as the user reads it, with its unit.
  final String? value;
  final bool selected;

  @override
  List<Object?> get props => [
    key,
    name,
    display,
    type,
    writable,
    kind,
    value,
    selected,
  ];
}

/// A group of action cards: Configure · staged, or Operate · runs now.
final class ActionCardGroupVm extends Equatable {
  const ActionCardGroupVm({required this.staged, required this.cards});

  final bool staged;
  final List<ActionCardVm> cards;

  @override
  List<Object?> get props => [staged, cards];
}

/// The answer of the last run of an action.
final class ResultVm extends Equatable {
  const ResultVm({
    required this.action,
    required this.count,
    this.columns = const [],
    this.rows = const [],
    this.lines = const [],
  });

  /// The action's label.
  final String action;

  /// How many rows it answered.
  final int count;

  /// A table when the rows are records…
  final List<String> columns;
  final List<List<String>> rows;

  /// …else the answer as JSON lines.
  final List<String> lines;

  @override
  List<Object?> get props => [action, count, columns, rows, lines];
}

/// One row of the History tab.
final class HistoryRowVm extends Equatable {
  const HistoryRowVm({required this.time, required this.value, this.mark});

  final DateTime time;
  final String value;

  /// Its quality; null for a rollup row.
  final SampleMark? mark;

  @override
  List<Object?> get props => [time, value, mark];
}

/// One record of the Audit tab.
final class AuditRowVm extends Equatable {
  const AuditRowVm({
    required this.time,
    required this.op,
    required this.key,
    required this.who,
    required this.status,
  });

  final DateTime time;
  final String op;
  final String key;
  final String who;

  /// 0: the call went through; else the status code that refused it.
  final int status;

  @override
  List<Object?> get props => [time, op, key, who, status];
}

/// Why the Audit tab shows no rows.
enum AuditNote {
  /// The user may not read the site's audit.
  needsRights,
  none;

  String get text => switch (this) {
    needsRights => S.current.auditNeeds,
    none => S.current.noAuditHere,
  };
}

/// The board's word for a modbus point's `edit` parameter.
enum PointFieldWord {
  area,
  address,
  dataType,
  bit,
  registers,
  wordOrder,
  unit,
  scale,
  offset,
  precision,
  writable,
  writableByMaster;

  String get label => switch (this) {
    area => S.current.fieldArea,
    address => S.current.fieldAddress,
    dataType => S.current.fieldDataType,
    bit => S.current.fieldBit,
    registers => S.current.fieldRegisters,
    wordOrder => S.current.fieldWordOrder,
    unit => S.current.fieldUnit,
    scale => S.current.fieldScale,
    offset => S.current.fieldOffset,
    precision => S.current.fieldPrecision,
    writable => S.current.fieldWritable,
    writableByMaster => S.current.fieldWritableByMaster,
  };
}

/// The word order a modbus data type's suffix sets.
enum WordOrderTag {
  abcd,
  cdab,
  badc,
  dcba;

  /// `CDAB`.
  String get text => name.toUpperCase();
}

/// One field of an `edit`: its change is staged at once. [word] names it
/// when the board has a word for it, else [label] (the domain's).
/// [missing]: the driver has no parameter for it (shown, disabled).
final class ExplorerFieldVm extends Equatable {
  const ExplorerFieldVm({
    required this.id,
    required this.code,
    required this.label,
    required this.kind,
    this.word,
    this.value,
    this.choices = const [],
    this.choiceLabels = const {},
    this.description,
    this.missing = false,
  });

  final String id;

  /// The parameter's name, handed back with a change.
  final String code;
  final String label;
  final PointFieldWord? word;
  final ParamKind kind;

  /// The value shown (a [WordOrderTag] for the word order).
  final Object? value;
  final List<String> choices;
  final Map<String, String> choiceLabels;
  final String? description;
  final bool missing;

  @override
  List<Object?> get props => [
    id,
    code,
    label,
    word,
    kind,
    value,
    choices,
    choiceLabels,
    description,
    missing,
  ];
}

/// A section of the inspector or of the Parameters tab.
sealed class ExplorerSectionVm extends Equatable {
  const ExplorerSectionVm();
}

/// A flow's `~val`: state, version, who deployed it, since, the error.
final class FlowStateSectionVm extends ExplorerSectionVm {
  const FlowStateSectionVm({
    required this.state,
    this.version,
    this.deployedBy,
    this.since,
    this.problem,
  });

  final FlowStateTag state;
  final int? version;
  final String? deployedBy;
  final DateTime? since;
  final String? problem;

  @override
  List<Object?> get props => [state, version, deployedBy, since, problem];
}

/// The node's `edit` as fields of [node], else its `cfg` as facts.
final class ParamsSectionVm extends ExplorerSectionVm {
  const ParamsSectionVm({
    required this.node,
    this.fields = const [],
    this.cfg = const [],
    this.noEdit = false,
  });

  final String node;
  final List<ExplorerFieldVm> fields;

  /// `cfg` as (name, label, value).
  final List<(String, String, String)> cfg;

  /// The node has neither an `edit` nor a `cfg`.
  final bool noEdit;

  @override
  List<Object?> get props => [node, fields, cfg, noEdit];
}

/// The node's `attr`.
final class AttributesSectionVm extends ExplorerSectionVm {
  const AttributesSectionVm(this.attr);

  final List<(String, String)> attr;

  @override
  List<Object?> get props => [attr];
}

/// The framework's diagnostic values, as (name, label, value).
final class DiagnosticsSectionVm extends ExplorerSectionVm {
  const DiagnosticsSectionVm(this.facts);

  final List<(String, String, String)> facts;

  @override
  List<Object?> get props => [facts];
}

/// A point with no `edit`: its type, unit and level, read only.
final class PointFactsSectionVm extends ExplorerSectionVm {
  const PointFactsSectionVm({this.type, this.unit, this.level});

  final String? type;
  final String? unit;

  /// The level a set needs; null: read only.
  final String? level;

  @override
  List<Object?> get props => [type, unit, level];
}

/// A point's register fields, or its value fields.
final class PointFieldsSectionVm extends ExplorerSectionVm {
  const PointFieldsSectionVm({
    required this.node,
    required this.value,
    required this.fields,
  });

  final String node;

  /// The value fields (three columns); else the register's.
  final bool value;
  final List<ExplorerFieldVm> fields;

  @override
  List<Object?> get props => [node, value, fields];
}

/// A point's poll rate: the segments of the rates, the one now, the one
/// before a staged edit.
final class PollingSectionVm extends ExplorerSectionVm {
  const PollingSectionVm({
    required this.node,
    required this.code,
    required this.rates,
    required this.now,
    required this.was,
    required this.staged,
  });

  final String node;

  /// The poll parameter's name, handed back with a change.
  final String code;
  final List<double> rates;
  final num? now;
  final num? was;
  final bool staged;

  @override
  List<Object?> get props => [node, code, rates, now, was, staged];
}

/// A point's write fields; a toggle says it needs [level].
final class WriteSectionVm extends ExplorerSectionVm {
  const WriteSectionVm({
    required this.node,
    required this.fields,
    required this.level,
  });

  final String node;
  final List<ExplorerFieldVm> fields;
  final String level;

  @override
  List<Object?> get props => [node, fields, level];
}

/// What the tree publishes for the point: its `~meta` and its `~val`.
final class PublishSectionVm extends ExplorerSectionVm {
  const PublishSectionVm({
    required this.writable,
    this.type,
    this.unit,
    this.value,
    this.quality,
    this.time,
  });

  final String? type;
  final String? unit;
  final bool writable;

  /// The sample's value as the user reads it; null: none read.
  final String? value;
  final SampleMark? quality;
  final DateTime? time;

  @override
  List<Object?> get props => [type, unit, writable, value, quality, time];
}

/// What the inspector shows: a point, an action's form, or the node on
/// screen.
sealed class ExplorerInspectorVm extends Equatable {
  const ExplorerInspectorVm();
}

/// A point (docs/design/specs/explorer.md §4): its name and display name,
/// its value and quality, then its sections.
final class PointInspectorVm extends ExplorerInspectorVm {
  const PointInspectorVm({
    required this.name,
    required this.mark,
    required this.sections,
    this.display,
    this.value,
    this.time,
    this.fails = const [],
    this.failKey = '',
    this.edit,
    this.editValue,
    this.choices = const [],
    this.choiceLabels = const {},
    this.readOnly,
  });

  final String name;
  final String? display;

  /// The value with its unit; null: `—` (none, or a read failed).
  final String? value;
  final SampleMark mark;

  /// When the value was read.
  final DateTime? time;
  final List<ExplorerSectionVm> sections;

  /// The reads that failed, of the point [failKey].
  final List<ReadFailed> fails;
  final String failKey;

  /// How a new value is typed; null when the point cannot be set.
  final ParamKind? edit;
  final Object? editValue;
  final List<String> choices;
  final Map<String, String> choiceLabels;
  final Disabled? readOnly;

  ReadFailVm? get fail => fails.isEmpty ? null : ReadFailVm.of(failKey, fails);

  @override
  List<Object?> get props => [
    name,
    display,
    value,
    mark,
    time,
    sections,
    fails,
    failKey,
    edit,
    editValue,
    choices,
    choiceLabels,
    readOnly,
  ];
}

/// An action: its form, Run now or Stage, the CLI line.
final class ActionInspectorVm extends ExplorerInspectorVm {
  const ActionInspectorVm({
    required this.id,
    required this.title,
    required this.keyName,
    required this.staged,
    required this.level,
    required this.fields,
    required this.cli,
    required this.user,
    this.result,
    this.disabled,
  });

  final String id;
  final String title;
  final String keyName;

  /// A `config` action: staged, not run.
  final bool staged;
  final String level;
  final String? result;
  final List<ParamFieldVm> fields;
  final String cli;

  /// Who a run runs as.
  final String user;
  final Disabled? disabled;

  @override
  List<Object?> get props => [
    id,
    title,
    keyName,
    staged,
    level,
    result,
    fields,
    cli,
    user,
    disabled,
  ];
}

/// The node on screen with no point selected (§4 "nothing selected").
final class NodeInspectorVm extends ExplorerInspectorVm {
  const NodeInspectorVm({
    required this.kind,
    required this.title,
    required this.sections,
    this.name,
    this.fails = const [],
    this.failKey = '',
  });

  final NodeKindTag kind;

  /// The node's display name, else its name.
  final String title;

  /// The node's name under a [title] that is its display name.
  final String? name;
  final List<ExplorerSectionVm> sections;
  final List<ReadFailed> fails;
  final String failKey;

  ReadFailVm? get fail => fails.isEmpty ? null : ReadFailVm.of(failKey, fails);

  @override
  List<Object?> get props => [kind, title, name, sections, fails, failKey];
}

/// An item of the node menu: an action of the node.
final class ExplorerMenuItemVm extends Equatable {
  const ExplorerMenuItemVm({
    required this.name,
    required this.label,
    required this.level,
    this.form = false,
    this.danger = false,
    this.disabled,
  });

  final String name;
  final String label;
  final String level;

  /// It opens a form (it has parameters): `…` after its label.
  final bool form;
  final bool danger;
  final Disabled? disabled;

  @override
  List<Object?> get props => [name, label, level, form, danger, disabled];
}

/// A group of the node menu: the action `group`, else Configure · staged
/// or Operate · runs now.
final class ExplorerMenuGroupVm extends Equatable {
  const ExplorerMenuGroupVm({
    required this.items,
    this.group,
    this.staged = false,
  });

  final String? group;
  final bool staged;
  final List<ExplorerMenuItemVm> items;

  @override
  List<Object?> get props => [group, staged, items];
}

/// The node menu of [key] (§5), once its `~meta` is read.
final class ExplorerMenuVm extends Equatable {
  const ExplorerMenuVm({
    required this.key,
    required this.name,
    required this.kind,
    required this.actions,
    required this.groups,
    this.driver,
  });

  final String key;
  final String name;
  final String? driver;
  final NodeKindTag kind;
  final int actions;
  final List<ExplorerMenuGroupVm> groups;

  @override
  List<Object?> get props => [key, name, driver, kind, actions, groups];
}
