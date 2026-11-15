// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:material_ui/material_ui.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/level_badge.dart';
import 'package:ui/indicators/node_state.dart';
import 'package:ui/indicators/quality_mark.dart';
import 'package:ui/indicators/sample_mark.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/indicators/value_type.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/overlays/review_panel.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/explorer_page.dart';
import 'package:ui/shell/studio_shell.dart';
import 'package:ui/shell/top_bar.dart';
import 'package:ui/shell/window_bar.dart';
import 'package:ui/shell/window_controls.dart';
import 'package:ui/shell/workspace_rail.dart';
import 'package:ui/tables/points_table.dart';
import 'package:ui/trees/tree_row.dart';

// The data of board *Studio · Explorer* (canvas `Main.dc.html`) as the
// connector would hand it: the shell, the tree of plant, device plc1 and
// its points; docs/design/specs/explorer.md §9 names the frames.

void _none(Object? _) {}

const _dev = 'wy/plant/downstream/modbus/tcp-boiler/plc1';

const _rail = [
  RailItemVm(icon: 'ws_explorer', label: 'Explorer'),
  RailItemVm(icon: 'ws_links', label: 'Links'),
  RailItemVm(icon: 'ws_flows', label: 'Flows'),
  RailItemVm(icon: 'ws_history', label: 'History'),
  RailItemVm(icon: 'ws_access', label: 'Access'),
  RailItemVm(icon: 'ws_sites', label: 'Sites'),
  RailItemVm(icon: 'ws_assistant', label: 'Assistant'),
  RailItemVm(icon: 'ws_system', label: 'System'),
];

Widget _shell(
  Widget child, {
  String? offline,
  Widget? drawer,
  int changes = 3,
  String site = 'plant',
  String route = 'via edge · central',
  WindowBarVm window = const WindowBarVm(),
}) => StudioShell(
  rail: _rail,
  selected: 0,
  onSelect: _none,
  offline: offline,
  drawer: drawer,
  topBar: (_, compact, _) => TopBar(
    vm: TopBarVm(
      site: site,
      siteDetail: route,
      sites: const [],
      connected: offline == null,
      changes: changes,
      user: 'olena',
      role: 'operator',
    ),
    compact: compact,
    window: window,
    onSite: _none,
    onSearch: () {},
    onReview: () {},
    onLogOut: () {},
  ),
  child: child,
);

List<TreeRowVm> _tree() => const [
  TreeRowVm(
    id: 'wy/plant/downstream',
    name: 'downstream',
    depth: 0,
    hasChildren: true,
    expanded: true,
    count: 4,
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/modbus',
    name: 'modbus',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    expanded: true,
    mode: .process,
    state: .connected,
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/modbus/tcp-boiler',
    name: 'tcp-boiler',
    depth: 2,
    icon: 'node_conn',
    hasChildren: true,
    expanded: true,
    state: .connected,
  ),
  TreeRowVm(
    id: _dev,
    name: 'plc1',
    depth: 3,
    icon: 'node_device',
    hasChildren: true,
    selected: true,
    count: 9,
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/modbus/tcp-boiler/plc2',
    name: 'plc2',
    depth: 3,
    icon: 'node_device',
    hasChildren: true,
    count: 14,
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/modbus/rtu-line1',
    name: 'rtu-line1',
    depth: 2,
    icon: 'node_conn',
    hasChildren: true,
    state: .starting,
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/opc-ua',
    name: 'opc-ua',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    mode: .embedded,
    state: .connected,
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/bacnet',
    name: 'bacnet',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    mode: .wasm,
    state: .failed,
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/field-gw',
    name: 'field-gw',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    mode: .external,
    state: .starting,
  ),
  TreeRowVm(
    id: 'wy/plant/dataflows',
    name: 'dataflows',
    depth: 0,
    hasChildren: true,
    expanded: true,
    count: 2,
  ),
  TreeRowVm(
    id: 'wy/plant/dataflows/tank-level',
    name: 'tank-level',
    depth: 1,
    icon: 'node_flow',
    state: .connected,
  ),
  TreeRowVm(
    id: 'wy/plant/dataflows/boiler-guard',
    name: 'boiler-guard',
    depth: 1,
    icon: 'node_flow',
    draft: true,
  ),
  TreeRowVm(
    id: 'wy/plant/storage',
    name: 'storage',
    depth: 0,
    hasChildren: true,
  ),
  TreeRowVm(
    id: 'wy/plant/upstream',
    name: 'upstream',
    depth: 0,
    hasChildren: true,
  ),
];

ModbusRegisterVm _hr(int addr, [RegisterArea area = .holding]) =>
    ModbusRegisterVm(addr: '$addr', area: area);

PointRowVm _p(
  String n,
  String l,
  RegisterVm a,
  String t,
  String? u,
  String? v, {
  num poll = 1,
  num? was,
  SampleMark q = .good,
  bool w = false,
  bool st = false,
  bool sel = false,
  bool stale = false,
}) => PointRowVm(
  id: '$_dev/$n',
  name: n,
  display: l,
  register: a,
  dtype: t,
  unit: u,
  poll: poll,
  pollWas: was,
  value: v,
  mark: stale ? .stale : q,
  writable: w,
  staged: st,
  selected: sel,
  stale: stale,
);

List<PointRowVm> _points({bool select = true, bool stale = false}) => [
  _p('t1', 'Supply temp', _hr(0), 'f32', '°C', '82.5', stale: stale),
  _p(
    't2',
    'Return temp',
    _hr(2),
    'f32',
    '°C',
    '64.1',
    poll: 0.5,
    was: 1,
    st: true,
    sel: select,
    stale: stale,
  ),
  _p(
    't3',
    'Flue temp',
    _hr(6),
    'f32',
    '°C',
    null,
    st: true,
    q: .notApplied,
    stale: stale,
  ),
  _p('p1', 'Pressure', _hr(4), 'f32', 'bar', '2.31', stale: stale),
  _p(
    'pump',
    'Pump run',
    _hr(0, .coil),
    'binary',
    null,
    'on',
    w: true,
    stale: stale,
  ),
  _p('fan', 'Fan speed', _hr(9), 'u16', '%', '72', st: true, stale: stale),
  _p(
    'flow',
    'Flow rate',
    _hr(0, .input),
    'f32',
    'm³/h',
    '12.8',
    poll: 5,
    q: .uncertain,
    stale: stale,
  ),
  _p(
    'valve',
    'Valve position',
    _hr(11),
    'u16',
    '%',
    null,
    q: .bad,
    w: true,
    stale: stale,
  ),
  _p('alarm', 'Alarm word', _hr(19), 'bits16', null, '0x0000', stale: stale),
];

const _tabs = [
  ExplorerTabVm(.points, count: 9),
  ExplorerTabVm(.parameters),
  ExplorerTabVm(.actions, count: 7),
  ExplorerTabVm(.history),
  ExplorerTabVm(.audit),
];

const _toolbar = [
  ToolButtonVm(.addPoint),
  ToolButtonVm(.importPoints),
  ToolButtonVm(.applyProfile, disabled: NotThere(.profile)),
];

ExplorerFieldVm _f(
  String code,
  Object? value, {
  PointFieldWord? word,
  ParamKind kind = ParamKind.text,
  List<String> choices = const [],
  bool missing = false,
}) => ExplorerFieldVm(
  code: code,
  label: code,
  word: word,
  kind: kind,
  value: value,
  choices: choices,
  missing: missing,
);

const _node = '$_dev/t2';

PointInspectorVm _pointInspector() => PointInspectorVm(
  key: _node,
  name: 't2',
  display: 'Return temp',
  value: '64.1 °C',
  mark: .good,
  time: DateTime(2026, 11, 8, 12, 0, 3),
  sections: [
    PointFieldsSectionVm(
      node: _node,
      value: false,
      fields: [
        _f(
          'table',
          'holding',
          word: .area,
          kind: ParamKind.choice,
          choices: const ['coil', 'discrete', 'input', 'holding'],
        ),
        _f('addr', 2, word: .address, kind: ParamKind.number),
        _f(
          'dtype',
          'f32',
          word: .dataType,
          kind: ParamKind.choice,
          choices: const ['u16', 'f32', 'f32_wswap'],
        ),
        _f('word_order', WordOrderTag.abcd, word: .wordOrder, missing: true),
      ],
    ),
    PointFieldsSectionVm(
      node: _node,
      value: true,
      fields: [
        _f('unit', '°C', word: .unit),
        _f('scale', 1.0, word: .scale, kind: ParamKind.number),
        _f('precision', null, word: .precision, missing: true),
      ],
    ),
    const PollingSectionVm(
      node: _node,
      code: 'poll_s',
      rates: [0.25, 0.5, 1, 5],
      now: 0.5,
      was: 1,
      staged: true,
    ),
    WriteSectionVm(
      node: _node,
      level: AccessLevel.config,
      fields: [_f('writable', false, word: .writable, kind: ParamKind.toggle)],
    ),
    PublishSectionVm(
      type: ValueType.number,
      unit: '°C',
      writable: false,
      value: '64.1',
      quality: .good,
      time: DateTime(2026, 11, 8, 12, 0, 3),
    ),
  ],
);

NodeInspectorVm _deviceInspector() => NodeInspectorVm(
  key: _dev,
  kind: .device,
  title: 'plc1',
  sections: [
    ParamsSectionVm(
      node: _dev,
      fields: [
        _f('unit', 1, kind: ParamKind.number),
        _f(
          'ping',
          'probe',
          kind: ParamKind.choice,
          choices: const ['probe', 'fc17', 'none'],
        ),
        _f('ping_s', 5.0, kind: ParamKind.number),
        _f('max_regs', 125, kind: ParamKind.number),
        _f('contiguous_only', false, kind: ParamKind.toggle),
      ],
    ),
    const DiagnosticsSectionVm([
      FactRowVm('requests', 'requests', '18 342'),
      FactRowVm('errors', 'errors', '0'),
      FactRowVm('timeouts', 'timeouts', '2'),
      FactRowVm('last_rtt_ms', 'last_rtt_ms', '4 ms'),
      FactRowVm('avg_rtt_ms', 'avg_rtt_ms', '5.2 ms'),
    ]),
  ],
);

ExplorerPage _page({
  List<PointRowVm>? points,
  ExplorerInspectorVm? inspector,
  PointsEmpty? empty,
  StatusPillVm? pill,
  SidePanelWidths panels = const SidePanelWidths(),
  ValueViewerVm? viewer,
  String title = 'plc1',
  String? titleName,
}) => ExplorerPage(
  site: 'plant',
  tree: _tree(),
  onTap: _none,
  onToggle: _none,
  onOpenMenu: _none,
  onTreeFilter: _none,
  onNoteLink: _none,
  keyName: _dev,
  onCopy: _none,
  title: title,
  titleName: titleName,
  pill: pill ?? NodeState.connected.pill(),
  subtitle: ExplorerSubtitleVm(
    kind: .device,
    driver: 'modbus',
    unit: '1',
    host: '10.0.4.20',
    port: '502',
    lastRead: DateTime(2026, 11, 8, 12, 0, 3),
  ),
  headerButtons: const [ToolButtonVm(.ping, disabled: NotThere(.ping))],
  onTool: _none,
  tabs: _tabs,
  tab: .points,
  onTab: _none,
  onTapFlowEditor: _none,
  toolbar: _toolbar,
  onPointFilter: _none,
  points: points ?? _points(),
  pointsEmpty: empty,
  emptyButtons: _toolbar.take(2).toList(),
  onPoint: _none,
  onCheck: _none,
  onRange: _none,
  onCheckAll: () {},
  inspector: inspector ?? _pointInspector(),
  panels: panels,
  onViewPoint: () {},
  viewer: viewer,
  onCloseViewer: () {},
);

/// A device with a point selected (board *Main*).
Widget explorerPoint() => _shell(_page());

/// A device titled [title], with its name [titleName] under it when the
/// title is its display name.
Widget explorerTitled({required String title, String? titleName}) =>
    _shell(_page(title: title, titleName: titleName));

/// macOS without a title bar (docs/studio.md §7.1): the top bar keeps 92
/// free at the left for the native close, minimize and zoom buttons (the
/// system draws them; a golden shows the room).
Widget explorerWindowMacos() => _shell(
  _page(),
  window: WindowBarVm(leading: 92, onDrag: () {}, onZoom: () {}),
);

/// Windows and Linux without a title bar: the top bar keeps the room of
/// the three window buttons at the right, and the app draws them over the
/// corner, as `WindowControlsConnector` does.
Widget explorerWindowControls({bool maximized = false}) => Stack(
  children: [
    Positioned.fill(
      child: _shell(
        _page(),
        window: WindowBarVm(
          trailing: WindowControls.width,
          onDrag: () {},
          onZoom: () {},
        ),
      ),
    ),
    Positioned(
      top: 0,
      right: 0,
      child: WindowControls(
        vm: WindowControlsVm(maximized: maximized),
        onMinimize: () {},
        onMaximize: () {},
        onClose: () {},
      ),
    ),
  ],
);

/// The point's value in the viewer: a number with its unit and quality.
Widget explorerViewer() => _shell(
  _page(
    viewer: const ValueViewerVm(
      title: 'downstream/modbus/plc1/level',
      type: 'number',
      copy: '72.4',
      quality: QualityMarkVm(label: 'good · 12:00:03', tone: .good),
      content: NumberContentVm('72.4', unit: '%'),
    ),
  ),
);

/// Nothing selected: the device's parameters and diagnostics.
Widget explorerDevice() => _shell(
  _page(points: _points(select: false), inspector: _deviceInspector()),
);

/// The review drawer open over the screen.
Widget explorerReview() => _shell(
  _page(),
  drawer: ReviewPanel(
    cards: const [
      ChangeCardVm(
        id: '1',
        op: 'Edit',
        key_: '…/tcp-boiler/plc1/t2',
        field: 'poll',
        from: '1 s',
        to: '500 ms',
        levelText: 'Needs config · you have it',
        allowed: true,
      ),
      ChangeCardVm(
        id: '2',
        op: 'Add',
        key_: '…/tcp-boiler/plc1',
        field: 'add_point',
        from: '—',
        to: 'name: t3, table: holding, addr: 6, dtype: f32',
        levelText: 'Needs config · you have it',
        allowed: true,
      ),
      ChangeCardVm(
        id: '3',
        op: 'Edit',
        key_: '…/tcp-boiler/plc1/fan',
        field: 'writable',
        from: 'false',
        to: 'true',
        levelText: 'Needs config · you have write',
        allowed: false,
      ),
    ],
    labels: const ReviewLabels(
      title: '3 staged changes',
      rights: 'Site plant · applied with your rights: olena, operator (write)',
      apply: 'Apply 2 changes',
      ask: 'Ask an admin for 1',
      askReason: 'The broker has no call to send a request to an admin yet.',
      discard: 'Discard all',
      empty: 'Nothing staged.',
      note: 'Each write is checked by the link and recorded in sys/audit/modbus. A value shows only after it is read back.',
      audit: 'sys/audit/modbus',
      refused: 'The broker refused a change',
    ),
    onApply: () {},
    onDiscard: () {},
    onClose: () {},
    onRemove: _none,
  ),
);

/// A device with no points yet.
Widget explorerEmpty() => _shell(
  _page(
    points: const [],
    empty: .noPointsYet,
    inspector: _deviceInspector(),
  ),
  changes: 0,
);

/// The gateway lost: the banner, values greyed, quality stale.
Widget explorerOffline() => _shell(
  _page(
    points: _points(stale: true),
    inspector: PointInspectorVm(
      key: _node,
      name: 't2',
      display: 'Return temp',
      value: '64.1 °C',
      mark: .stale,
      sections: _pointInspector().sections,
    ),
  ),
  offline: 'The gateway connection is lost. Reconnecting; values on screen are the last ones received.',
);

/// The point frame after the viewer dragged the panel edges: a wider tree,
/// a narrower inspector (spec §1, resizable side panels).
Widget explorerResized() => _shell(
  _page(panels: const SidePanelWidths(left: 380, right: 290)),
);

// Frames by node kind (docs/design/specs/explorer.md "Frames by node
// kind"), from the demo's `edge` site.

const _edge = 'wy/edge';
const _flowKey = '$_edge/dataflows/ahu2_ctl';
const _flowDisplay =
    'ahu2: count mod 10 × 10 → mockdev knob on change; temp in °F; a warm flag';

List<TreeRowVm> _edgeTree(String selected, {String? longName}) => [
  const TreeRowVm(
    id: '$_edge/downstream',
    name: 'downstream',
    depth: 0,
    hasChildren: true,
    expanded: true,
    count: 3,
  ),
  const TreeRowVm(
    id: '$_edge/downstream/modbus',
    name: 'modbus',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    expanded: true,
    mode: .embedded,
    state: .connected,
  ),
  const TreeRowVm(
    id: '$_edge/downstream/modbus/line1',
    name: 'line1',
    depth: 2,
    icon: 'node_conn',
    hasChildren: true,
    expanded: true,
  ),
  TreeRowVm(
    id: '$_edge/downstream/modbus/line1/${longName ?? 'ahu1'}',
    name: longName ?? 'ahu1',
    depth: 3,
    icon: 'node_device',
    selected: selected.endsWith('/${longName ?? 'ahu1'}'),
  ),
  const TreeRowVm(
    id: '$_edge/downstream/mock',
    name: 'mock',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    mode: .embedded,
    state: .connected,
  ),
  const TreeRowVm(
    id: '$_edge/dataflows',
    name: 'dataflows',
    depth: 0,
    hasChildren: true,
    expanded: true,
    count: 1,
  ),
  TreeRowVm(
    id: _flowKey,
    name: 'ahu2_ctl',
    depth: 1,
    icon: 'node_flow',
    hasChildren: true,
    selected: selected == _flowKey,
  ),
  const TreeRowVm(
    id: '$_edge/storage',
    name: 'storage',
    depth: 0,
    hasChildren: true,
    expanded: true,
    count: 1,
  ),
  TreeRowVm(
    id: '$_edge/storage/line1',
    name: 'line1',
    depth: 1,
    icon: 'node_storage',
    hasChildren: true,
    selected: selected == '$_edge/storage/line1',
  ),
  const TreeRowVm(
    id: '$_edge/upstream',
    name: 'upstream',
    depth: 0,
    hasChildren: true,
  ),
];

ExplorerPage _edgePage({
  required String keyName,
  required List<TreeRowVm> tree,
  required String title,
  required ExplorerSubtitleVm subtitle,
  required List<ExplorerTabVm> tabs,
  required ExplorerTabTag tab,
  StatusPillVm? pill,
  String? flowId,
  List<ToolButtonVm> headerButtons = const [],
  List<ExplorerSectionVm> params = const [],
  List<ChildRowVm> children = const [],
  List<PointRowVm> points = const [],
  ExplorerInspectorVm? inspector,
}) => ExplorerPage(
  site: 'edge',
  tree: tree,
  onTap: _none,
  onToggle: _none,
  onOpenMenu: _none,
  onTreeFilter: _none,
  keyName: keyName,
  onCopy: _none,
  title: title,
  pill: pill,
  subtitle: subtitle,
  flowId: flowId,
  onTapFlowEditor: _none,
  headerButtons: headerButtons,
  onTool: _none,
  tabs: tabs,
  tab: tab,
  onTab: _none,
  toolbar: _toolbar,
  onPointFilter: _none,
  points: points,
  onPoint: _none,
  onCheck: _none,
  onRange: _none,
  onCheckAll: () {},
  params: params,
  children: children,
  onChild: _none,
  inspector: inspector,
);

final _flowState = FlowStateSectionVm(
  state: .deployed,
  version: 2,
  deployedBy: 'user:admin@central',
  since: DateTime(2026, 11, 8, 8, 3, 19),
);

const _flowAttributes = AttributesSectionVm([
  FactRowVm('display', 'display', _flowDisplay),
  FactRowVm('version', 'version', '2'),
]);

/// A flow selected: its name, its state from `~val`, Edit dataflow, and no
/// points.
Widget explorerFlow() => _shell(
  _edgePage(
    keyName: _flowKey,
    tree: _edgeTree(_flowKey),
    title: 'ahu2_ctl',
    pill: FlowStateTag.deployed.pill(2),
    subtitle: const ExplorerSubtitleVm(
      kind: .dataflow,
      deployedBy: 'user:admin@central',
      description: _flowDisplay,
    ),
    flowId: 'ahu2_ctl',
    tabs: const [
      ExplorerTabVm(.parameters),
      ExplorerTabVm(.actions, count: 8),
      ExplorerTabVm(.audit),
    ],
    tab: .parameters,
    params: [_flowState, _flowAttributes],
    inspector: NodeInspectorVm(
      key: _flowKey,
      kind: .dataflow,
      title: 'ahu2_ctl',
      sections: [_flowState, _flowAttributes],
    ),
  ),
  changes: 0,
  site: 'edge',
  route: 'this broker',
);

/// A storage folder selected: its children as a table, a value of it in
/// the inspector.
Widget explorerFolder() => _shell(
  _edgePage(
    keyName: '$_edge/storage/line1',
    tree: _edgeTree('$_edge/storage/line1'),
    title: 'line1',
    subtitle: const ExplorerSubtitleVm(kind: .storage, children: 3),
    tabs: const [
      ExplorerTabVm(.contents, count: 3),
      ExplorerTabVm(.parameters),
      ExplorerTabVm(.actions, count: 5),
      ExplorerTabVm(.history),
      ExplorerTabVm(.audit),
    ],
    tab: .contents,
    children: const [
      ChildRowVm(
        key: '$_edge/storage/line1/fault',
        name: 'fault',
        type: ValueType.bool_,
        writable: true,
        value: 'false',
      ),
      ChildRowVm(
        key: '$_edge/storage/line1/temp',
        name: 'temp',
        display: 'Line 1 air temp',
        type: ValueType.number,
        writable: true,
        value: '21.5 °C',
        selected: true,
      ),
      ChildRowVm(
        key: '$_edge/storage/line1/test',
        name: 'test',
        kind: .storage,
      ),
    ],
    inspector: PointInspectorVm(
      key: '$_edge/storage/line1/temp',
      name: 'temp',
      display: 'Line 1 air temp',
      value: '21.5 °C',
      mark: .good,
      time: DateTime(2026, 11, 8, 8, 3, 19),
      sections: const [
        PointFactsSectionVm(
          type: ValueType.number,
          unit: '°C',
          level: AccessLevel.write,
        ),
      ],
      edit: ParamKind.number,
      editValue: 21.5,
    ),
  ),
  changes: 0,
  site: 'edge',
  route: 'this broker',
);

const _longName = 'supply_air_temperature_controller_north_wing_floor_2';
const _longDisplay =
    'North wing, floor 2: supply air temperature controller with the '
    'economiser, the frost guard and the night set-back schedule from the '
    'building management contract of 2019';

/// A device whose name and display name are both very long, on a narrow
/// window: every line ends in an ellipsis, nothing overflows.
Widget explorerLongName() => _shell(
  _edgePage(
    keyName: '$_edge/downstream/modbus/line1/$_longName',
    tree: _edgeTree(_longName, longName: _longName),
    title: _longName,
    pill: NodeState.connected.pill(),
    subtitle: ExplorerSubtitleVm(
      kind: .device,
      driver: 'modbus',
      unit: '1',
      host: '127.0.0.1',
      port: '5020',
      lastRead: DateTime(2026, 11, 8, 8, 3, 19),
      description: _longDisplay,
    ),
    headerButtons: const [ToolButtonVm(.ping)],
    tabs: _tabs,
    tab: .points,
    points: [
      const PointRowVm(
        id: '$_edge/downstream/modbus/line1/$_longName/$_longName',
        name: _longName,
        display: _longDisplay,
        register: ModbusRegisterVm(addr: '40003', area: .holding),
        dtype: 'f32_wbswap',
        unit: '°C',
        poll: 1,
        value: '21.5',
        mark: .good,
      ),
      ..._points(select: false),
    ],
    inspector: const PointInspectorVm(
      key: '$_edge/downstream/modbus/line1/$_longName/$_longName',
      name: _longName,
      display: _longDisplay,
      value: '21.5 °C',
      mark: .good,
      sections: [],
    ),
  ),
  changes: 0,
  site: 'edge',
  route: 'this broker',
);
