// Canvas data, kept as the boards write it.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:ui/flows/bind_refusal.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/field_word.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_intents.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/flow_status.dart';
import 'package:ui/flows/flow_viewer.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/flows/shortcut_card.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/indicators/quality_mark.dart';
import 'package:ui/indicators/value_type.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/tables/table_edits.dart';
import 'package:ui/trees/json_tree.dart';

import '../support/test_query.dart';
import 'cells.dart';

// The data of boards *Flow editor · fields, bindings, properties* (FlowBind)
// and *· drag points and actions from the tree* (FlowTree), as
// FlowEditorPage arguments. The board's canvas has a 16 px margin; the
// blocks here carry it in their x and y.

const _m = 16.0;

/// Rows of the boards that are outputs only: a wire over one is refused.
const _outputsOnly = {'output', 'result', 'state', 't1', 't2', 'out'};

final _refusal = TestQuery<BindAsk, BindRefusalVm?>(
  (ask) => _outputsOnly.contains(ask.row.id) ? const RefuseOutput() : null,
);

void _id(String _) {}
void _tab(PaletteTabVm _) {}
void _typed(RowTyped _) {}

/// The moment [age] before now: a deploy `12 min ago` on a board.
DateTime _ago(Duration age) => DateTime.now().subtract(age);
void _index(int _) {}
void _rowBound(RowBound _) {}
void _pinned(RowPinned _) {}

/// The head of the inspector as a board words it (its kind, title and note
/// in English): the kind and a note of the app's own as their values, any
/// other note as the catalogue's description.
InspectorHeadVm? _head(String kind, String title, String note) {
  if (kind.isEmpty) {
    return null;
  }
  const kinds = {
    'Custom block': InspectorKindVm.ports,
    'Tree node': InspectorKindVm.node,
    'Logic block': InspectorKindVm.logic,
    'Sink': InspectorKindVm.sink,
    'Action': InspectorKindVm.action,
    'My block': InspectorKindVm.my,
  };
  final notes = {
    for (final n in InspectorNoteVm.values)
      if (n != InspectorNoteVm.catalog)
        InspectorHeadVm(kind: .logic, id: '', note: n).noteText: n,
  };
  final known = notes[note];
  return InspectorHeadVm(
    kind: kinds[kind]!,
    id: title,
    boundary: switch (title) {
      'Inputs' => BoundaryVm.inputs,
      'Outputs' => BoundaryVm.outputs,
      _ => null,
    },
    note: known ?? InspectorNoteVm.catalog,
    description: known == null ? note : '',
  );
}

void _rowRef(RowRef _) {}
void _bindWire(WireDropped _) {}
void _moveWire(WireMoved _) {}
void _resize(BlockResized _) {}
void _moved(BlocksMoved _) {}
void _selected(BlocksSelected _) {}
void _command(CanvasCommand _) {}

List<PaletteEntryVm> _blocks() => const [
  PaletteEntryVm(
    title: 'Subscribe',
    kind: PaletteKindVm.input,
    category: 'Sources',
  ),
  PaletteEntryVm(
    title: 'If',
    category: 'Logic',
    description: 'then when the inputs pass op, else otherwise.',
  ),
  PaletteEntryVm(
    title: 'Case',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'Router',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'Hub',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'Script · rhai',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'Delay',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'State',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'Stopwatch',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'Trace',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'Catch error',
    category: 'Logic',
  ),
  PaletteEntryVm(
    title: 'Repeat',
    glyph: 'RPT',
    category: 'Data',
  ),
  PaletteEntryVm(title: 'Table', glyph: 'TBL', category: 'Data'),
  PaletteEntryVm(
    title: 'Make object',
    glyph: '{}',
    category: 'Data',
  ),
  PaletteEntryVm(
    title: 'DQL query',
    glyph: 'DQL',
    category: 'Data',
  ),
  PaletteEntryVm(
    title: 'Publish',
    kind: PaletteKindVm.output,
    category: 'Sinks',
  ),
  PaletteEntryVm(
    title: 'WASM',
    category: 'Code · WASM',
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
  GhostKindVm? ghost,
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
    ghost: ghost,
  );
}

List<FlowBlockVm> _bindBlocks(String selected, {int cases = 2}) => [
  FlowBlockVm(
    id: 'plcL',
    title: 'plc1',
    caption: const ['tcp-boiler'],
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
    caption: const ['v3'],
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
      VariadicKindVm.pairs,
      count: cases,
      canRemove: cases > 1,
      canAdd: cases < 4,
    ),
  ),
  FlowBlockVm(
    id: 'script',
    title: 'script',
    caption: const ['rhai'],
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
    caption: const ['writes'],
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
    caption: const ['storage'],
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
  ViewerTables? tables,
}) => FlowEditorPage(
  flowName: flow,
  selected: selected == null ? null : title,
  status: FlowStatusVm.draft,
  stateDot: true,
  onDeploy: () {},
  onValidate: () {},
  onClose: () {},
  onFlows: () {},
  onLogo: () {},
  myBlocksOff: true,
  paletteTab: PaletteTabVm.blocks,
  onPaletteTab: _tab,
  palette: _blocks(),
  paletteClosed: const {'Sources', 'Sinks', 'Code · WASM'},
  blocks: blocks ?? _bindBlocks(selected ?? '', cases: cases),
  wires: wires ?? _bindWires,
  onSelect: _id,
  onBind: _bindWire,
  onRebind: _moveWire,
  onUnbind: _rowRef,
  onResize: _resize,
  refusal: _refusal,
  onClear: () {},
  onMove: _moved,
  inspector: _head(kind, title, note),
  inspectorRows: rows,
  summary: summary,
  onFieldChanged: _typed,
  onFieldUnbind: _index,
  onFieldBind: _rowBound,
  onProblem: _id,
  onRemove: selected == null ? null : () {},
  onView: _index,
  viewer: viewer == null ? null : FieldViewerVm(viewer),
  viewerTables: tables,
  onCloseViewer: () {},
  onSelectMany: _selected,
  onCommand: _command,
  onViewField: _rowRef,
  onFieldPin: pins ? _pinned : null,
  onSaveViewer: _id,
  checkViewer: TestQuery(
    (text) => text.contains('oops') ? ViewerTextProblemVm.json : null,
  ),
  mac: true,
  menu: TestQuery(
    (ask) => _menu(
      ask.ids,
      ask.block,
      ask.row,
      blocks ?? _bindBlocks(selected ?? '', cases: cases),
      hidden,
    ),
  ),
);

/// The context menu as the app builds it: of one block (with its fields),
/// of several, or of the canvas.
FlowMenuVm _menu(
  Set<String> ids,
  String? block,
  int? row,
  List<FlowBlockVm> blocks,
  Set<String> hidden,
) {
  final b = blocks.where((b) => b.id == block).firstOrNull;
  final one = ids.length == 1 && b != null;
  final none = ids.isEmpty ? const FlowOff(.nothingSelected) : null;
  FlowPinVm pin(String id, String label, {bool bound = false}) => FlowPinVm(
    label: label,
    pinned: !hidden.contains(id),
    locked: bound,
    onPin: (_) {},
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
    block: one ? b.heading : null,
    blockType: one ? (b.type.isEmpty ? 'case' : b.type) : null,
    count: ids.length,
    flow: 'tank-level',
    blocksInFlow: blocks.length,
    fields: fields,
    unpin: row == null || row >= fields.length ? null : fields[row],
    items: [
      FlowMenuItemVm(.cut, off: none),
      FlowMenuItemVm(.copy, off: none),
      const FlowMenuItemVm(.paste),
      FlowMenuItemVm(.duplicate, off: none),
      FlowMenuItemVm(.delete, off: none, danger: ids.isNotEmpty),
      const FlowMenuItemVm(.selectAll, divider: true),
      if (ids.isEmpty) ...const [
        FlowMenuItemVm(.undo, divider: true),
        FlowMenuItemVm(.redo, off: FlowOff(.nothingToRedo)),
      ],
      if (one) ...[
        const FlowMenuItemVm(.fields, divider: true),
        if (row != null) const FlowMenuItemVm(.unpin),
      ],
      if (ids.isNotEmpty)
        const FlowMenuItemVm(
          .createCustomBlock,
          divider: true,
          off: FlowOff(.needsBroker),
        ),
      if (one)
        const FlowMenuItemVm(
          .editCustomBlock,
          off: FlowOff(.needsBroker),
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
            caption: b.caption,
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
      name: 'tank-level',
      facts: [FactVersion(4), FactValues(.deployed)],
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
    locked: locked ? ViewerLockVm.bound : null,
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
    targets: [RowTargetVm('plc1', 'fan')],
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
  summary: FlowSummaryVm(
    name: 'tank-level',
    facts: [
      const FactVersion(4),
      FactDeployedBy('olena', at: _ago(const Duration(minutes: 12))),
      const FactMayWrite(.write),
      const FactReads([
        'downstream/modbus/tcp-boiler/t1',
        'downstream/modbus/tcp-boiler/t2',
      ]),
      const FactWrites(['downstream/modbus/tcp-boiler/fan']),
    ],
    problems: const [
      FlowProblemVm(
        .broker,
        message: 'node script: expr: unknown variable c',
        block: 'script',
      ),
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
  flowName: 'tank-level',
  selected: 'stop_pump',
  status: FlowStatusVm.draft,
  stateDot: true,
  onDeploy: () {},
  onValidate: () {},
  onClose: () {},
  onFlows: () {},
  onLogo: () {},
  myBlocksOff: true,
  paletteTab: PaletteTabVm.tree,
  onPaletteTab: _tab,
  palette: const [
    PaletteEntryVm(
      title: 'level_raw',
      glyph: '.0',
      category: 'modbus / tcp-tank',
      point: true,
      value: '3790',
      used: true,
    ),
    PaletteEntryVm(
      title: 'level_sp',
      glyph: '.0',
      category: 'modbus / tcp-tank',
      point: true,
      value: '90 %',
      dragging: true,
    ),
    PaletteEntryVm(
      title: 'pump_run',
      glyph: '01',
      category: 'modbus / tcp-tank',
      point: true,
      value: 'off',
      used: true,
    ),
    PaletteEntryVm(
      title: 'mode',
      glyph: '≡',
      category: 'modbus / tcp-tank',
      point: true,
      value: 'auto',
      used: true,
    ),
    PaletteEntryVm(
      title: 'pump_fault',
      glyph: '01',
      category: 'modbus / tcp-tank',
      point: true,
      value: 'off',
    ),
    PaletteEntryVm(
      title: 'start_pump',
      glyph: 'ACT',
      category: 'modbus / tcp-tank',
      point: true,
      action: true,
      value: '2 in',
    ),
    PaletteEntryVm(
      title: 'stop_pump',
      glyph: 'ACT',
      category: 'modbus / tcp-tank',
      point: true,
      action: true,
      value: '1 in',
      used: true,
    ),
    PaletteEntryVm(
      title: 'reset_alarm',
      glyph: 'ACT',
      category: 'modbus / tcp-tank',
      point: true,
      action: true,
      value: '0 in',
    ),
    PaletteEntryVm(
      title: 'level',
      glyph: '.0',
      category: 'storage / tank',
      point: true,
      value: '92.6',
    ),
    PaletteEntryVm(
      title: 'state',
      glyph: 'Aa',
      category: 'storage / tank',
      point: true,
      value: '"high"',
    ),
  ],
  blocks: [
    FlowBlockVm(
      id: 'tank',
      title: 'tank',
      caption: const ['modbus/tcp-tank'],
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
      caption: const ['scale'],
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
      caption: const ['op >'],
      x: 320 + _m,
      y: 300 + _m,
      rows: [
        _r('a', '92.6', ins: 'bound', tone: ValueTone.bound),
        _r('b', '90'),
        _r('out', 'true', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(.inputs, count: 2, canRemove: false),
    ),
    FlowBlockVm(
      id: 'pub',
      title: 'publish',
      caption: const ['storage'],
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
      caption: const ['modbus/tcp-tank'],
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
  onSelect: _id,
  onBind: _bindWire,
  onRebind: _moveWire,
  onUnbind: _rowRef,
  onResize: _resize,
  refusal: _refusal,
  onClear: () {},
  onMove: _moved,
  inspector: _head(
    'Action',
    'stop_pump',
    'Dragged from the tree. Runs when run when turns true; ok, code and message come back.',
  ),
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
    ),
    InspectorRowVm(
      id: 'code',
      name: 'Code',
      engine: 'code',
      editor: FieldEditorVm.output,
      value: '—',
    ),
    InspectorRowVm(
      id: 'message',
      name: 'Message',
      engine: 'message',
      editor: FieldEditorVm.output,
      value: 'stopped',
    ),
  ],
  onFieldChanged: _typed,
  onFieldUnbind: _index,
  onFieldBind: _rowBound,
  onProblem: _id,
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
        caption: const ['plc/tank'],
        kind: BlockKindVm.node,
        x: 40 + _m,
        y: 80 + _m,
        width: 200,
        rows: [_r('level_raw', '3790', ins: '', outs: 'bound')],
      ),
      FlowBlockVm(
        id: 'pct',
        title: 'pct',
        caption: const ['scale'],
        x: 320 + _m,
        y: 60 + _m,
        selected: true,
        rows: rows,
      ),
      FlowBlockVm(
        id: 'show',
        title: 'show',
        caption: const ['publish'],
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
        targets: [RowTargetVm('show', 'Value')],
      ),
      if (range)
        const InspectorRowVm(
          id: 'input_out_of_range',
          name: 'Input out of range',
          engine: 'input_out_of_range',
          editor: FieldEditorVm.output,
          value: 'false',
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
    caption: const ['string'],
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
    caption: const ['string'],
    x: 40 + _m,
    y: 180 + _m,
    selected: selected == 'who',
    rows: [_r('value', 'tank 3', outs: 'bound')],
  ),
  FlowBlockVm(
    id: 'limit',
    title: 'limit',
    caption: const ['number'],
    x: 40 + _m,
    y: 320 + _m,
    selected: selected == 'limit',
    rows: [_r('value', preview ? '70' : '25', outs: 'bound')],
  ),
  FlowBlockVm(
    id: 'armed',
    title: 'armed',
    caption: const ['bool'],
    x: 40 + _m,
    y: 440 + _m,
    selected: selected == 'armed',
    rows: [_r('value', 'true')],
  ),
  FlowBlockVm(
    id: 'text',
    title: 'text',
    caption: const ['concat'],
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
    variadic: const VariadicVm(.inputs, count: 2, canRemove: false),
  ),
  FlowBlockVm(
    id: 'cmd',
    title: 'cmd',
    caption: const ['scale'],
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
    caption: const ['publish'],
    kind: BlockKindVm.sink,
    x: 660 + _m,
    y: 100 + _m,
    width: 210,
    preview: preview,
    rows: [
      _r('node', 'banner', ins: '', outs: '', label: 'Value name'),
      _r(
        'in',
        'Hello, tank 3',
        outs: '',
        ins: 'bound',
        tone: preview ? ValueTone.ghost : ValueTone.bound,
        ghost: preview ? GhostKindVm.write : null,
        label: 'Value',
      ),
    ],
  ),
  FlowBlockVm(
    id: 'knob',
    title: 'knob',
    caption: const ['mockdev/bench/rig1'],
    kind: BlockKindVm.node,
    x: 660 + _m,
    y: 360 + _m,
    width: 210,
    preview: preview,
    rows: [
      _r(
        'in',
        preview ? '70.7' : '25.3',
        ins: 'write',
        outs: '',
        tone: preview ? ValueTone.ghost : ValueTone.bound,
        ghost: preview ? GhostKindVm.write : null,
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
      targets: [RowTargetVm('show', 'Value')],
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
  summary: FlowSummaryVm(
    name: 'banner',
    facts: [
      const FactVersion(3),
      FactDeployedBy('user:admin', at: _ago(const Duration(hours: 2))),
      const FactMayWrite(.write),
      const FactValues(.preview),
      const FactWrites(['downstream/mockdev/bench/rig1/knob']),
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
      caption: const ['plc/tank'],
      kind: BlockKindVm.node,
      x: 40 + _m,
      y: 80 + _m,
      width: 200,
      rows: [_r('level', '92.6 %', ins: '', outs: 'bound')],
    ),
    FlowBlockVm(
      id: 'tier',
      title: 'tier',
      caption: const ['case'],
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
      variadic: const VariadicVm(.pairs, count: 2),
    ),
    FlowBlockVm(
      id: 'show',
      title: 'show',
      caption: const ['publish'],
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
      targets: [RowTargetVm('show', 'Value')],
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
      caption: const ['number'],
      x: 40 + _m,
      y: 120 + _m,
      rows: [_r('value', '2', outs: 'bound')],
    ),
    FlowBlockVm(
      id: 'tag',
      title: 'tag',
      caption: const ['concat'],
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
      variadic: const VariadicVm(.inputs, count: 2, canRemove: false),
    ),
    FlowBlockVm(
      id: 'show',
      title: 'show',
      caption: const ['publish'],
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
      targets: [RowTargetVm('show', 'Value')],
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
      targets: [RowTargetVm('show', 'Value')],
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

FlowMenuVm _menu2(FlowMenuAsk ask) => FlowMenuVm(
  block: ask.ids.length > 1 ? null : ask.block,
  blockType: ask.ids.length > 1 ? null : 'block:mean2',
  count: ask.ids.length,
  flow: 'line',
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
      off: ask.ids.length == 1 ? null : const FlowOff(.notCustom),
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
  PaletteTabVm tab = PaletteTabVm.blocks,
  List<PaletteEntryVm>? palette,
  List<PaletteTreeRowVm>? tree,
  List<String> crumbs = const [],
  int? instances,
  ScopePromptVm? prompt,
  bool openInside = false,
  String title = '',
  FlowOffReason? deployOff,
  FlowSummaryVm? summary,
}) => FlowEditorPage(
  flowName: 'line',
  selected: selected == null ? null : (title.isEmpty ? selected : title),
  status: FlowStatusVm.draft,
  stateDot: true,
  onDeploy: () {},
  deployOff: deployOff == null ? null : FlowOff(deployOff),
  onValidate: () {},
  onClose: () {},
  onFlows: () {},
  onLogo: () {},
  paletteTab: tab,
  onPaletteTab: _tab,
  palette: palette ?? (tree == null ? _blocks() : const []),
  paletteClosed: const {'Sources', 'Sinks', 'Code · WASM'},
  tree: tree,
  onTreeToggle: _id,
  onTreeQuery: _id,
  blocks: blocks,
  wires: wires,
  onSelect: _id,
  onBind: _bindWire,
  onRebind: _moveWire,
  onUnbind: _rowRef,
  onResize: _resize,
  refusal: _refusal,
  onOpen: _id,
  onRowAction: _rowRef,
  onClear: () {},
  onMove: _moved,
  inspector: _head(kind, title.isEmpty ? (selected ?? '') : title, note),
  inspectorRows: rows,
  summary: summary,
  onOpenInside: openInside ? () {} : null,
  onFieldChanged: _typed,
  onFieldUnbind: _index,
  onFieldBind: _rowBound,
  onProblem: _id,
  onRemove: selected == null || selected.startsWith('~') ? null : () {},
  onView: _index,
  onCloseViewer: () {},
  onSelectMany: _selected,
  onCommand: _command,
  onViewField: _rowRef,
  onFieldPin: _pinned,
  onRun: _index,
  menu: TestQuery(_menu2),
  crumbs: crumbs,
  onBack: (_) {},
  instances: instances,
  prompt: prompt,
  onPromptSave: _id,
  onPromptCancel: () {},
  checkScope: TestQuery(
    (s) => s.startsWith('sys') ? ScopeProblemVm.section : null,
  ),
  createBlock: const CustomBlockDialogVm(
    blocks: 2,
    name: 'block1',
    inputs: [
      BlockPortVm(name: 'sum_0', outside: ['a.out']),
      BlockPortVm(name: 'sum_1', outside: ['b.out']),
    ],
    outputs: [
      BlockPortVm(name: 'half', outside: ['mean.in']),
    ],
  ),
  checkBlock: TestQuery(
    (r) => r.name.contains(' ') ? CustomBlockProblemVm.badName : null,
  ),
  onCreateBlock: (_) {},
);

FlowBlockVm _var(String id, String type, String value, double x, double y) =>
    FlowBlockVm(
      id: id,
      title: id,
      caption: [type],
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
  note: 'A point of the tree. A read-only point has no input; binding into a writable one writes ~set.',
  blocks: [
    _var('name', 'string', 'pump1', 30, 60),
    FlowBlockVm(
      id: 'path',
      title: 'path',
      caption: const ['concat'],
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
      variadic: const VariadicVm(.inputs, count: 2, canRemove: false),
    ),
    FlowBlockVm(
      id: 'level',
      title: 'level',
      caption: const ['modbus/line1'],
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
          editScope: true,
        ),
        _r('pump1', '41.5 %', ins: '', outs: 'bound'),
        _r('error', '', ins: '', label: 'Error'),
      ],
    ),
    FlowBlockVm(
      id: 'pub',
      title: 'publish',
      caption: const ['publish'],
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
          row: 1,
          value: 'downstream/modbus/line1/**',
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
      targets: [RowTargetVm('publish', 'Value')],
      pinned: true,
      pinLocked: true,
    ),
    InspectorRowVm(
      id: 'error',
      name: 'Error',
      engine: 'error',
      editor: FieldEditorVm.output,
      pinned: true,
    ),
  ],
);

List<FlowBlockVm> _actionBlocks({bool preview = false}) => [
  _var('target', 'number', '40', 30, 80),
  FlowBlockVm(
    id: 'alarm',
    title: 'alarm',
    caption: const ['rising_edge'],
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
    caption: const ['pump', 'ramp'],
    kind: BlockKindVm.action,
    x: 340 + _m,
    y: 80 + _m,
    width: 210,
    selected: true,
    preview: preview,
    rows: [
      _r('target', '40', ins: 'write', tone: ValueTone.bound),
      _r(
        'trigger',
        preview ? '{…}' : '',
        ins: 'write',
        tone: preview ? ValueTone.ghost : ValueTone.plain,
        ghost: preview ? GhostKindVm.send : null,
        label: 'Trigger',
      ),
      _r('ok', preview ? '' : '14:03:28', ins: '', label: 'Ok'),
      _r('error', '', ins: '', outs: 'bound', label: 'Error'),
    ],
  ),
  FlowBlockVm(
    id: 'pub',
    title: 'publish',
    caption: const ['publish'],
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
/// [runOff] why `Run` is off; [preview] the ghost of what it would send.
FlowEditorPage flowActionBlock({
  bool button = false,
  Disabled? runOff,
  bool preview = false,
}) => _wave2(
  selected: 'ramp1',
  kind: 'Action',
  note: 'An action of the tree. It runs on its trigger, on a changed argument, on a period, or by Run.',
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
      group: .target,
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'action',
      name: 'Action',
      engine: 'action',
      editor: FieldEditorVm.text,
      value: 'ramp',
      group: .target,
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
      group: .arguments,
      pinned: true,
      pinLocked: true,
    ),
    const InspectorRowVm(
      id: 'ramp_s',
      name: 'ramp_s',
      editor: FieldEditorVm.text,
      value: '30',
      inPort: 'ramp_s',
      group: .arguments,
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'mode',
      name: 'mode',
      editor: FieldEditorVm.choice,
      value: 'linear',
      choices: ['linear', 'step'],
      inPort: 'mode',
      group: .arguments,
      pinned: false,
    ),
    if (button)
      InspectorRowVm(
        id: 'trigger',
        name: 'Trigger',
        engine: 'trigger',
        editor: FieldEditorVm.run,
        off: runOff,
        inPort: 'trigger',
        group: .behaviour,
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
        group: .behaviour,
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
      group: .behaviour,
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'interval_ms',
      name: 'Every',
      engine: 'interval_ms',
      editor: FieldEditorVm.duration,
      value: '300000',
      inPort: 'interval_ms',
      group: .behaviour,
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'enabled',
      name: 'Enabled',
      engine: 'enabled',
      editor: FieldEditorVm.toggle,
      value: 'true',
      on: true,
      inPort: 'enabled',
      group: .behaviour,
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'run_on_start',
      name: 'Run on start',
      engine: 'run_on_start',
      editor: FieldEditorVm.toggle,
      value: 'false',
      group: .behaviour,
      pinned: false,
      confirm: 'WARNING: true runs this command once every time the flow starts: at each deploy, hot swap, reload and broker restart (default false: a start never runs a command).',
    ),
    const InspectorRowVm(
      id: 'sent',
      name: 'Sent',
      engine: 'sent',
      editor: FieldEditorVm.output,
      value: '14:03:27',
      group: .events,
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'ok',
      name: 'Ok',
      engine: 'ok',
      editor: FieldEditorVm.output,
      value: '14:03:28',
      group: .events,
      pinned: true,
    ),
    const InspectorRowVm(
      id: 'error',
      name: 'Error',
      engine: 'error',
      editor: FieldEditorVm.output,
      value: '13:58:02 · busy: queue full',
      targets: [RowTargetVm('publish', 'Value')],
      group: .events,
      pinned: true,
      pinLocked: true,
    ),
    const InspectorRowVm(
      id: 'result',
      name: 'Result',
      engine: 'result',
      editor: FieldEditorVm.output,
      value: '{…}',
      group: .state,
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'running',
      name: 'Running',
      engine: 'running',
      editor: FieldEditorVm.output,
      value: 'false',
      group: .state,
      pinned: false,
    ),
    const InspectorRowVm(
      id: 'last_run',
      name: 'Last run',
      engine: 'last_run',
      editor: FieldEditorVm.output,
      value: '14:03:27',
      group: .state,
      pinned: false,
    ),
  ],
);

/// The Tree tab: the site's tree with its values as leaves and the actions
/// of an open node, in ember.
List<PaletteTreeRowVm> _treeRows() => const [
  PaletteNodeRowVm(
    key: 'd',
    name: 'downstream',
    depth: 0,
    opens: true,
    open: true,
  ),
  PaletteNodeRowVm(
    key: 'd/modbus',
    name: 'modbus',
    depth: 1,
    icon: AppIcon.nodeLink,
    opens: true,
    open: true,
  ),
  PaletteNodeRowVm(
    key: 'd/modbus/tcp-tank',
    name: 'tcp-tank',
    depth: 2,
    icon: AppIcon.nodeDevice,
    opens: true,
    open: true,
  ),
  PaletteActionRowVm(
    key: 'a1',
    name: 'start_pump',
    depth: 3,
    node: 'd/modbus/tcp-tank',
    action: 'start_pump',
    inputs: 2,
  ),
  PaletteActionRowVm(
    key: 'a2',
    name: 'stop_pump',
    depth: 3,
    node: 'd/modbus/tcp-tank',
    action: 'stop_pump',
    inputs: 1,
  ),
  PaletteNodeRowVm(
    key: 'k1',
    name: 'level_raw',
    depth: 3,
    used: true,
    type: ValueType.numeric,
    value: '3790',
    places: true,
  ),
  PaletteNodeRowVm(
    key: 'k2',
    name: 'level_sp',
    depth: 3,
    type: ValueType.numeric,
    value: '90 %',
    places: true,
  ),
  PaletteNodeRowVm(
    key: 'k3',
    name: 'pump_run',
    depth: 3,
    type: ValueType.bool_,
    value: 'off',
    places: true,
  ),
  PaletteNodeRowVm(
    key: 'k4',
    name: 'mode',
    depth: 3,
    type: ValueType.enum_,
    value: 'auto',
    places: true,
  ),
  PaletteNodeRowVm(
    key: 'd/modbus/tcp-boiler',
    name: 'tcp-boiler',
    depth: 2,
    icon: AppIcon.nodeDevice,
    opens: true,
  ),
  PaletteNodeRowVm(
    key: 'f',
    name: 'dataflows',
    depth: 0,
    opens: true,
  ),
  PaletteNodeRowVm(
    key: 's',
    name: 'storage',
    depth: 0,
    icon: AppIcon.nodeStorage,
    opens: true,
    open: true,
  ),
  PaletteNodeRowVm(
    key: 's/tank',
    name: 'tank',
    depth: 1,
    opens: true,
    open: true,
  ),
  PaletteNodeRowVm(
    key: 'k6',
    name: 'level',
    depth: 2,
    type: ValueType.numeric,
    value: '92.6',
    places: true,
  ),
  PaletteNodeRowVm(
    key: 'k7',
    name: 'state',
    depth: 2,
    type: ValueType.string,
    value: '"high"',
    places: true,
  ),
];

/// The Tree tab beside the action block's flow.
FlowEditorPage flowTreeTab() => _wave2(
  tab: PaletteTabVm.tree,
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
    name: 'line',
    facts: [FactVersion(4), FactMayWrite(.write)],
  ),
);

List<FlowBlockVm> _customBlocks({bool selected = true}) => [
  FlowBlockVm(
    id: 'a',
    title: 'a',
    caption: const ['modbus/line1'],
    kind: BlockKindVm.node,
    x: 30 + _m,
    y: 60 + _m,
    width: 200,
    rows: [_r('a', '41.5', ins: '', outs: 'bound')],
  ),
  FlowBlockVm(
    id: 'b',
    title: 'b',
    caption: const ['modbus/line1'],
    kind: BlockKindVm.node,
    x: 30 + _m,
    y: 180 + _m,
    width: 200,
    rows: [_r('b', '43.5', ins: '', outs: 'bound')],
  ),
  FlowBlockVm(
    id: 'mean21',
    title: 'mean21',
    caption: const ['mean2'],
    kind: BlockKindVm.my,
    x: 320 + _m,
    y: 80 + _m,
    selected: selected,
    openable: true,
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
    caption: const ['publish'],
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
    title: 'mean2',
    kind: PaletteKindVm.my,
    description: 'The mean of two values',
    instances: 1,
    menu: [
      PaletteMenuItemVm(MyBlockItemVm.edit),
      PaletteMenuItemVm(MyBlockItemVm.save),
      PaletteMenuItemVm(MyBlockItemVm.rename),
      PaletteMenuItemVm(
        MyBlockItemVm.update,
        off: FlowOff(.notInLibrary),
      ),
      PaletteMenuItemVm(MyBlockItemVm.delete, off: InUse(1)),
    ],
  ),
  PaletteEntryVm(
    title: 'clamp',
    kind: PaletteKindVm.my,
    updateTo: 4,
  ),
  PaletteEntryVm(
    title: 'clamp',
    kind: PaletteKindVm.library,
    version: 4,
  ),
  PaletteEntryVm(
    title: 'deadtime',
    kind: PaletteKindVm.library,
    version: 1,
  ),
  PaletteEntryVm(
    title: 'mean',
    kind: PaletteKindVm.library,
    version: 2,
  ),
];

/// An instance of a custom block, selected: the `MY` chip, its declared
/// ports as fields, `Open inside`; the My blocks tab beside it.
FlowEditorPage flowCustomInstance() => _wave2(
  selected: 'mean21',
  kind: 'My block',
  note: 'The mean of two values',
  tab: PaletteTabVm.my,
  palette: _myBlocks(),
  blocks: _customBlocks(),
  wires: _customWires,
  openInside: true,
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
      targets: [RowTargetVm('publish', 'Value')],
      pinned: true,
      pinLocked: true,
    ),
  ],
);

/// The same flow with two blocks selected, for `Create custom block…`.
FlowEditorPage flowCustomCreate() => _wave2(
  tab: PaletteTabVm.my,
  palette: _myBlocks(),
  blocks: [
    for (final b in _customBlocks(selected: false))
      b.marked(selected: b.id == 'a' || b.id == 'b'),
  ],
  wires: _customWires,
  summary: const FlowSummaryVm(name: 'line'),
);

/// The inside of `mean2`, opened from `mean21`: the path with the block,
/// `Back`, the inputs block and the outputs block around its nodes, live
/// values of that instance.
FlowEditorPage flowCustomInside() => _wave2(
  selected: '~in',
  title: 'Inputs',
  kind: 'Custom block',
  note: 'What the block takes. Drag from an input to every inner field it feeds; type its default here. + adds an input.',
  crumbs: const ['mean2'],
  instances: 1,
  deployOff: FlowOffReason.deployInside,
  tab: PaletteTabVm.my,
  palette: [
    for (final e in _myBlocks())
      if (e.kind == PaletteKindVm.my && e.title == 'mean2')
        const PaletteEntryVm(
          title: 'mean2',
          kind: PaletteKindVm.my,
          instances: 1,
          insideItself: true,
        )
      else
        e,
  ],
  blocks: [
    FlowBlockVm(
      id: '~in',
      boundary: BoundaryVm.inputs,
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
      variadic: const VariadicVm(.ports, count: 3),
    ),
    FlowBlockVm(
      id: 'sum',
      title: 'sum',
      caption: const ['add'],
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
      variadic: const VariadicVm(.inputs, count: 2, canRemove: false),
    ),
    FlowBlockVm(
      id: 'half',
      title: 'half',
      caption: const ['divide'],
      x: 480 + _m,
      y: 60 + _m,
      rows: [
        _r('in.0', '85', ins: 'bound', tone: ValueTone.bound, label: 'Input 1'),
        _r('in.1', '2', ins: 'bound', tone: ValueTone.bound, label: 'Input 2'),
        _r('out', '42.5', ins: '', outs: 'bound'),
      ],
      variadic: const VariadicVm(.inputs, count: 2, canRemove: false),
    ),
    FlowBlockVm(
      id: '~out',
      boundary: BoundaryVm.outputs,
      kind: BlockKindVm.my,
      x: 730 + _m,
      y: 80 + _m,
      width: 150,
      rows: [_r('out', '42.5', ins: 'bound', outs: '', tone: ValueTone.bound)],
      variadic: const VariadicVm(.ports, count: 1),
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

/// A table typed into the `table` variable (owner request 2026-11-11):
/// the viewer as a grid of every row, cells by type, the filter, Add row
/// and Add column; Copy CSV and Copy JSON in the title row.
FlowEditorPage flowViewerTable() {
  final t = rawTable(
    ['t', 'name', 'kw', 'on', 'note', 'limits'],
    [
      [1762862400000000, 'pump 1', 3, true, 'duty', null],
      [
        1762862460000000,
        'pump 2',
        7.5,
        false,
        null,
        {'low': 20, 'high': 90},
      ],
      [1762862520000000, 'fan', 0.75, true, 'two lines\nof text', null],
      [1762862580000000, 'chiller', 12, false, 'standby', null],
      for (var i = 5; i <= 40; i++)
        [
          1762862400000000 + i * 60000000,
          'valve $i',
          i * 0.5,
          i.isEven,
          null,
          null,
        ],
    ],
  );
  return _bind(
    flow: 'plant-table',
    selected: 'text',
    kind: 'Logic block',
    title: 'text',
    blocks: _textBlocks('text'),
    wires: _textWires,
    viewer: ValueViewerVm(
      title: 'pumps.value',
      type: 'table',
      size: '40 rows · 6 columns',
      content: TableContentVm(t),
      copy: '',
      edit: ViewerEditVm(kind: .table, text: '', table: t),
    ),
    tables: ViewerTables(
      cellText: (column, cell) => switch (cell) {
        NumberCell(value: final int v) when column == 't' =>
          '2026-11-11 12:${((v - 1762862400000000) ~/ 60000000).toString().padLeft(2, '0')}:00',
        _ => null,
      },
      copyCsv: (_) => '',
    ),
  );
}

/// `table_from_csv` with a CSV of three lines typed into its Input: the
/// block's row shows the first line and `↲ +2`; the inspector's text row
/// grows to its lines; a bound row of two lines shows its mark too.
FlowEditorPage flowCsvLines() => _bind(
  flow: 'csv-import',
  selected: 'csv1',
  kind: 'Logic block',
  title: 'csv1',
  note: 'A CSV text as a table.',
  blocks: [
    FlowBlockVm(
      id: 'csv1',
      title: 'csv1',
      caption: const ['table_from_csv'],
      x: 340 + _m,
      y: 80 + _m,
      width: 240,
      selected: true,
      rows: [
        _r('in', 'name,kw\npump,3\nfan,7', label: 'Input'),
        _r('with_header', 'true', label: 'With header'),
        _r('delimiter', ',', label: 'Delimiter'),
        _r(
          'note',
          'checked by olena\non 2026-11-11',
          ins: 'bound',
          tone: ValueTone.bound,
          label: 'Note',
        ),
        _r('out', '{…}', ins: '', label: 'Output'),
      ],
    ),
  ],
  wires: const [],
  rows: const [
    InspectorRowVm(
      id: 'in:in',
      name: 'Input',
      engine: 'in',
      editor: FieldEditorVm.text,
      value: 'name,kw\npump,3\nfan,7',
      inPort: 'in',
    ),
    InspectorRowVm(
      id: 'note',
      name: 'Note',
      engine: 'note',
      editor: FieldEditorVm.bound,
      value: 'checked by olena\non 2026-11-11',
      sourceBlock: 'who',
      inPort: 'note',
    ),
    InspectorRowVm(
      id: 'out',
      name: 'Output',
      engine: 'out',
      editor: FieldEditorVm.output,
      value: '{…}',
    ),
  ],
);

/// A row's label of `flow_large.json` as the editor words it: `business`
/// writes a word Studio says itself by its name (`#point`, `#input 2`) and
/// the engine's own name as it came.
String _labelOf(String tag) {
  if (!tag.startsWith('#')) {
    return tag;
  }
  final parts = tag.substring(1).split(' ');
  return FieldWordVm(
    FieldWordTag.values.byName(parts.first),
    parts.length > 1 ? int.parse(parts[1]) : null,
  ).text;
}

/// The flow the agent deployed on the demo's `central` (62 blocks, no
/// saved layout) as the editor lays it out (flow-editor.md §25): the
/// places come from `business`'s layout (`flow_large.json`, written by
/// `business/test/flow_layout_test.dart`).
FlowEditorPage flowLarge() {
  final json = jsonDecode(
    File('test/frames/flow_large.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final wires = [
    for (final w in json['wires']! as List<Object?>)
      if (w case [
        final String from,
        final String fromPort,
        final String to,
        final String toPort,
      ])
        FlowWireVm(
          from,
          fromPort,
          to,
          toPort,
          writes: toPort == 'trigger' || toPort.startsWith('arg.'),
        ),
  ];
  bool bound(String block, String? port, {required bool output}) =>
      port != null &&
      wires.any(
        (w) => output
            ? w.from == block && w.fromPort == port
            : w.to == block && w.toPort == port,
      );
  final blocks = [
    for (final b in json['blocks']! as List<Object?>)
      if (b case {
        'id': final String id,
        'type': final String type,
        'role': final String role,
        'x': final num x,
        'y': final num y,
        'width': final num width,
        'rows': final List<Object?> rows,
      })
        FlowBlockVm(
          id: id,
          title: id,
          caption: [type],
          kind: switch (role) {
            'node' => BlockKindVm.node,
            'action' => BlockKindVm.action,
            'sink' => BlockKindVm.sink,
            _ => BlockKindVm.logic,
          },
          x: x.toDouble(),
          y: y.toDouble(),
          width: width.toDouble(),
          rows: [
            for (final r in rows)
              if (r case {
                'id': final String rid,
                'label': final String label,
                'in': final String? inPort,
                'out': final String? outPort,
              })
                FieldRowVm(
                  id: rid,
                  label: _labelOf(label),
                  name: rid,
                  inPort: inPort,
                  outPort: outPort,
                  inMark: inPort == null
                      ? PortMark.none
                      : (bound(id, inPort, output: false)
                            ? PortMark.bound
                            : PortMark.free),
                  outMark: outPort == null
                      ? PortMark.none
                      : (bound(id, outPort, output: true)
                            ? PortMark.bound
                            : PortMark.free),
                ),
          ],
        ),
  ];
  return _bind(
    selected: null,
    flow: 'dvpsm-bot',
    blocks: blocks,
    wires: wires,
    // The app's facts: the version of this flow (the board also listed
    // `Blocks · 62`, a fact the editor never shows).
    summary: const FlowSummaryVm(
      name: 'dvpsm-bot',
      facts: [FactVersion(2)],
    ),
  );
}
