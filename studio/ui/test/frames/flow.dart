// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_legend.dart';
import 'package:ui/pages/flow_editor_page.dart';

// The data of boards *Flow editor · fields, bindings, properties* (FlowBind)
// and *· drag points and actions from the tree* (FlowTree), as
// FlowEditorPage arguments. The board's canvas has a 16 px margin; the
// blocks here carry it in their x and y.

const _m = 16.0;

const _actions = FlowBlockActions(
  onSelect: _id,
  onBind: _bindField,
  onRebind: _four,
  onUnbind: _two,
  onDropEntry: _three,
  onResize: _resize,
  refusal: _refusal,
);

/// Rows of the boards that are outputs only: a wire over one is refused.
const _outputsOnly = {'output', 'result', 'state', 't1', 't2', 'out'};

String? _refusal(
  FieldRefVm _,
  String _,
  String row, {
  (String, String)? replacing,
}) => _outputsOnly.contains(row) ? 'Outputs cannot be bound' : null;

void _id(String _) {}
void _four(String _, String _, String _, String _) {}
void _bindField(FieldRefVm _, String _, String _) {}
void _two(String _, String _) {}
void _three(String _, String _, String _) {}
void _resize(String _, {required bool add}) {}

List<TabItemVm> _tabs() => const [
  TabItemVm(id: 'blocks', label: 'Blocks'),
  TabItemVm(
    id: 'my',
    label: 'My blocks',
    disabledReason: 'Needs own blocks in the engine',
  ),
  TabItemVm(id: 'tree', label: 'Tree'),
];

const _legend = FlowLegendVm(
  reads: 'reads a value',
  writes: 'writes to a device',
  free: 'free field',
  readOnly: 'no left port = read-only point',
);

const _footer = [
  'Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.',
  'A bound field shows the value that comes in; its wire and source light when you point at it. The link icon goes to the source or unbinds.',
];

List<PaletteEntryVm> _blocks() => const [
  PaletteEntryVm(
    id: 'type:subscribe',
    title: 'Subscribe',
    tag: 'IN',
    group: 'Sources',
  ),
  PaletteEntryVm(
    id: 'type:if',
    title: 'If',
    tag: 'FX',
    group: 'Logic',
    detail: 'then when the inputs pass op, else otherwise.',
  ),
  PaletteEntryVm(id: 'type:case', title: 'Case', tag: 'FX', group: 'Logic'),
  PaletteEntryVm(id: 'type:router', title: 'Router', tag: 'FX', group: 'Logic'),
  PaletteEntryVm(id: 'type:hub', title: 'Hub', tag: 'FX', group: 'Logic'),
  PaletteEntryVm(
    id: 'type:expression',
    title: 'Script · rhai',
    tag: 'FX',
    group: 'Logic',
  ),
  PaletteEntryVm(id: 'type:delay', title: 'Delay', tag: 'FX', group: 'Logic'),
  PaletteEntryVm(id: 'type:state', title: 'State', tag: 'FX', group: 'Logic'),
  PaletteEntryVm(
    id: 'type:stopwatch',
    title: 'Stopwatch',
    tag: 'FX',
    group: 'Logic',
  ),
  PaletteEntryVm(id: 'type:trace', title: 'Trace', tag: 'FX', group: 'Logic'),
  PaletteEntryVm(
    id: 'type:catch',
    title: 'Catch error',
    tag: 'FX',
    group: 'Logic',
  ),
  PaletteEntryVm(id: 'type:repeat', title: 'Repeat', tag: 'RPT', group: 'Data'),
  PaletteEntryVm(id: 'type:table', title: 'Table', tag: 'TBL', group: 'Data'),
  PaletteEntryVm(
    id: 'type:object',
    title: 'Make object',
    tag: '{}',
    group: 'Data',
  ),
  PaletteEntryVm(id: 'type:dql', title: 'DQL query', tag: 'DQL', group: 'Data'),
  PaletteEntryVm(
    id: 'type:publish',
    title: 'Publish',
    tag: 'OUT',
    group: 'Sinks',
  ),
  PaletteEntryVm(
    id: 'type:wasm',
    title: 'WASM',
    tag: 'FX',
    group: 'Code · WASM',
  ),
];

/// The label a row reads for an engine name (flow-editor.md §3): fields
/// read in sentence case; point names, variables and item labels as given.
const _human = {
  'in': 'Input',
  'out': 'Output',
  'op': 'Operation',
  'input': 'Input',
  'output': 'Output',
  'else': 'Else',
  'expr': 'Expression',
  'result': 'Result',
  'key': 'Value name',
  'value': 'Value',
  'quality': 'Quality',
  'input_max': 'Input max',
  'output_max': 'Output max',
  'run when': 'Run when',
  'ramp_s': 'Ramp (s)',
  'ok': 'Ok',
  'code': 'Code',
  'message': 'Message',
  'limit': 'Limit',
  'state': 'State',
  'margin': 'Margin',
  'input_min': 'Input min',
  'output_min': 'Output min',
  'input_out_of_range': 'Input out of range',
};

String _label(String name) => _human[name] ?? name;

/// A row of a block, [name] as the engine has it and [label] as it reads
/// (else from [_human]): [ins] / [outs] are `''` (none), `free`, `bound`,
/// `write`.
FieldRowVm _r(
  String name,
  String value, {
  String ins = 'free',
  String outs = 'free',
  ValueTone tone = ValueTone.plain,
  bool target = false,
  String? label,
}) {
  PortMark mark(String s) => switch (s) {
    'free' => PortMark.free,
    'bound' => PortMark.bound,
    'write' => PortMark.write,
    _ => PortMark.none,
  };
  return FieldRowVm(
    id: name,
    label: label ?? _label(name),
    name: name,
    value: value,
    tone: tone,
    inPort: ins.isEmpty ? null : name,
    outPort: outs.isEmpty ? null : name,
    inMark: mark(ins),
    outMark: mark(outs),
    dropTarget: target,
  );
}

List<FlowBlockVm> _bindBlocks(String selected, {int cases = 2}) => [
  FlowBlockVm(
    id: 'plcL',
    title: 'plc1',
    type: 'tcp-boiler',
    kind: BlockKindVm.node,
    x: 30 + _m,
    y: 40 + _m,
    width: 200,
    selected: selected == 'plcL',
    rows: [
      _r('t1', '82.5 °C', ins: '', outs: 'bound'),
      _r('t2', '64.1 °C', ins: '', outs: 'bound'),
      _r('valve', '— bad', tone: ValueTone.bad),
      _r('pump', 'on'),
    ],
  ),
  FlowBlockVm(
    id: 'tank',
    title: 'tankInfo',
    type: 'v3',
    kind: BlockKindVm.my,
    x: 30 + _m,
    y: 270 + _m,
    width: 200,
    selected: selected == 'tank',
    rows: [
      _r('level', '92.6 %'),
      _r('limit', '90'),
      _r('state', 'high', ins: '', outs: 'bound'),
      _r('margin', '-2.6', ins: ''),
    ],
  ),
  FlowBlockVm(
    id: 'case',
    title: 'case',
    x: 320 + _m,
    y: 60 + _m,
    selected: selected == 'case',
    rows: [
      _r('op', '='),
      _r('input', 'high', ins: 'bound', tone: ValueTone.bound),
      for (var i = 0; i < cases; i++) ...[
        _r('case $i', const ['high', 'ok', 'bad', 'stale'][i]),
        _r('then $i', const ['100', '40', '0', '20'][i]),
      ],
      _r('else', '0'),
      _r('output', '100', ins: '', outs: 'bound'),
    ],
    variadic: VariadicVm(
      label: '$cases cases',
      canRemove: cases > 1,
      canAdd: cases < 4,
      removeLabel: 'Remove last case',
      addLabel: 'Add a case',
    ),
  ),
  FlowBlockVm(
    id: 'script',
    title: 'script',
    type: 'rhai',
    x: 320 + _m,
    y: (cases > 2 ? 560 : 500) + _m,
    selected: selected == 'script',
    rows: [
      _r('a', '64.1', ins: 'bound', tone: ValueTone.bound),
      _r('b', '82.5', ins: 'bound', tone: ValueTone.bound),
      _r('expr', 'b - a'),
      _r('result', '18.4', ins: '', outs: 'bound'),
    ],
  ),
  FlowBlockVm(
    id: 'plcR',
    title: 'plc1',
    type: 'writes',
    kind: BlockKindVm.node,
    x: 650 + _m,
    y: 80 + _m,
    width: 210,
    selected: selected == 'plcR',
    rows: [
      _r('fan', '100 %', ins: 'write', tone: ValueTone.bound),
      _r('pump', 'on'),
    ],
  ),
  FlowBlockVm(
    id: 'pub',
    title: 'publish',
    type: 'storage',
    kind: BlockKindVm.sink,
    x: 650 + _m,
    y: (cases > 2 ? 560 : 500) + _m,
    width: 210,
    selected: selected == 'pub',
    rows: [
      _r('key', 'boiler/delta', outs: ''),
      _r('value', '18.4', ins: 'bound', outs: '', tone: ValueTone.bound),
      _r('quality', 'good', ins: ''),
    ],
  ),
];

const _bindWires = [
  FlowWireVm('tank', 'state', 'case', 'input'),
  FlowWireVm('case', 'output', 'plcR', 'fan', writes: true),
  FlowWireVm('plcL', 't2', 'script', 'a'),
  FlowWireVm('plcL', 't1', 'script', 'b'),
  FlowWireVm('script', 'result', 'pub', 'value'),
];

FlowEditorPage _bind({
  required String? selected,
  String kind = '',
  String title = '',
  String note = '',
  List<InspectorRowVm> rows = const [],
  FlowSummaryVm? summary,
  int cases = 2,
  List<FlowBlockVm>? blocks,
  List<FlowWireVm>? wires,
  String flow = 'tank-level',
}) => FlowEditorPage(
  flowsLabel: 'Flows',
  flowLabel: flow,
  blockLabel: selected == null ? null : title,
  state: 'Draft saved',
  stateDot: true,
  validateLabel: 'Validate',
  deployLabel: 'Deploy',
  onDeploy: () {},
  onValidate: () {},
  onClose: () {},
  onFlows: () {},
  onLogo: () {},
  paletteTabs: _tabs(),
  paletteTab: 'blocks',
  onPaletteTab: _id,
  palette: _blocks(),
  paletteClosed: const {'Sources', 'Sinks', 'Code · WASM'},
  searchHint: 'Find a block',
  onPick: _id,
  blocks: blocks ?? _bindBlocks(selected ?? '', cases: cases),
  wires: wires ?? _bindWires,
  blockActions: _actions,
  onClear: () {},
  onMove: (_, _, _) {},
  onDrop: (_, _, _) {},
  legend: _legend,
  inspectorKind: kind,
  inspectorTitle: title,
  inspectorNote: note,
  inspectorRows: rows,
  summary: summary,
  inspectorFooter: _footer,
  onFieldChanged: _two,
  onFieldUnbind: _id,
  onFieldBind: (_, _) {},
  onProblem: _id,
  removeLabel: 'Remove block',
  onRemove: selected == null ? null : () {},
);

InspectorRowVm _text(String name, String value) => InspectorRowVm(
  id: name,
  name: _label(name),
  engine: _label(name) == name ? '' : name,
  editor: FieldEditorVm.text,
  value: value,
  inPort: name,
);

List<InspectorRowVm> _caseRows(int cases) => [
  const InspectorRowVm(
    id: 'op',
    name: 'Operation',
    engine: 'op',
    editor: FieldEditorVm.choice,
    value: '=',
    choices: ['=', '>', '<'],
    inPort: 'op',
  ),
  const InspectorRowVm(
    id: 'input',
    name: 'Input',
    engine: 'input',
    editor: FieldEditorVm.bound,
    value: 'high',
    sourceBlock: 'tank',
    inPort: 'input',
  ),
  for (var i = 0; i < cases; i++) ...[
    _text('case $i', const ['high', 'ok', 'bad', 'stale'][i]),
    _text('then $i', const ['100', '40', '0', '20'][i]),
  ],
  _text('else', '0'),
  const InspectorRowVm(
    id: 'output',
    name: 'Output',
    engine: 'output',
    editor: FieldEditorVm.output,
    value: '100',
    targets: '→ plc1.fan',
  ),
];

/// FlowBind with `case` selected (block selected).
FlowEditorPage flowBlockSelected() => _bind(
  selected: 'case',
  kind: 'Logic block',
  title: 'case',
  note: 'Compares input with each case; output takes the matching then.',
  rows: _caseRows(2),
);

/// FlowBind with nothing selected: the flow's summary.
FlowEditorPage flowNothingSelected() => _bind(
  selected: null,
  summary: const FlowSummaryVm(
    label: 'Flow',
    title: 'tank-level',
    facts: [
      ('Version', '4'),
      ('Deployed by', 'olena · 12 min ago'),
      ('May write', 'write'),
      (
        'Reads',
        'downstream/modbus/tcp-boiler/t1, downstream/modbus/tcp-boiler/t2',
      ),
      ('Writes', 'downstream/modbus/tcp-boiler/fan'),
    ],
    problemsLabel: 'Problems',
    problems: [
      ProblemVm('node script: expr: unknown variable c', block: 'script'),
    ],
  ),
);

/// FlowBind with the written point selected: the ember write wire and its
/// ember chip.
FlowEditorPage flowWriteWire() => _bind(
  selected: 'plcR',
  kind: 'Tree node',
  title: 'plc1',
  note: 'Writable points have an input; binding into it writes ~set.',
  rows: const [
    InspectorRowVm(
      id: 'fan',
      name: 'fan',
      editor: FieldEditorVm.bound,
      value: '100 %',
      sourceBlock: 'case',
      writes: true,
      inPort: 'fan',
    ),
    InspectorRowVm(
      id: 'pump',
      name: 'pump',
      editor: FieldEditorVm.text,
      value: 'on',
      inPort: 'pump',
    ),
  ],
);

/// FlowBind with `case` grown to three cases (a variable block).
FlowEditorPage flowVariadic() => _bind(
  selected: 'case',
  kind: 'Logic block',
  title: 'case',
  note: 'Compares input with each case; output takes the matching then.',
  rows: _caseRows(3),
  cases: 3,
);

/// FlowTree: `stop_pump` selected, `level_sp` being dragged onto `tank`.
FlowEditorPage flowTreeDrag() => FlowEditorPage(
  flowsLabel: 'Flows',
  flowLabel: 'tank-level',
  blockLabel: 'stop_pump',
  state: 'Draft saved',
  stateDot: true,
  validateLabel: 'Validate',
  deployLabel: 'Deploy',
  onDeploy: () {},
  onValidate: () {},
  onClose: () {},
  onFlows: () {},
  onLogo: () {},
  paletteTabs: _tabs(),
  paletteTab: 'tree',
  onPaletteTab: _id,
  palette: const [
    PaletteEntryVm(
      id: 'k1',
      title: 'level_raw',
      tag: '.0',
      group: 'modbus / tcp-tank',
      point: true,
      value: '3790',
      used: true,
    ),
    PaletteEntryVm(
      id: 'k2',
      title: 'level_sp',
      tag: '.0',
      group: 'modbus / tcp-tank',
      point: true,
      value: '90 %',
      dragging: true,
    ),
    PaletteEntryVm(
      id: 'k3',
      title: 'pump_run',
      tag: '01',
      group: 'modbus / tcp-tank',
      point: true,
      value: 'off',
      used: true,
    ),
    PaletteEntryVm(
      id: 'k4',
      title: 'mode',
      tag: '≡',
      group: 'modbus / tcp-tank',
      point: true,
      value: 'auto',
      used: true,
    ),
    PaletteEntryVm(
      id: 'k5',
      title: 'pump_fault',
      tag: '01',
      group: 'modbus / tcp-tank',
      point: true,
      value: 'off',
    ),
    PaletteEntryVm(
      id: 'a1',
      title: 'start_pump',
      tag: 'ACT',
      group: 'modbus / tcp-tank',
      point: true,
      action: true,
      value: '2 in',
    ),
    PaletteEntryVm(
      id: 'a2',
      title: 'stop_pump',
      tag: 'ACT',
      group: 'modbus / tcp-tank',
      point: true,
      action: true,
      value: '1 in',
      used: true,
    ),
    PaletteEntryVm(
      id: 'a3',
      title: 'reset_alarm',
      tag: 'ACT',
      group: 'modbus / tcp-tank',
      point: true,
      action: true,
      value: '0 in',
    ),
    PaletteEntryVm(
      id: 'k6',
      title: 'level',
      tag: '.0',
      group: 'storage / tank',
      point: true,
      value: '92.6',
    ),
    PaletteEntryVm(
      id: 'k7',
      title: 'state',
      tag: 'Aa',
      group: 'storage / tank',
      point: true,
      value: '"high"',
    ),
  ],
  paletteNotes: const [
    PaletteNoteVm(
      'Point',
      'on a block: adds it as a field. On the canvas: a new block of that node.',
    ),
    PaletteNoteVm(
      'Action',
      'a block that runs it when run when turns true; its arguments are fields.',
      ember: true,
    ),
  ],
  searchHint: 'Find a point or action',
  onPick: _id,
  blocks: [
    FlowBlockVm(
      id: 'tank',
      title: 'tank',
      type: 'modbus/tcp-tank',
      kind: BlockKindVm.node,
      x: 30 + _m,
      y: 120 + _m,
      width: 200,
      rows: [
        _r('level_raw', '3790', ins: '', outs: 'bound'),
        _r('pump_run', 'off'),
        _r('mode', 'auto', target: true),
      ],
    ),
    FlowBlockVm(
      id: 'scale',
      title: 'scale',
      type: 'scale',
      x: 320 + _m,
      y: 40 + _m,
      rows: [
        _r('in', '3790', ins: 'bound', tone: ValueTone.bound),
        _r('input_max', '4095'),
        _r('output_max', '100'),
        _r('out', '92.6', ins: '', outs: 'bound'),
      ],
    ),
    FlowBlockVm(
      id: 'if',
      title: 'if',
      type: 'op >',
      x: 320 + _m,
      y: 300 + _m,
      rows: [
        _r('a', '92.6', ins: 'bound', tone: ValueTone.bound),
        _r('b', '90'),
        _r('out', 'true', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(label: '2 inputs', canRemove: false),
    ),
    FlowBlockVm(
      id: 'pub',
      title: 'publish',
      type: 'storage',
      kind: BlockKindVm.sink,
      x: 640 + _m,
      y: 40 + _m,
      width: 210,
      rows: [
        _r('key', 'tank/level', outs: ''),
        _r('value', '92.6', ins: 'bound', outs: '', tone: ValueTone.bound),
      ],
    ),
    FlowBlockVm(
      id: 'act',
      title: 'stop_pump',
      type: 'modbus/tcp-tank',
      kind: BlockKindVm.action,
      x: 640 + _m,
      y: 280 + _m,
      width: 210,
      selected: true,
      rows: [
        _r('run when', 'true', ins: 'write', tone: ValueTone.bound),
        _r('ramp_s', '5'),
        _r('ok', 'true', ins: ''),
        _r('code', '—', ins: ''),
        _r('message', 'stopped', ins: ''),
      ],
    ),
  ],
  wires: const [
    FlowWireVm('tank', 'level_raw', 'scale', 'in'),
    FlowWireVm('scale', 'out', 'pub', 'value'),
    FlowWireVm('scale', 'out', 'if', 'a'),
    FlowWireVm('if', 'out', 'act', 'run when', writes: true),
  ],
  blockActions: _actions,
  onClear: () {},
  onMove: (_, _, _) {},
  onDrop: (_, _, _) {},
  legend: _legend,
  inspectorKind: 'Action',
  inspectorTitle: 'stop_pump',
  inspectorNote:
      'Dragged from the tree. Runs when run when turns true; ok, code and message come back.',
  inspectorRows: const [
    InspectorRowVm(
      id: 'run when',
      name: 'Run when',
      engine: 'run when',
      editor: FieldEditorVm.bound,
      value: 'true',
      sourceBlock: 'if',
      writes: true,
      inPort: 'run when',
    ),
    InspectorRowVm(
      id: 'ramp_s',
      name: 'Ramp (s)',
      engine: 'ramp_s',
      editor: FieldEditorVm.text,
      value: '5',
      inPort: 'ramp_s',
    ),
    InspectorRowVm(
      id: 'ok',
      name: 'Ok',
      engine: 'ok',
      editor: FieldEditorVm.output,
      value: 'true',
      targets: 'not bound',
    ),
    InspectorRowVm(
      id: 'code',
      name: 'Code',
      engine: 'code',
      editor: FieldEditorVm.output,
      value: '—',
      targets: 'not bound',
    ),
    InspectorRowVm(
      id: 'message',
      name: 'Message',
      engine: 'message',
      editor: FieldEditorVm.output,
      value: 'stopped',
      targets: 'not bound',
    ),
  ],
  inspectorFooter: _footer,
  onFieldChanged: _two,
  onFieldUnbind: _id,
  onFieldBind: (_, _) {},
  onProblem: _id,
  removeLabel: 'Remove block',
  onRemove: () {},
);

/// A `scale` in each form (ADR 0032 §7), as the editor builds it from the
/// catalog: the linear form reads Input · Factor · Offset · Output (both
/// ports on Factor and Offset: `in.k`, `in.b` since spec 06 0.2.17); the range
/// form reads the four range fields, each with both ports, and
/// `Input out of range`.
FlowEditorPage flowScale({required bool range}) {
  final rows = range
      ? [
          _r('in', '3790', ins: 'bound', tone: ValueTone.bound),
          _r('input_min', '0'),
          _r('input_max', '4095'),
          _r('output_min', '0'),
          _r('output_max', '100'),
          _r('out', '92.6', ins: '', outs: 'bound'),
          _r('input_out_of_range', 'false', ins: ''),
        ]
      : [
          _r('in', '3790', ins: 'bound', tone: ValueTone.bound),
          _r('k', '0.0244', label: 'Factor'),
          _r('b', '0', label: 'Offset'),
          _r('out', '92.6', ins: '', outs: 'bound'),
        ];
  return _bind(
    flow: 'tank',
    selected: 'pct',
    kind: 'Logic block',
    title: 'pct',
    note:
        'out = k × in + b; with a range, in is first mapped from '
        'input_min…input_max to output_min…output_max.',
    blocks: [
      FlowBlockVm(
        id: 'raw',
        title: 'raw',
        type: 'plc/tank',
        kind: BlockKindVm.node,
        x: 40 + _m,
        y: 80 + _m,
        width: 200,
        rows: [_r('level_raw', '3790', ins: '', outs: 'bound')],
      ),
      FlowBlockVm(
        id: 'pct',
        title: 'pct',
        type: 'scale',
        x: 320 + _m,
        y: 60 + _m,
        selected: true,
        rows: rows,
      ),
      FlowBlockVm(
        id: 'show',
        title: 'show',
        type: 'publish',
        kind: BlockKindVm.sink,
        x: 640 + _m,
        y: 100 + _m,
        width: 210,
        rows: [
          _r('key', 'level', ins: '', outs: ''),
          _r('value', '92.6', ins: 'bound', outs: '', tone: ValueTone.bound),
        ],
      ),
    ],
    wires: const [
      FlowWireVm('raw', 'level_raw', 'pct', 'in'),
      FlowWireVm('pct', 'out', 'show', 'value'),
    ],
    rows: [
      InspectorRowVm(
        id: 'form',
        name: 'Form',
        editor: FieldEditorVm.choice,
        value: range ? 'Range' : 'k × in + b',
        choices: const [
          'k × in + b',
          'Range',
        ],
      ),
      const InspectorRowVm(
        id: 'in',
        name: 'Input',
        engine: 'in',
        editor: FieldEditorVm.bound,
        value: '3790',
        sourceBlock: 'raw',
        inPort: 'in',
      ),
      if (range) ...[
        _text('input_min', '0'),
        _text('input_max', '4095'),
        _text('output_min', '0'),
        _text('output_max', '100'),
      ] else ...[
        const InspectorRowVm(
          id: 'k',
          name: 'Factor',
          engine: 'k',
          editor: FieldEditorVm.text,
          value: '0.0244',
          inPort: 'k',
        ),
        const InspectorRowVm(
          id: 'b',
          name: 'Offset',
          engine: 'b',
          editor: FieldEditorVm.text,
          value: '0',
          inPort: 'b',
        ),
      ],
      const InspectorRowVm(
        id: 'out',
        name: 'Output',
        engine: 'out',
        editor: FieldEditorVm.output,
        value: '92.6',
        targets: '→ show.Value',
      ),
      if (range)
        const InspectorRowVm(
          id: 'input_out_of_range',
          name: 'Input out of range',
          engine: 'input_out_of_range',
          editor: FieldEditorVm.output,
          value: 'false',
          targets: 'not bound',
        ),
    ],
  );
}

/// The blocks of a small text flow (owner's review 2026-11-08): variables
/// are one field `Value` each; `concat` reads Input 1, Input 2, Strict,
/// Output; a bound field shows the value that comes in.
List<FlowBlockVm> _textBlocks(String selected, {bool preview = false}) => [
  FlowBlockVm(
    id: 'greeting',
    title: 'greeting',
    type: 'string',
    x: 40 + _m,
    y: 60 + _m,
    selected: selected == 'greeting',
    rows: [
      _r('value', 'Hello, ', outs: 'bound'),
    ],
  ),
  FlowBlockVm(
    id: 'who',
    title: 'who',
    type: 'string',
    x: 40 + _m,
    y: 180 + _m,
    selected: selected == 'who',
    rows: [_r('value', 'tank 3', outs: 'bound')],
  ),
  FlowBlockVm(
    id: 'limit',
    title: 'limit',
    type: 'number',
    x: 40 + _m,
    y: 320 + _m,
    selected: selected == 'limit',
    rows: [_r('value', preview ? '70' : '25', outs: 'bound')],
  ),
  FlowBlockVm(
    id: 'armed',
    title: 'armed',
    type: 'bool',
    x: 40 + _m,
    y: 440 + _m,
    selected: selected == 'armed',
    rows: [_r('value', 'true')],
  ),
  FlowBlockVm(
    id: 'text',
    title: 'text',
    type: 'concat',
    x: 340 + _m,
    y: 80 + _m,
    selected: selected == 'text',
    rows: [
      _r(
        'in.0',
        'Hello, ',
        ins: 'bound',
        tone: ValueTone.bound,
        label: 'Input 1',
      ),
      _r(
        'in.1',
        'tank 3',
        ins: 'bound',
        tone: ValueTone.bound,
        label: 'Input 2',
      ),
      _r('strict', 'false', label: 'Strict'),
      _r('out', 'Hello, tank 3', ins: '', outs: 'bound'),
    ],
    variadic: const VariadicVm(label: '2 inputs', canRemove: false),
  ),
  FlowBlockVm(
    id: 'cmd',
    title: 'cmd',
    type: 'scale',
    x: 340 + _m,
    y: 340 + _m,
    selected: selected == 'cmd',
    rows: [
      _r('in', preview ? '70' : '25', ins: 'bound', tone: ValueTone.bound),
      _r('k', '1.01', label: 'Factor'),
      _r('b', '0', label: 'Offset'),
      _r('out', preview ? '70.7' : '25.25', ins: '', outs: 'bound'),
    ],
  ),
  FlowBlockVm(
    id: 'show',
    title: 'show',
    type: 'publish',
    kind: BlockKindVm.sink,
    x: 660 + _m,
    y: 100 + _m,
    width: 210,
    tag: preview ? 'preview' : null,
    rows: [
      _r('node', 'banner', ins: '', outs: '', label: 'Value name'),
      _r(
        'in',
        preview ? 'would write Hello, tank 3' : 'Hello, tank 3',
        outs: '',
        ins: 'bound',
        tone: preview ? ValueTone.ghost : ValueTone.bound,
        label: 'Value',
      ),
    ],
  ),
  FlowBlockVm(
    id: 'knob',
    title: 'knob',
    type: 'mockdev/bench/rig1',
    kind: BlockKindVm.node,
    x: 660 + _m,
    y: 360 + _m,
    width: 210,
    tag: preview ? 'preview' : null,
    rows: [
      _r(
        'in',
        preview ? 'would write 70.7' : '25.3',
        ins: 'write',
        outs: '',
        tone: preview ? ValueTone.ghost : ValueTone.bound,
        label: 'knob',
      ),
    ],
  ),
];

const _textWires = [
  FlowWireVm('greeting', 'value', 'text', 'in.0'),
  FlowWireVm('who', 'value', 'text', 'in.1'),
  FlowWireVm('text', 'out', 'show', 'in'),
  FlowWireVm('limit', 'value', 'cmd', 'in'),
  FlowWireVm(
    'cmd',
    'out',
    'knob',
    'in',
    writes: true,
  ),
];

/// A variable block selected: one field `Value` (a number box), its input
/// and its output one entity.
FlowEditorPage flowVariable() => _bind(
  flow: 'banner',
  selected: 'limit',
  kind: 'Logic block',
  title: 'limit',
  note: 'A number: sent at start, and again when in brings another.',
  blocks: _textBlocks('limit'),
  wires: _textWires,
  rows: const [
    InspectorRowVm(
      id: 'value',
      name: 'Value',
      engine: 'value',
      editor: FieldEditorVm.text,
      value: '25',
      inPort: 'in',
      hint: 'The value at start (default 0).',
    ),
  ],
);

/// `concat` selected: its inputs show the values that come in (no path),
/// the inspector the same, read only, with the bound mark.
FlowEditorPage flowBoundValue() => _bind(
  flow: 'banner',
  selected: 'text',
  kind: 'Logic block',
  title: 'text',
  note: 'The inputs as one text.',
  blocks: _textBlocks('text'),
  wires: _textWires,
  rows: const [
    InspectorRowVm(
      id: 'in.0',
      name: 'Input 1',
      engine: 'in.0',
      editor: FieldEditorVm.bound,
      value: 'Hello, ',
      sourceBlock: 'greeting',
      inPort: 'in.0',
    ),
    InspectorRowVm(
      id: 'in.1',
      name: 'Input 2',
      engine: 'in.1',
      editor: FieldEditorVm.bound,
      value: 'tank 3',
      sourceBlock: 'who',
      inPort: 'in.1',
    ),
    InspectorRowVm(
      id: 'strict',
      name: 'Strict',
      engine: 'strict',
      editor: FieldEditorVm.toggle,
      value: 'false',
      inPort: 'strict',
    ),
    InspectorRowVm(
      id: 'out',
      name: 'Output',
      engine: 'out',
      editor: FieldEditorVm.output,
      value: 'Hello, tank 3',
      targets: '→ show.Value',
    ),
  ],
);

/// The draft differs from the deployed version (`limit` 25 → 70): its
/// values come from the preview, the sinks show what they would write.
FlowEditorPage flowPreviewSink() => _bind(
  flow: 'banner',
  selected: null,
  blocks: _textBlocks('', preview: true),
  wires: _textWires,
  summary: const FlowSummaryVm(
    label: 'Flow',
    title: 'banner',
    facts: [
      ('Version', '3'),
      ('Deployed by', 'user:admin · 2 h ago'),
      ('May write', 'write'),
      ('Values', 'a preview of the draft; nothing is written'),
      ('Writes', 'downstream/mockdev/bench/rig1/knob'),
    ],
  ),
);

/// A `case` block as the editor builds it from the 0.2.21 catalog (ADR 0038
/// §8): Input · Operation · Case 1 · Then 1 · Case 2 · Then 2 · Else ·
/// Output, the pairs typed as constants (`values`), − / + by a pair.
FlowEditorPage flowCase() => _bind(
  flow: 'tiers',
  selected: 'tier',
  kind: 'Logic block',
  title: 'tier',
  note:
      'The then of the first pair whose case in matches by op; else when '
      'none does.',
  blocks: [
    FlowBlockVm(
      id: 'level',
      title: 'level',
      type: 'plc/tank',
      kind: BlockKindVm.node,
      x: 40 + _m,
      y: 80 + _m,
      width: 200,
      rows: [_r('level', '92.6 %', ins: '', outs: 'bound')],
    ),
    FlowBlockVm(
      id: 'tier',
      title: 'tier',
      type: 'case',
      x: 320 + _m,
      y: 60 + _m,
      selected: true,
      rows: [
        _r('in', '92.6', ins: 'bound', tone: ValueTone.bound),
        _r('op', '>=', label: 'Operation'),
        _r('in.0', '90', label: 'Case 1'),
        _r('in.1', 'high', label: 'Then 1'),
        _r('in.2', '10', label: 'Case 2'),
        _r('in.3', 'normal', label: 'Then 2'),
        _r('else', 'low', label: 'Else'),
        _r('out', 'high', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(
        label: '2 cases',
        addLabel: 'Add a case',
        removeLabel: 'Remove the last case',
      ),
    ),
    FlowBlockVm(
      id: 'show',
      title: 'show',
      type: 'publish',
      kind: BlockKindVm.sink,
      x: 640 + _m,
      y: 100 + _m,
      width: 210,
      rows: [
        _r('node', 'tier', ins: '', outs: '', label: 'Value name'),
        _r(
          'in',
          'high',
          ins: 'bound',
          outs: '',
          tone: ValueTone.bound,
          label: 'Value',
        ),
      ],
    ),
  ],
  wires: const [
    FlowWireVm('level', 'level', 'tier', 'in'),
    FlowWireVm('tier', 'out', 'show', 'in'),
  ],
  rows: const [
    InspectorRowVm(
      id: 'in',
      name: 'Input',
      engine: 'in',
      editor: FieldEditorVm.bound,
      value: '92.6',
      sourceBlock: 'level',
      inPort: 'in',
    ),
    InspectorRowVm(
      id: 'op',
      name: 'Operation',
      engine: 'op',
      editor: FieldEditorVm.choice,
      value: '>=',
      choices: [
        '=',
        '!=',
        '>',
        '<',
        '>=',
        '<=',
        'contains',
        'starts_with',
        'ends_with',
      ],
      inPort: 'op',
    ),
    InspectorRowVm(
      id: 'in.0',
      name: 'Case 1',
      engine: 'in.0',
      editor: FieldEditorVm.text,
      value: '90',
      inPort: 'in.0',
    ),
    InspectorRowVm(
      id: 'in.1',
      name: 'Then 1',
      engine: 'in.1',
      editor: FieldEditorVm.text,
      value: 'high',
      inPort: 'in.1',
    ),
    InspectorRowVm(
      id: 'in.2',
      name: 'Case 2',
      engine: 'in.2',
      editor: FieldEditorVm.text,
      value: '10',
      inPort: 'in.2',
    ),
    InspectorRowVm(
      id: 'in.3',
      name: 'Then 2',
      engine: 'in.3',
      editor: FieldEditorVm.text,
      value: 'normal',
      inPort: 'in.3',
    ),
    InspectorRowVm(
      id: 'else',
      name: 'Else',
      engine: 'else',
      editor: FieldEditorVm.text,
      value: 'low',
      inPort: 'else',
      hint: 'Sent when no case matches (default null).',
    ),
    InspectorRowVm(
      id: 'out',
      name: 'Output',
      engine: 'out',
      editor: FieldEditorVm.output,
      value: 'high',
      targets: '→ show.Value',
    ),
  ],
);

/// Operands hold a typed value (ADR 0038 §7): `concat` Input 1 typed
/// `AHU-` (plain, an editable text in the inspector), Input 2 bound to a
/// number (the value that comes in, in accent; read only, bound).
FlowEditorPage flowOperand() => _bind(
  flow: 'tags',
  selected: 'tag',
  kind: 'Logic block',
  title: 'tag',
  note: 'The inputs as one text.',
  blocks: [
    FlowBlockVm(
      id: 'unit',
      title: 'unit',
      type: 'number',
      x: 40 + _m,
      y: 120 + _m,
      rows: [_r('value', '2', outs: 'bound')],
    ),
    FlowBlockVm(
      id: 'tag',
      title: 'tag',
      type: 'concat',
      x: 320 + _m,
      y: 80 + _m,
      selected: true,
      rows: [
        _r('in.0', 'AHU-', label: 'Input 1'),
        _r(
          'in.1',
          '2',
          ins: 'bound',
          tone: ValueTone.bound,
          label: 'Input 2',
        ),
        _r('strict', 'false', label: 'Strict'),
        _r('out', 'AHU-2', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(label: '2 inputs', canRemove: false),
    ),
    FlowBlockVm(
      id: 'show',
      title: 'show',
      type: 'publish',
      kind: BlockKindVm.sink,
      x: 640 + _m,
      y: 100 + _m,
      width: 210,
      rows: [
        _r('node', 'tag', ins: '', outs: '', label: 'Value name'),
        _r(
          'in',
          'AHU-2',
          ins: 'bound',
          outs: '',
          tone: ValueTone.bound,
          label: 'Value',
        ),
      ],
    ),
  ],
  wires: const [
    FlowWireVm('unit', 'value', 'tag', 'in.1'),
    FlowWireVm('tag', 'out', 'show', 'in'),
  ],
  rows: const [
    InspectorRowVm(
      id: 'in.0',
      name: 'Input 1',
      engine: 'in.0',
      editor: FieldEditorVm.text,
      value: 'AHU-',
      inPort: 'in.0',
    ),
    InspectorRowVm(
      id: 'in.1',
      name: 'Input 2',
      engine: 'in.1',
      editor: FieldEditorVm.bound,
      value: '2',
      sourceBlock: 'unit',
      inPort: 'in.1',
    ),
    InspectorRowVm(
      id: 'strict',
      name: 'Strict',
      engine: 'strict',
      editor: FieldEditorVm.toggle,
      value: 'false',
      inPort: 'strict',
    ),
    InspectorRowVm(
      id: 'out',
      name: 'Output',
      engine: 'out',
      editor: FieldEditorVm.output,
      value: 'AHU-2',
      targets: '→ show.Value',
    ),
  ],
);
