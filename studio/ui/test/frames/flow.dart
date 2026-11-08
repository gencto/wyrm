// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/widgets.dart';
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
  onMove: _move,
  onMoveEnd: _id,
  onBind: _bindField,
  onUnbind: _two,
  onDropEntry: _three,
  onResize: _resize,
);

void _id(String _) {}
void _move(String _, Offset _) {}
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
  'A bound field shows its source here and in the block; click the link icon to unbind.',
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

/// A row of a block: [ins] / [outs] are `''` (none), `free`, `bound`,
/// `write`.
FieldRowVm _r(
  String label,
  String value, {
  String ins = 'free',
  String outs = 'free',
  ValueTone tone = ValueTone.plain,
  bool target = false,
}) {
  PortMark mark(String s) => switch (s) {
    'free' => PortMark.free,
    'bound' => PortMark.bound,
    'write' => PortMark.write,
    _ => PortMark.none,
  };
  return FieldRowVm(
    id: label,
    label: label,
    value: value,
    tone: tone,
    inPort: ins.isEmpty ? null : label,
    outPort: outs.isEmpty ? null : label,
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
}) => FlowEditorPage(
  flowsLabel: 'Flows',
  flowLabel: 'tank-level',
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
  blocks: _bindBlocks(selected ?? '', cases: cases),
  wires: _bindWires,
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
  name: name,
  editor: FieldEditorVm.text,
  value: value,
  inPort: name,
);

List<InspectorRowVm> _caseRows(int cases) => [
  const InspectorRowVm(
    id: 'op',
    name: 'op',
    editor: FieldEditorVm.choice,
    value: '=',
    choices: ['=', '>', '<'],
    inPort: 'op',
  ),
  const InspectorRowVm(
    id: 'input',
    name: 'input',
    editor: FieldEditorVm.bound,
    source: 'tankInfo.state',
    inPort: 'input',
  ),
  for (var i = 0; i < cases; i++) ...[
    _text('case $i', const ['high', 'ok', 'bad', 'stale'][i]),
    _text('then $i', const ['100', '40', '0', '20'][i]),
  ],
  _text('else', '0'),
  const InspectorRowVm(
    id: 'output',
    name: 'output',
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
      source: 'case.output',
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
      name: 'run when',
      editor: FieldEditorVm.bound,
      source: 'if.out',
      writes: true,
      inPort: 'run when',
    ),
    InspectorRowVm(
      id: 'ramp_s',
      name: 'ramp_s',
      editor: FieldEditorVm.text,
      value: '5',
      inPort: 'ramp_s',
    ),
    InspectorRowVm(
      id: 'ok',
      name: 'ok',
      editor: FieldEditorVm.output,
      value: 'true',
      targets: 'not bound',
    ),
    InspectorRowVm(
      id: 'code',
      name: 'code',
      editor: FieldEditorVm.output,
      value: '—',
      targets: 'not bound',
    ),
    InspectorRowVm(
      id: 'message',
      name: 'message',
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
