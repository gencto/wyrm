// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/widgets.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_legend.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/flows/shortcut_card.dart';
import 'package:ui/indicators/quality_mark.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/trees/json_tree.dart';
import 'package:ui/trees/tree_row.dart';

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
  ValueViewerVm? viewer,
  Set<String> hidden = const {},
  bool pins = false,
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
  onMove: (_, {required nudge}) {},
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
  onView: _id,
  viewer: viewer,
  onCloseViewer: () {},
  onSelectMany: (_, {required add, required toggle}) {},
  onCommand: (_, {at}) {},
  onPin: (_, _, {required pinned}) {},
  onViewField: (_, _) {},
  onFieldPin: pins ? (_, {required pinned}) {} : null,
  onSaveViewer: _id,
  validateViewer: (text) =>
      text.contains('oops') ? 'Not a JSON map or list' : null,
  saveHint: 'Cmd+Enter saves · Esc cancels',
  menu: (ids, block, row) => _menu(
    ids,
    block,
    row,
    blocks ?? _bindBlocks(selected ?? '', cases: cases),
    hidden,
  ),
);

/// The context menu as the app builds it: of one block (with its fields),
/// of several, or of the canvas.
FlowMenuVm _menu(
  Set<String> ids,
  String? block,
  String? row,
  List<FlowBlockVm> blocks,
  Set<String> hidden,
) {
  final b = blocks.where((b) => b.id == block).firstOrNull;
  final one = ids.length == 1 && b != null;
  final none = ids.isEmpty ? 'Select a block first' : null;
  FlowPinVm pin(String id, String label, {bool bound = false}) => FlowPinVm(
    id: id,
    label: label,
    pinned: !hidden.contains(id),
    lockedReason: bound ? 'bound' : null,
  );
  final fields = [
    if (one)
      for (final r in b.rows)
        pin(
          r.id,
          r.label,
          bound:
              r.inMark == PortMark.bound ||
              r.inMark == PortMark.write ||
              r.outMark == PortMark.bound,
        ),
    if (one)
      for (final id in hidden) pin(id, _label(id)),
  ];
  return FlowMenuVm(
    title: one
        ? b.title
        : (ids.length > 1 ? '${ids.length} blocks' : 'tank-level'),
    subtitle: one
        ? (b.type.isEmpty ? 'case' : b.type)
        : (ids.length > 1 ? '' : '${blocks.length} blocks'),
    fields: fields,
    unpin: row == null ? null : fields.where((f) => f.id == row).firstOrNull,
    items: [
      FlowMenuItemVm(.cut, disabledReason: none),
      FlowMenuItemVm(.copy, disabledReason: none),
      const FlowMenuItemVm(.paste),
      FlowMenuItemVm(.duplicate, disabledReason: none),
      FlowMenuItemVm(.delete, disabledReason: none, danger: ids.isNotEmpty),
      const FlowMenuItemVm(.selectAll, divider: true),
      if (ids.isEmpty) ...const [
        FlowMenuItemVm(.undo, divider: true),
        FlowMenuItemVm(.redo, disabledReason: 'Nothing to redo'),
      ],
      if (one) ...[
        const FlowMenuItemVm(.fields, divider: true),
        if (row != null) const FlowMenuItemVm(.unpin),
      ],
      if (ids.isNotEmpty)
        const FlowMenuItemVm(
          .createCustomBlock,
          divider: true,
          disabledReason: 'Needs custom blocks in the engine',
        ),
      if (one)
        const FlowMenuItemVm(
          .editCustomBlock,
          disabledReason: 'Needs custom blocks in the engine',
        ),
    ],
  );
}

/// FlowBind with `case` selected and two of its fields taken off the
/// block (`Operation`, `Else`): they stay in the inspector, their pins
/// grey; bound fields keep theirs (spec §12).
FlowEditorPage flowPins() {
  const hidden = {'op', 'else'};
  return _bind(
    selected: 'case',
    kind: 'Logic block',
    title: 'case',
    note: 'Compares input with each case; output takes the matching then.',
    hidden: hidden,
    pins: true,
    blocks: [
      for (final b in _bindBlocks('case'))
        if (b.id == 'case')
          FlowBlockVm(
            id: b.id,
            title: b.title,
            x: b.x,
            y: b.y,
            type: b.type,
            kind: b.kind,
            width: b.width,
            selected: true,
            variadic: b.variadic,
            rows: [
              for (final r in b.rows)
                if (!hidden.contains(r.id)) r,
            ],
          )
        else
          b,
    ],
    rows: [
      for (final r in _caseRows(2))
        r.pin(
          pinned: !hidden.contains(r.id),
          locked: r.id == 'input' || r.id == 'output',
        ),
    ],
  );
}

/// FlowBind with three blocks selected (a marquee's result): the flow's
/// summary in the inspector, `3 blocks` in the path.
FlowEditorPage flowSelection() {
  const picked = {'case', 'script', 'plcR'};
  return _bind(
    selected: null,
    title: '3 blocks',
    blocks: [
      for (final b in _bindBlocks(''))
        b.marked(selected: picked.contains(b.id)),
    ],
    summary: const FlowSummaryVm(
      label: 'Flow',
      title: 'tank-level',
      facts: [('Version', '4'), ('Values', 'the deployed version')],
    ),
  );
}

/// The viewer of a typed map (`show.meta`), with its Edit button: the
/// test opens the editor.
FlowEditorPage flowViewerEdit({bool locked = false}) => flowLongOutput(
  viewer: ValueViewerVm(
    title: locked ? 'text.in.1' : 'show.meta',
    type: locked ? 'string' : 'map',
    size: locked ? '5 chars' : '3 keys',
    copy: '',
    content: locked
        ? const TextContentVm(['world'])
        : const JsonContentVm(
            JsonNodeVm(
              kind: .object,
              text: '3 keys',
              children: [
                JsonNodeVm(key: 'unit', kind: .string, text: '"%"'),
                JsonNodeVm(key: 'display', kind: .string, text: '"Tank 3"'),
                JsonNodeVm(key: 'max', kind: .number, text: '100'),
              ],
            ),
          ),
    edit: locked
        ? null
        : const ViewerEditVm(
            kind: .json,
            text: '{\n  "unit": "%",\n  "display": "Tank 3",\n  "max": 100\n}',
          ),
    locked: locked
        ? 'Read only: a wire feeds this field. Unbind it to type a value.'
        : null,
  ),
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
  onMove: (_, {required nudge}) {},
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

/// The text a long `concat` sends: longer than its inspector cell.
const _long =
    'Hello, tank 3 — level 72.4 % at 12:00:03, inlet valve open, pump 2 '
    'running at 1450 rpm, alarm limits 20 % and 90 %, operator olena';

/// `concat` selected with a long Output (owner's review 2026-11-09: the
/// row overflowed by 7.7 px): every value cell ends in an ellipsis, and
/// each row ends in the eye that opens the viewer.
FlowEditorPage flowLongOutput({ValueViewerVm? viewer}) => _bind(
  flow: 'banner',
  selected: 'text',
  kind: 'Logic block',
  title: 'text',
  note: 'The inputs as one text.',
  blocks: _textBlocks('text'),
  wires: _textWires,
  viewer: viewer,
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
      value: _long,
      sourceBlock: 'who',
      inPort: 'in.1',
    ),
    InspectorRowVm(
      id: 'sep',
      name: 'Separator',
      engine: 'sep',
      editor: FieldEditorVm.choice,
      value: 'a long separator name that does not fit',
      choices: ['', ' ', 'a long separator name that does not fit'],
    ),
    InspectorRowVm(
      id: 'out',
      name: 'Output',
      engine: 'out',
      editor: FieldEditorVm.output,
      value: _long,
      targets: '→ show.Value',
    ),
  ],
);

const _wraps =
    'a third line after an empty one, long enough to wrap twice in the '
    'window at its first width of 440 points, which is what this golden '
    'shows';

/// The viewer of `text.out` open over the editor: a long text in mono,
/// wrapped, with line numbers.
FlowEditorPage flowViewerText() => flowLongOutput(
  viewer: const ValueViewerVm(
    title: 'text.out',
    type: 'string',
    size: '412 chars · 4 lines',
    copy: '',
    quality: QualityMarkVm(label: 'good', tone: .good),
    content: TextContentVm([
      _long,
      'next check in 5 s; last write by flow banner v3',
      '',
      _wraps,
    ]),
  ),
);

/// The viewer of a map (a `publish` input of a JSON object): a tree in
/// the syntax colours, one map closed.
FlowEditorPage flowViewerJson() => flowLongOutput(
  viewer: const ValueViewerVm(
    title: 'show.in',
    type: 'map',
    size: '6 keys',
    copy: '',
    quality: QualityMarkVm(label: 'good · 12:00:03', tone: .good),
    content: JsonContentVm(
      JsonNodeVm(
        kind: .object,
        text: '6 keys',
        children: [
          JsonNodeVm(key: 'tank', kind: .string, text: '"tank 3"'),
          JsonNodeVm(key: 'level', kind: .number, text: '72.4'),
          JsonNodeVm(key: 'armed', kind: .flag, text: 'true'),
          JsonNodeVm(key: 'operator', kind: .nil, text: 'null'),
          JsonNodeVm(
            key: 'limits',
            kind: .object,
            text: '2 keys',
            children: [
              JsonNodeVm(key: 'low', kind: .number, text: '20'),
              JsonNodeVm(key: 'high', kind: .number, text: '90'),
            ],
          ),
          JsonNodeVm(
            key: 'pumps',
            kind: .array,
            text: '2 items',
            children: [
              JsonNodeVm(
                kind: .object,
                text: '2 keys',
                children: [
                  JsonNodeVm(key: 'id', kind: .number, text: '1'),
                  JsonNodeVm(key: 'on', kind: .flag, text: 'false'),
                ],
              ),
              JsonNodeVm(
                kind: .object,
                text: '2 keys',
                children: [
                  JsonNodeVm(key: 'id', kind: .number, text: '2'),
                  JsonNodeVm(key: 'rpm', kind: .number, text: '1450'),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);

// ---------- wave 2 (flow-editor.md §17–§20, ADR 0040) ----------

List<TabItemVm> _tabs2() => const [
  TabItemVm(id: 'blocks', label: 'Blocks'),
  TabItemVm(id: 'my', label: 'My blocks'),
  TabItemVm(id: 'tree', label: 'Tree'),
];

FlowMenuVm _menu2(Set<String> ids, String? block, String? row) => FlowMenuVm(
  title: ids.length > 1 ? '${ids.length} blocks' : (block ?? 'line'),
  subtitle: ids.length > 1 ? '' : 'block:mean2',
  items: [
    const FlowMenuItemVm(FlowCommand.cut),
    const FlowMenuItemVm(FlowCommand.copy),
    const FlowMenuItemVm(FlowCommand.paste),
    const FlowMenuItemVm(FlowCommand.duplicate),
    const FlowMenuItemVm(FlowCommand.delete, danger: true),
    const FlowMenuItemVm(FlowCommand.selectAll, divider: true),
    const FlowMenuItemVm(FlowCommand.createCustomBlock, divider: true),
    FlowMenuItemVm(
      FlowCommand.editCustomBlock,
      disabledReason: ids.length == 1 ? null : 'Not a custom block',
    ),
  ],
);

/// A page of wave 2: what [_bind] gives, with the palette, the path, the
/// scope prompt and the custom-block dialog of ADR 0040.
FlowEditorPage _wave2({
  required List<FlowBlockVm> blocks,
  required List<FlowWireVm> wires,
  String? selected,
  String kind = '',
  String note = '',
  List<InspectorRowVm> rows = const [],
  String tab = 'blocks',
  List<PaletteEntryVm>? palette,
  List<TreeRowVm>? tree,
  List<String> crumbs = const [],
  String? insideNote,
  ScopePromptVm? prompt,
  List<(String, VoidCallback)> links = const [],
  String title = '',
  String? deployReason,
  FlowSummaryVm? summary,
}) => FlowEditorPage(
  flowsLabel: 'Flows',
  flowLabel: 'line',
  blockLabel: selected == null ? null : (title.isEmpty ? selected : title),
  state: 'Draft saved',
  stateDot: true,
  validateLabel: 'Validate',
  deployLabel: 'Deploy',
  onDeploy: () {},
  deployReason: deployReason,
  onValidate: () {},
  onClose: () {},
  onFlows: () {},
  onLogo: () {},
  paletteTabs: _tabs2(),
  paletteTab: tab,
  onPaletteTab: _id,
  palette: palette ?? (tree == null ? _blocks() : const []),
  paletteClosed: const {'Sources', 'Sinks', 'Code · WASM'},
  searchHint: tree == null ? 'Find a block' : 'Find a point or action',
  paletteNotes: tree == null
      ? const []
      : const [
          PaletteNoteVm(
            'Point',
            'on the canvas: a block that reads it (a writable point asks Read or Write; Alt writes). On a field: wired into it.',
          ),
          PaletteNoteVm(
            'Action',
            'a block that runs it: its parameters are fields you fill from other blocks, with a trigger.',
            ember: true,
          ),
        ],
  tree: tree,
  onTreeToggle: _id,
  onTreeQuery: _id,
  onPaletteMenu: _two,
  onPick: _id,
  blocks: blocks,
  wires: wires,
  blockActions: const FlowBlockActions(
    onSelect: _id,
    onBind: _bindField,
    onRebind: _four,
    onUnbind: _two,
    onDropEntry: _three,
    onResize: _resize,
    refusal: _refusal,
    onOpen: _id,
    onRowAction: _two,
  ),
  onClear: () {},
  onMove: (_, {required nudge}) {},
  onDrop: (_, _, _) {},
  legend: _legend,
  inspectorKind: kind,
  inspectorTitle: title.isEmpty ? (selected ?? '') : title,
  inspectorNote: note,
  inspectorRows: rows,
  summary: summary,
  inspectorFooter: _footer,
  inspectorLinks: links,
  onFieldChanged: _two,
  onFieldUnbind: _id,
  onFieldBind: (_, _) {},
  onProblem: _id,
  removeLabel: 'Remove block',
  onRemove: selected == null || selected.startsWith('~') ? null : () {},
  onView: _id,
  onCloseViewer: () {},
  onSelectMany: (_, {required add, required toggle}) {},
  onCommand: (_, {at}) {},
  onPin: (_, _, {required pinned}) {},
  onViewField: (_, _) {},
  onFieldPin: (_, {required pinned}) {},
  onRun: _id,
  menu: _menu2,
  crumbs: crumbs,
  onBack: (_) {},
  insideNote: insideNote,
  prompt: prompt,
  onPromptSave: _id,
  onPromptCancel: () {},
  validatePrompt: (s) => s.startsWith('sys')
      ? 'A scope starts with downstream, dataflows or storage'
      : null,
  createBlock: () => const CustomBlockDialogVm(
    title: 'Create custom block',
    note:
        '2 blocks become one block of this flow. Wires that cross its edge become its inputs and outputs.',
    name: 'block1',
    inputs: [
      BlockPortVm(name: 'sum_0', detail: '← a.out'),
      BlockPortVm(name: 'sum_1', detail: '← b.out'),
    ],
    outputs: [BlockPortVm(name: 'half', detail: '→ mean.in')],
  ),
  validateBlock: (r) =>
      r.name.contains(' ') ? 'A name has letters, digits and _ only' : null,
  onCreateBlock: (_) {},
);

FlowBlockVm _var(String id, String type, String value, double x, double y) =>
    FlowBlockVm(
      id: id,
      title: id,
      type: type,
      x: x + _m,
      y: y + _m,
      rows: [_r('value', value, outs: 'bound', label: 'Value')],
    );

/// A `subscribe` whose key comes from another block: the `Point` row is
/// bound, the `Scope` row reads what it may read (with its pencil), the
/// `Error` output is a row; [asking] shows the scope's prompt on it.
FlowEditorPage flowKeyScope({bool asking = false}) => _wave2(
  selected: 'level',
  kind: 'Tree node',
  note:
      'A point of the tree. A read-only point has no input; binding into a writable one writes ~set.',
  blocks: [
    _var('name', 'string', 'pump1', 30, 60),
    FlowBlockVm(
      id: 'path',
      title: 'path',
      type: 'concat',
      x: 300 + _m,
      y: 40 + _m,
      rows: [
        _r('in.0', 'downstream/modbus/line1/', label: 'Input 1'),
        _r(
          'in.1',
          'pump1',
          ins: 'bound',
          tone: ValueTone.bound,
          label: 'Input 2',
        ),
        _r('strict', 'false', label: 'Strict'),
        _r('out', 'downstream/modbus/line1/pump1', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(label: '2 inputs', canRemove: false),
    ),
    FlowBlockVm(
      id: 'level',
      title: 'level',
      type: 'modbus/line1',
      kind: BlockKindVm.node,
      x: 600 + _m,
      y: 60 + _m,
      width: 200,
      selected: true,
      rows: [
        _r(
          'key',
          'downstream/modbus/line1/pump1',
          ins: 'bound',
          tone: ValueTone.bound,
          label: 'Point',
        ),
        const FieldRowVm(
          id: 'p:key_scope',
          label: 'Scope',
          name: 'key_scope',
          value: 'downstream/modbus/line1/**',
          action: 'action_edit',
          actionTip: 'Edit the scope',
        ),
        _r('pump1', '41.5 %', ins: '', outs: 'bound'),
        _r('error', '', ins: '', label: 'Error'),
      ],
    ),
    FlowBlockVm(
      id: 'pub',
      title: 'publish',
      type: 'publish',
      kind: BlockKindVm.sink,
      x: 880 + _m,
      y: 80 + _m,
      width: 210,
      rows: [
        _r('node', 'level', ins: '', label: 'Value name'),
        _r('value', '41.5', ins: 'bound', outs: '', tone: ValueTone.bound),
      ],
    ),
  ],
  wires: const [
    FlowWireVm('name', 'value', 'path', 'in.1'),
    FlowWireVm('path', 'out', 'level', 'key'),
    FlowWireVm('level', 'pump1', 'pub', 'value'),
  ],
  prompt: asking
      ? const ScopePromptVm(
          block: 'level',
          row: 'p:key_scope',
          title: 'This block may read keys under',
          value: 'downstream/modbus/line1/**',
          note:
              'A key that comes on the wire is read only inside this scope. Whoever deploys must be able to read all of it.',
          suggestions: [
            'downstream/modbus/line1/**',
            'downstream/**',
            'dataflows/**',
            'storage/**',
          ],
        )
      : null,
  rows: const [
    InspectorRowVm(
      id: 'key',
      name: 'Point',
      engine: 'key',
      editor: FieldEditorVm.bound,
      value: 'downstream/modbus/line1/pump1',
      sourceBlock: 'path',
      inPort: 'key',
      pinned: true,
      pinLocked: true,
    ),
    InspectorRowVm(
      id: 'key_scope',
      name: 'Scope',
      engine: 'key_scope',
      editor: FieldEditorVm.text,
      value: 'downstream/modbus/line1/**',
      pinned: true,
    ),
    InspectorRowVm(
      id: 'pump1',
      name: 'pump1',
      engine: 'out',
      editor: FieldEditorVm.output,
      value: '41.5 %',
      targets: '→ publish.Value',
      pinned: true,
      pinLocked: true,
    ),
    InspectorRowVm(
      id: 'error',
      name: 'Error',
      engine: 'error',
      editor: FieldEditorVm.output,
      targets: 'not bound',
      pinned: true,
    ),
  ],
);

List<FlowBlockVm> _actionBlocks({bool preview = false}) => [
  _var('target', 'number', '40', 30, 80),
  FlowBlockVm(
    id: 'alarm',
    title: 'alarm',
    type: 'rising_edge',
    x: 30 + _m,
    y: 220 + _m,
    rows: [
      _r('in', 'true', ins: 'bound', tone: ValueTone.bound),
      _r('on_edge', '14:03:27', ins: '', outs: 'bound', label: 'On edge'),
    ],
  ),
  FlowBlockVm(
    id: 'ramp1',
    title: 'ramp1',
    type: 'pump · ramp',
    kind: BlockKindVm.action,
    x: 340 + _m,
    y: 80 + _m,
    width: 210,
    selected: true,
    tag: preview ? 'preview' : null,
    rows: [
      _r('target', '40', ins: 'write', tone: ValueTone.bound),
      _r(
        'trigger',
        preview ? 'would send {…}' : '',
        ins: 'write',
        tone: preview ? ValueTone.ghost : ValueTone.plain,
        label: 'Trigger',
      ),
      _r('ok', preview ? '' : '14:03:28', ins: '', label: 'Ok'),
      _r('error', '', ins: '', outs: 'bound', label: 'Error'),
    ],
  ),
  FlowBlockVm(
    id: 'pub',
    title: 'publish',
    type: 'publish',
    kind: BlockKindVm.sink,
    x: 640 + _m,
    y: 160 + _m,
    width: 210,
    rows: [
      _r('node', 'ramp_error', ins: '', label: 'Value name'),
      _r('value', '', ins: 'bound', outs: ''),
    ],
  ),
];

/// The action block (`invoke`): one block, its inspector in groups. The
/// trigger is bound here; [button] shows it unbound, with `Run`, and
/// [runReason] why `Run` is off; [preview] the ghost of what it would
/// send.
FlowEditorPage flowActionBlock({
  bool button = false,
  String? runReason,
  bool preview = false,
}) => _wave2(
  selected: 'ramp1',
  kind: 'Action',
  note:
      'An action of the tree. It runs on its trigger, on a changed argument, on a period, or by Run.',
  blocks: _actionBlocks(preview: preview),
  wires: [
    const FlowWireVm('target', 'value', 'ramp1', 'target', writes: true),
    if (!button)
      const FlowWireVm('alarm', 'on_edge', 'ramp1', 'trigger', writes: true),
    const FlowWireVm('ramp1', 'error', 'pub', 'value'),
  ],
  rows: [
    const InspectorRowVm(
      id: 'path',
      name: 'Node',
      engine: 'path',
      editor: FieldEditorVm.text,
      value: 'downstream/modbus/line1/pump',
      group: 'Target',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'action',
      name: 'Action',
      engine: 'action',
      editor: FieldEditorVm.text,
      value: 'ramp',
      group: 'Target',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'target',
      name: 'target',
      editor: FieldEditorVm.bound,
      value: '40',
      sourceBlock: 'target',
      writes: true,
      inPort: 'target',
      group: 'Arguments',
      pinned: true,
      pinLocked: true,
    ),
    const InspectorRowVm(
      id: 'ramp_s',
      name: 'ramp_s',
      editor: FieldEditorVm.text,
      value: '30',
      inPort: 'ramp_s',
      group: 'Arguments',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'mode',
      name: 'mode',
      editor: FieldEditorVm.choice,
      value: 'linear',
      choices: ['linear', 'step'],
      inPort: 'mode',
      group: 'Arguments',
      pinned: false,
    ),
    if (button)
      InspectorRowVm(
        id: 'trigger',
        name: 'Trigger',
        engine: 'trigger',
        editor: FieldEditorVm.run,
        value: 'Run',
        disabledReason: runReason,
        inPort: 'trigger',
        group: 'Behaviour',
        pinned: true,
      )
    else
      const InspectorRowVm(
        id: 'trigger',
        name: 'Trigger',
        engine: 'trigger',
        editor: FieldEditorVm.bound,
        value: '14:03:27',
        sourceBlock: 'alarm',
        writes: true,
        inPort: 'trigger',
        group: 'Behaviour',
        pinned: true,
        pinLocked: true,
      ),
    const InspectorRowVm(
      id: 'auto_run',
      name: 'Auto run',
      engine: 'auto_run',
      editor: FieldEditorVm.toggle,
      value: 'false',
      inPort: 'auto_run',
      group: 'Behaviour',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'interval_ms',
      name: 'Every',
      engine: 'interval_ms',
      editor: FieldEditorVm.duration,
      value: '300000',
      inPort: 'interval_ms',
      group: 'Behaviour',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'enabled',
      name: 'Enabled',
      engine: 'enabled',
      editor: FieldEditorVm.toggle,
      value: 'true',
      inPort: 'enabled',
      group: 'Behaviour',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'run_on_start',
      name: 'Run on start',
      engine: 'run_on_start',
      editor: FieldEditorVm.toggle,
      value: 'false',
      group: 'Behaviour',
      pinned: false,
      confirm: (
        'Run on every start?',
        'WARNING: true runs this command once every time the flow starts: at each deploy, hot swap, reload and broker restart (default false: a start never runs a command).',
      ),
    ),
    const InspectorRowVm(
      id: 'sent',
      name: 'Sent',
      engine: 'sent',
      editor: FieldEditorVm.output,
      value: '14:03:27',
      targets: 'not bound',
      group: 'Events',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'ok',
      name: 'Ok',
      engine: 'ok',
      editor: FieldEditorVm.output,
      value: '14:03:28',
      targets: 'not bound',
      group: 'Events',
      pinned: true,
    ),
    const InspectorRowVm(
      id: 'error',
      name: 'Error',
      engine: 'error',
      editor: FieldEditorVm.output,
      value: '13:58:02 · busy: queue full',
      targets: '→ publish.Value',
      group: 'Events',
      pinned: true,
      pinLocked: true,
    ),
    const InspectorRowVm(
      id: 'result',
      name: 'Result',
      engine: 'result',
      editor: FieldEditorVm.output,
      value: '{…}',
      targets: 'not bound',
      group: 'State',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'running',
      name: 'Running',
      engine: 'running',
      editor: FieldEditorVm.output,
      value: 'false',
      targets: 'not bound',
      group: 'State',
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'last_run',
      name: 'Last run',
      engine: 'last_run',
      editor: FieldEditorVm.output,
      value: '14:03:27',
      targets: 'not bound',
      group: 'State',
      pinned: false,
    ),
  ],
);

/// The Tree tab: the site's tree with its values as leaves and the actions
/// of an open node, in ember.
List<TreeRowVm> _treeRows() => const [
  TreeRowVm(
    id: 'd',
    name: 'downstream',
    depth: 0,
    hasChildren: true,
    expanded: true,
  ),
  TreeRowVm(
    id: 'd/modbus',
    name: 'modbus',
    depth: 1,
    icon: 'node_link',
    hasChildren: true,
    expanded: true,
  ),
  TreeRowVm(
    id: 'd/modbus/tcp-tank',
    name: 'tcp-tank',
    depth: 2,
    icon: 'node_device',
    hasChildren: true,
    expanded: true,
  ),
  TreeRowVm(
    id: 'a1',
    name: 'start_pump',
    depth: 3,
    tag: 'ACT',
    ember: true,
    value: '2 in',
    drag: 'act:start_pump',
  ),
  TreeRowVm(
    id: 'a2',
    name: 'stop_pump',
    depth: 3,
    tag: 'ACT',
    ember: true,
    value: '1 in',
    drag: 'act:stop_pump',
  ),
  TreeRowVm(
    id: 'k1',
    name: 'level_raw',
    depth: 3,
    tag: '.0',
    value: '3790',
    drag: 'key:level_raw',
    marked: true,
  ),
  TreeRowVm(
    id: 'k2',
    name: 'level_sp',
    depth: 3,
    tag: '.0',
    value: '90 %',
    drag: 'key:level_sp',
  ),
  TreeRowVm(
    id: 'k3',
    name: 'pump_run',
    depth: 3,
    tag: '01',
    value: 'off',
    drag: 'key:pump_run',
  ),
  TreeRowVm(
    id: 'k4',
    name: 'mode',
    depth: 3,
    tag: '≡',
    value: 'auto',
    drag: 'key:mode',
  ),
  TreeRowVm(
    id: 'd/modbus/tcp-boiler',
    name: 'tcp-boiler',
    depth: 2,
    icon: 'node_device',
    hasChildren: true,
  ),
  TreeRowVm(id: 'f', name: 'dataflows', depth: 0, hasChildren: true),
  TreeRowVm(
    id: 's',
    name: 'storage',
    depth: 0,
    icon: 'node_storage',
    hasChildren: true,
    expanded: true,
  ),
  TreeRowVm(
    id: 's/tank',
    name: 'tank',
    depth: 1,
    hasChildren: true,
    expanded: true,
  ),
  TreeRowVm(
    id: 'k6',
    name: 'level',
    depth: 2,
    tag: '.0',
    value: '92.6',
    drag: 'key:level',
  ),
  TreeRowVm(
    id: 'k7',
    name: 'state',
    depth: 2,
    tag: 'Aa',
    value: '"high"',
    drag: 'key:state',
  ),
];

/// The Tree tab beside the action block's flow.
FlowEditorPage flowTreeTab() => _wave2(
  tab: 'tree',
  tree: _treeRows(),
  blocks: [
    for (final b in _actionBlocks()) b.marked(selected: false),
  ],
  wires: const [
    FlowWireVm('target', 'value', 'ramp1', 'target', writes: true),
    FlowWireVm('alarm', 'on_edge', 'ramp1', 'trigger', writes: true),
    FlowWireVm('ramp1', 'error', 'pub', 'value'),
  ],
  summary: const FlowSummaryVm(
    label: 'Flow',
    title: 'line',
    facts: [('Version', '4'), ('May write', 'write')],
  ),
);

List<FlowBlockVm> _customBlocks({bool selected = true}) => [
  FlowBlockVm(
    id: 'a',
    title: 'a',
    type: 'modbus/line1',
    kind: BlockKindVm.node,
    x: 30 + _m,
    y: 60 + _m,
    width: 200,
    rows: [_r('a', '41.5', ins: '', outs: 'bound')],
  ),
  FlowBlockVm(
    id: 'b',
    title: 'b',
    type: 'modbus/line1',
    kind: BlockKindVm.node,
    x: 30 + _m,
    y: 180 + _m,
    width: 200,
    rows: [_r('b', '43.5', ins: '', outs: 'bound')],
  ),
  FlowBlockVm(
    id: 'mean21',
    title: 'mean21',
    type: 'mean2',
    kind: BlockKindVm.my,
    x: 320 + _m,
    y: 80 + _m,
    selected: selected,
    link: 'Open inside',
    rows: [
      _r('first', '41.5', ins: 'bound', tone: ValueTone.bound),
      _r('second', '43.5', ins: 'bound', tone: ValueTone.bound),
      _r('n', '2'),
      _r('out', '42.5', ins: '', outs: 'bound'),
    ],
  ),
  FlowBlockVm(
    id: 'pub',
    title: 'publish',
    type: 'publish',
    kind: BlockKindVm.sink,
    x: 620 + _m,
    y: 100 + _m,
    width: 210,
    rows: [
      _r('node', 'mean', ins: '', label: 'Value name'),
      _r('value', '42.5', ins: 'bound', outs: '', tone: ValueTone.bound),
    ],
  ),
];

const _customWires = [
  FlowWireVm('a', 'a', 'mean21', 'first'),
  FlowWireVm('b', 'b', 'mean21', 'second'),
  FlowWireVm('mean21', 'out', 'pub', 'value'),
];

List<PaletteEntryVm> _myBlocks() => const [
  PaletteEntryVm(
    id: 'type:block:mean2',
    title: 'mean2',
    tag: 'MY',
    group: 'This flow',
    detail: 'The mean of two values',
    value: '1 used',
    menu: [
      PaletteMenuItemVm('edit', 'Edit custom block'),
      PaletteMenuItemVm('save', 'Save to library'),
      PaletteMenuItemVm('rename', 'Rename'),
      PaletteMenuItemVm(
        'update',
        'Update from library',
        disabledReason: 'The library has no block of this name',
      ),
      PaletteMenuItemVm(
        'delete',
        'Delete',
        danger: true,
        disabledReason: '1 instance uses it',
      ),
    ],
  ),
  PaletteEntryVm(
    id: 'type:block:clamp',
    title: 'clamp',
    tag: 'MY',
    group: 'This flow',
    value: 'library v4',
  ),
  PaletteEntryVm(
    id: 'lib:clamp',
    title: 'clamp',
    tag: 'LIB',
    group: 'Site library',
    value: 'v4',
  ),
  PaletteEntryVm(
    id: 'lib:deadtime',
    title: 'deadtime',
    tag: 'LIB',
    group: 'Site library',
    value: 'v1',
  ),
  PaletteEntryVm(
    id: 'lib:mean',
    title: 'mean',
    tag: 'LIB',
    group: 'Site library',
    value: 'v2',
  ),
];

/// An instance of a custom block, selected: the `MY` chip, its declared
/// ports as fields, `Open inside`; the My blocks tab beside it.
FlowEditorPage flowCustomInstance() => _wave2(
  selected: 'mean21',
  kind: 'My block',
  note: 'The mean of two values',
  tab: 'my',
  palette: _myBlocks(),
  blocks: _customBlocks(),
  wires: _customWires,
  links: [('Open inside', () {})],
  rows: const [
    InspectorRowVm(
      id: 'first',
      name: 'first',
      editor: FieldEditorVm.bound,
      value: '41.5',
      sourceBlock: 'a',
      inPort: 'first',
      pinned: true,
      pinLocked: true,
    ),
    InspectorRowVm(
      id: 'second',
      name: 'second',
      editor: FieldEditorVm.bound,
      value: '43.5',
      sourceBlock: 'b',
      inPort: 'second',
      pinned: true,
      pinLocked: true,
    ),
    InspectorRowVm(
      id: 'n',
      name: 'n',
      editor: FieldEditorVm.text,
      value: '2',
      inPort: 'n',
      pinned: true,
    ),
    InspectorRowVm(
      id: 'out',
      name: 'out',
      editor: FieldEditorVm.output,
      value: '42.5',
      targets: '→ publish.Value',
      pinned: true,
      pinLocked: true,
    ),
  ],
);

/// The same flow with two blocks selected, for `Create custom block…`.
FlowEditorPage flowCustomCreate() => _wave2(
  tab: 'my',
  palette: _myBlocks(),
  blocks: [
    for (final b in _customBlocks(selected: false))
      b.marked(selected: b.id == 'a' || b.id == 'b'),
  ],
  wires: _customWires,
  summary: const FlowSummaryVm(label: 'Flow', title: 'line'),
);

/// The inside of `mean2`, opened from `mean21`: the path with the block,
/// `Back`, the inputs block and the outputs block around its nodes, live
/// values of that instance.
FlowEditorPage flowCustomInside() => _wave2(
  selected: '~in',
  title: 'Inputs',
  kind: 'Custom block',
  note:
      'What the block takes. Drag from an input to every inner field it feeds; type its default here. + adds an input.',
  crumbs: const ['mean2'],
  insideNote: '1 instance in this flow · a change here changes them all',
  deployReason: 'Go back to the flow to deploy',
  tab: 'my',
  palette: [
    for (final e in _myBlocks())
      if (e.id == 'type:block:mean2')
        const PaletteEntryVm(
          id: 'type:block:mean2',
          title: 'mean2',
          tag: 'MY',
          group: 'This flow',
          value: '1 used',
          disabledReason: 'A block cannot contain itself',
        )
      else
        e,
  ],
  blocks: [
    FlowBlockVm(
      id: '~in',
      title: 'Inputs',
      kind: BlockKindVm.my,
      x: 20 + _m,
      y: 60 + _m,
      width: 160,
      selected: true,
      rows: [
        _r('first', '', ins: '', outs: 'bound'),
        _r('second', '', ins: '', outs: 'bound'),
        _r('n', '2', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(
        label: '3 ports',
        addLabel: 'Add a port',
        removeLabel: 'Remove the last port',
      ),
    ),
    FlowBlockVm(
      id: 'sum',
      title: 'sum',
      type: 'add',
      x: 220 + _m,
      y: 40 + _m,
      rows: [
        _r(
          'in.0',
          '41.5',
          ins: 'bound',
          tone: ValueTone.bound,
          label: 'Input 1',
        ),
        _r(
          'in.1',
          '43.5',
          ins: 'bound',
          tone: ValueTone.bound,
          label: 'Input 2',
        ),
        _r('out', '85', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(label: '2 inputs', canRemove: false),
    ),
    FlowBlockVm(
      id: 'half',
      title: 'half',
      type: 'divide',
      x: 480 + _m,
      y: 60 + _m,
      rows: [
        _r('in.0', '85', ins: 'bound', tone: ValueTone.bound, label: 'Input 1'),
        _r('in.1', '2', ins: 'bound', tone: ValueTone.bound, label: 'Input 2'),
        _r('out', '42.5', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(label: '2 inputs', canRemove: false),
    ),
    FlowBlockVm(
      id: '~out',
      title: 'Outputs',
      kind: BlockKindVm.my,
      x: 730 + _m,
      y: 80 + _m,
      width: 150,
      rows: [_r('out', '42.5', ins: 'bound', outs: '', tone: ValueTone.bound)],
      variadic: const VariadicVm(
        label: '1 port',
        addLabel: 'Add a port',
        removeLabel: 'Remove the last port',
      ),
    ),
  ],
  wires: const [
    FlowWireVm('~in', 'first', 'sum', 'in.0'),
    FlowWireVm('~in', 'second', 'sum', 'in.1'),
    FlowWireVm('~in', 'n', 'half', 'in.1'),
    FlowWireVm('sum', 'out', 'half', 'in.0'),
    FlowWireVm('half', 'out', '~out', 'out'),
  ],
  rows: const [
    InspectorRowVm(
      id: 'first',
      name: 'first',
      editor: FieldEditorVm.text,
      hint: 'default',
      pinned: true,
      pinLocked: true,
    ),
    InspectorRowVm(
      id: 'second',
      name: 'second',
      editor: FieldEditorVm.text,
      hint: 'default',
      pinned: true,
      pinLocked: true,
    ),
    InspectorRowVm(
      id: 'n',
      name: 'n',
      editor: FieldEditorVm.text,
      value: '2',
      hint: 'default',
      pinned: true,
      pinLocked: true,
    ),
  ],
);
