// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/containers/inspector_sections.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/quality_mark.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/review_panel.dart';
import 'package:ui/pages/explorer_page.dart';
import 'package:ui/shell/studio_shell.dart';
import 'package:ui/shell/top_bar.dart';
import 'package:ui/shell/workspace_rail.dart';
import 'package:ui/tables/points_table.dart';
import 'package:ui/trees/node_tree.dart';
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
}) => StudioShell(
  rail: _rail,
  selected: 0,
  onSelect: _none,
  offline: offline,
  drawer: drawer,
  topBar: (compact) => TopBar(
    vm: TopBarVm(
      site: 'plant',
      siteDetail: 'via edge · central',
      sites: const [],
      connected: offline == null,
      changes: changes,
      user: 'olena',
      role: 'operator',
    ),
    compact: compact,
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
    meta: '4',
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/modbus',
    name: 'modbus',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    expanded: true,
    chip: 'Process',
    dot: Tone.good,
    dotLabel: 'Connected',
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/modbus/tcp-boiler',
    name: 'tcp-boiler',
    depth: 2,
    icon: 'node_conn',
    hasChildren: true,
    expanded: true,
    dot: Tone.good,
    dotLabel: 'Connected',
  ),
  TreeRowVm(
    id: _dev,
    name: 'plc1',
    depth: 3,
    icon: 'node_device',
    hasChildren: true,
    selected: true,
    meta: '9',
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/modbus/tcp-boiler/plc2',
    name: 'plc2',
    depth: 3,
    icon: 'node_device',
    hasChildren: true,
    meta: '14',
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/modbus/rtu-line1',
    name: 'rtu-line1',
    depth: 2,
    icon: 'node_conn',
    hasChildren: true,
    dot: Tone.warn,
    dotLabel: 'Connecting',
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/opc-ua',
    name: 'opc-ua',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    chip: 'Embedded',
    dot: Tone.good,
    dotLabel: 'Connected',
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/bacnet',
    name: 'bacnet',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    chip: 'WASM',
    dot: Tone.bad,
    dotLabel: 'Failed',
  ),
  TreeRowVm(
    id: 'wy/plant/downstream/field-gw',
    name: 'field-gw',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    chip: 'External',
    dot: Tone.warn,
    dotLabel: 'In quarantine',
  ),
  TreeRowVm(
    id: 'wy/plant/dataflows',
    name: 'dataflows',
    depth: 0,
    hasChildren: true,
    expanded: true,
    meta: '2',
  ),
  TreeRowVm(
    id: 'wy/plant/dataflows/tank-level',
    name: 'tank-level',
    depth: 1,
    icon: 'node_flow',
    dot: Tone.good,
    dotLabel: 'Deployed',
  ),
  TreeRowVm(
    id: 'wy/plant/dataflows/boiler-guard',
    name: 'boiler-guard',
    depth: 1,
    icon: 'node_flow',
    meta: 'draft',
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

const _good = QualityMarkVm(label: 'good', tone: Tone.good);

PointRowVm _p(
  String n,
  String l,
  String a,
  String t,
  String u,
  String v, {
  String poll = '1 s',
  String? was,
  QualityMarkVm q = _good,
  bool w = false,
  bool st = false,
  bool sel = false,
  bool stale = false,
}) => PointRowVm(
  id: '$_dev/$n',
  name: n,
  display: l,
  register: a,
  type: t,
  unit: u,
  poll: poll,
  pollWas: was,
  value: stale ? v : v,
  quality: stale
      ? const QualityMarkVm(
          label: 'stale',
          tone: Tone.neutral,
          mark: Mark.dashed,
        )
      : q,
  writable: w,
  staged: st,
  selected: sel,
  stale: stale,
);

List<PointRowVm> _points({bool select = true, bool stale = false}) => [
  _p('t1', 'Supply temp', 'HR 0', 'f32', '°C', '82.5', stale: stale),
  _p(
    't2',
    'Return temp',
    'HR 2',
    'f32',
    '°C',
    '64.1',
    poll: '500 ms',
    was: '1 s',
    st: true,
    sel: select,
    stale: stale,
  ),
  _p(
    't3',
    'Flue temp',
    'HR 6',
    'f32',
    '°C',
    '—',
    st: true,
    q: const QualityMarkVm(
      label: 'not applied',
      tone: Tone.neutral,
      mark: Mark.ring,
    ),
    stale: stale,
  ),
  _p('p1', 'Pressure', 'HR 4', 'f32', 'bar', '2.31', stale: stale),
  _p('pump', 'Pump run', 'Coil 0', 'binary', '—', 'on', w: true, stale: stale),
  _p('fan', 'Fan speed', 'HR 9', 'u16', '%', '72', st: true, stale: stale),
  _p(
    'flow',
    'Flow rate',
    'IR 0',
    'f32',
    'm³/h',
    '12.8',
    poll: '5 s',
    q: const QualityMarkVm(
      label: 'uncertain',
      tone: Tone.warn,
      mark: Mark.ring,
    ),
    stale: stale,
  ),
  _p(
    'valve',
    'Valve position',
    'HR 11',
    'u16',
    '%',
    '—',
    q: const QualityMarkVm(label: 'bad', tone: Tone.bad),
    w: true,
    stale: stale,
  ),
  _p('alarm', 'Alarm word', 'HR 19', 'bits16', '—', '0x0000', stale: stale),
];

const _tabs = [
  TabItemVm(id: 'points', label: 'Points', count: '9'),
  TabItemVm(id: 'params', label: 'Parameters'),
  TabItemVm(id: 'actions', label: 'Actions', count: '7'),
  TabItemVm(id: 'history', label: 'History'),
  TabItemVm(id: 'audit', label: 'Audit'),
];

const _toolbar = [
  ToolButtonVm(id: 'add_point', label: 'Add point', icon: 'ui_add'),
  ToolButtonVm(
    id: 'import',
    label: 'Import CSV or DSA tree',
    icon: 'ui_upload',
    quiet: true,
  ),
  ToolButtonVm(
    id: 'apply_profile',
    label: 'Apply profile',
    icon: 'ui_profile',
    quiet: true,
    disabledReason:
        'The broker has no action to apply a profile to a device yet.',
  ),
];

ParamFieldVm _f(
  String id,
  String label,
  Object? value, {
  ParamKind kind = ParamKind.text,
  List<String> choices = const [],
  bool enabled = true,
  String? description,
}) => ParamFieldVm(
  id: id,
  label: label,
  kind: kind,
  value: value,
  choices: choices,
  enabled: enabled,
  description: description,
  onChanged: _none,
);

PointInspectorVm _pointInspector() => PointInspectorVm(
  eyebrow: 'Point',
  name: 't2',
  display: 'Return temp',
  value: '64.1 °C',
  quality: const QualityMarkVm(label: 'good · 12:00:03', tone: Tone.good),
  sections: [
    InspectorSectionVm(
      label: 'Register',
      fields: [
        _f(
          'table',
          'Area',
          'holding',
          kind: ParamKind.choice,
          choices: const ['coil', 'discrete', 'input', 'holding'],
        ),
        _f('addr', 'Address', 2, kind: ParamKind.number),
        _f(
          'dtype',
          'Data type',
          'f32',
          kind: ParamKind.choice,
          choices: const ['u16', 'f32', 'f32_wswap'],
        ),
        _f('word_order', 'Word order', 'ABCD', enabled: false),
      ],
    ),
    InspectorSectionVm(
      label: 'Value',
      columns: 3,
      fields: [
        _f('unit', 'Unit', '°C'),
        _f('scale', 'Scale', 1.0, kind: ParamKind.number),
        _f('precision', 'Precision', null, enabled: false),
      ],
    ),
    const InspectorSectionVm(
      label: 'Polling',
      note: 'staged · was 1 s',
      segments: ['250 ms', '500 ms', '1 s', '5 s'],
      segment: 1,
      onSegment: _none,
    ),
    InspectorSectionVm(
      label: 'Write',
      fields: [
        _f(
          'writable',
          'Writable',
          false,
          kind: ParamKind.toggle,
          description: 'Turning this on needs config level',
        ),
      ],
    ),
    const InspectorSectionVm(
      label: 'What the tree will publish',
      code: [
        ('~meta', '{type: number, unit: °C, writable: false}'),
        ('~val', '{v: 64.1, q: good, t: 12:00:03}'),
      ],
    ),
  ],
);

NodeInspectorVm _deviceInspector() => NodeInspectorVm(
  eyebrow: 'Device',
  title: 'plc1',
  sections: [
    InspectorSectionVm(
      label: 'Parameters',
      fields: [
        _f('unit', 'unit', 1, kind: ParamKind.number),
        _f(
          'ping',
          'ping',
          'probe',
          kind: ParamKind.choice,
          choices: const ['probe', 'fc17', 'none'],
        ),
        _f('ping_s', 'ping_s', 5.0, kind: ParamKind.number),
        _f('max_regs', 'max_regs', 125, kind: ParamKind.number),
        _f('contiguous_only', 'contiguous_only', false, kind: ParamKind.toggle),
      ],
    ),
    const InspectorSectionVm(
      label: 'Diagnostics',
      facts: [
        FactVm(label: 'requests', value: '18 342', mono: true),
        FactVm(label: 'errors', value: '0', mono: true),
        FactVm(label: 'timeouts', value: '2', mono: true),
        FactVm(label: 'last_rtt_ms', value: '4 ms', mono: true),
        FactVm(label: 'avg_rtt_ms', value: '5.2 ms', mono: true),
      ],
    ),
  ],
);

ExplorerPage _page({
  List<PointRowVm>? points,
  ExplorerInspectorVm? inspector,
  String? empty,
  StatusPillVm pill = const StatusPillVm(label: 'Connected', tone: Tone.good),
}) => ExplorerPage(
  treeLabel: 'Tree · plant',
  tree: _tree(),
  onTap: _none,
  onToggle: _none,
  onMenu: (_, _) {},
  onTreeFilter: _none,
  treeFilterHint: 'Filter',
  treeNote: const TreeNoteVm(
    lead: 'The tree shows data only.',
    code: 'sys/**',
    middle: 'is edited in',
    and: 'and',
    links: [
      ('links', 'Links'),
      ('access', 'Access'),
      ('sites', 'Sites'),
      ('system', 'System'),
    ],
  ),
  keyName: _dev,
  onCopyKey: () {},
  title: 'plc1',
  pill: pill,
  subtitle: 'modbus device · unit 1 · 10.0.4.20:502 · last read 12:00:03',
  headerButtons: const [
    ToolButtonVm(
      id: 'ping',
      label: 'Ping',
      disabledReason:
          'This node has no ping action: the driver pings by itself (cfg ping).',
    ),
  ],
  actionsLabel: 'Actions',
  onActions: _none,
  onTool: _none,
  tabs: _tabs,
  tab: 'points',
  onTab: _none,
  toolbar: _toolbar,
  onPointFilter: _none,
  pointFilterHint: 'Filter points',
  points: points ?? _points(),
  pointsEmpty: empty,
  emptyButtons: _toolbar.take(2).toList(),
  pointsNote:
      'Values update live. Edits are staged in this session; nothing is written to the device until you apply.',
  onPoint: _none,
  onCheck: _none,
  onRange: _none,
  onCheckAll: () {},
  inspector: inspector ?? _pointInspector(),
);

/// A device with a point selected (board *Main*).
Widget explorerPoint() => _shell(_page());

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
      note:
          'Each write is checked by the link and recorded in sys/audit/modbus. A value shows only after it is read back.',
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
    empty: 'No points yet',
    inspector: _deviceInspector(),
  ),
  changes: 0,
);

/// The gateway lost: the banner, values greyed, quality stale.
Widget explorerOffline() => _shell(
  _page(
    points: _points(stale: true),
    inspector: PointInspectorVm(
      eyebrow: 'Point',
      name: 't2',
      display: 'Return temp',
      value: '64.1 °C',
      quality: const QualityMarkVm(
        label: 'stale',
        tone: Tone.neutral,
        mark: Mark.dashed,
      ),
      sections: _pointInspector().sections,
    ),
  ),
  offline:
      'The gateway connection is lost. Reconnecting; values on screen are the last ones received.',
);
