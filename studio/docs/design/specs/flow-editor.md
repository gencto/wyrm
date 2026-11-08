# Flow editor

Boards: `FlowBind` (fields, bindings, properties), `FlowTree` (dragging points and actions from the tree). Canvas source: `../canvas/FlowBind.dc.html`, `../canvas/FlowTree.dc.html`. `FlowSymbol` and `FlowRepeat` wait for the engine (`docs/studio.md` §10 items 8, 9).

## 1. Regions (1440 wide)

| Region | Size | Background |
|---|---|---|
| Top bar | min height 52, padding 6 × 16 | `#0E1113`, bottom border `#252B30` |
| Palette | flex 1 1 220, **max 250** | `#13171A`, right border |
| Canvas | flex 999 1 560, scrolls both ways | `#0E1113` with a dot grid: radial `#252B30` 1 px every 20 px |
| Inspector | flex 1 1 320, max 360 | `#13171A`, left border |

**Side panels are resizable (proposed; the boards are fixed).** Drag the inner border of the palette or the inspector to change its width: palette 200–520 (default 220), inspector 280–640 (default 320); the canvas never gets less than 480. Handle, double click to reset, ←/→ and persistence as in `explorer.md` §1.

Top bar: logo (to Explorer) · path `Flows › <flow id> › <selected block>` (14; `Flows` link `#A3ABAF`, separators `#5A6168`, ids mono `#ECE9E1`) · right: state (`Draft saved` with a teal dot 6, `Saving…`, or `Version <n> · deployed` when the draft equals the deployed version; 12 `#8E979C`) · `Validate` (outline 38) · `Deploy` (ember filled 38; outline and disabled only while nothing differs from the deployed version, tooltip `Nothing to deploy`) · close.

## 2. Palette
- Tabs, three equal columns, 40 high: `Blocks` · `My blocks` · `Tree` (`My blocks` disabled with the tooltip `Needs own blocks in the engine` until §10 item 8 exists).
- `Find a block`: height 34, radius 6, fill `#1D2226`.
- Categories (13/600 `#C5CBCE`, chevron) from `node_types` `category`.
- **Items are one line, 32 high**: indent 24, a tag chip (24 × 16, mono 9/600: `IN` teal on `#15302A`, `OUT` ember on `#2A1F16`, `FX` `#C5CBCE` on `#22282D`), the name 13 `#C5CBCE`. **No description in the list**: it is the tooltip and the inspector note when the block is placed. Cursor `grab`; drag onto the canvas places a block.

## 3. Blocks
- Width **200–220** (210 for sinks). Radius 8, fill `#161A1D`, border `#2F373D` (selected: 1.5 ember + ring `rgba(232,137,58,0.14)` 4 px), shadow `0 8px 20px rgba(0,0,0,0.35)`.
- Header 32: tag chip (mono 9/600 with a 1 px border in the kind colour: `NODE` teal, `FX` `#C5CBCE`, `OUT` ember, `MY` ember), title mono 13/600 (the node id), type on the right mono 11 `#8E979C` (`scale`, `if`, `publish`, or the connection for a tree node). Header fill per kind: node `#15302A`, logic `#22282D`, sink `#22282D`.
- Body padding 6 × 12 × 8; **one row per field**, 28 high: label 12 `#A3ABAF` (no colon) · value mono 12 right-aligned (ellipsis) · ports. The row's tooltip is the engine name.

### Labels (owner decision 2026-11-08)
A row reads a human label, never the engine's name:
1. the catalog's own `display` for the parameter, when it has one;
2. else an override: `in` → `Input`, `out` → `Output`, `k` → `Factor`, `b` → `Offset`, `abs` → `Absolute change`, `pct` → `Percent change`, `fn` → `Function`, `op` → `Operation`, `expr` → `Expression`, `msg` → `Message`, `ms` → `Delay (ms)`, `key` → `Point`, `node` → `Value name`, `allow_bad` → `Allow bad quality`, `on_bad` → `On bad quality`; for a parameter of one type `<type>.<name>`: `latch.reset` → `Reset mode` (its input `reset` reads `Reset`), `set.on` → `Write on`, `invoke.on` → `Run on`, `set.path` → `Point`, `invoke.path` → `Node`, `stopwatch.interval` → `Interval (s)`; outputs `invoke.out` → `Result`, `alarm.out` → `Active`, `timer.out` → `Count`;
3. else sentence case with spaces: words split at `_`, the first capitalised, a unit suffix in brackets (`input_min` → `Input min`, `input_out_of_range` → `Input out of range`, `size_s` → `Size (s)`, `period_ms` → `Period (ms)`, `on_change` → `On change`).

Numbered inputs `in.0`, `in.1` read `Input 1`, `Input 2`. Names a user or a device gave stay as given: a tree point (`level`), an `expression` variable (`a`), a `wasm` port, an `invoke` argument (`ramp_s`); item labels of a block's own (`case 0`, `then 0`) too. Labels are English, like the catalog's descriptions. The engine name stays visible: small and mono under the label in the inspector, and as the row's tooltip. Code: `flow_fields.dart` `fieldLabel`.

### Forms
A type that does one of two things shows the form in use, never both sets of fields: `scale` is `k × in + b` (rows Input · Factor · Offset · Output; Factor and Offset have no left port: the engine has no `in.k`, `in.b`) or `Range` (Input · Input min · Input max · Output min · Output max · Output · Input out of range, each range field with both ports). The inspector's first row `Form` picks it; switching removes the other form's config and the wires into and out of its fields, and `Range` writes its four parameters so the definition says the form. A definition with both forms (the engine maps from the range, then applies `k`, `b`) shows both.

### Fields from `node_types` (the rule the app does not follow yet)
A block shows **fields**, not engine port names. For a node type with parameters `P` and ports `in`, `in.<p>`, `out`, …:

| Engine | Row label | Value shown | Left port (input) | Right port (output) |
|---|---|---|---|---|
| parameter `p` (with port `in.<p>`) | label of `p` (`Input min`; never `in.p`) | the parameter's value, else its default | yes | yes |
| parameter `p` (no `in.<p>`) | label of `p` (`Factor`) | the value | no | yes |
| input port `in` | `Input` | the last sample (live) | yes | yes |
| numbered inputs `in.0`, `in.1` | `Input 1`, `Input 2` | the last sample | yes | yes |
| output port `out`, `remainder`, … | `Output`, `Remainder`, … | the last output (live) | **no** | yes |
| sink field (`publish.key`, `value`) | the name | the value | yes | no |
| tree point, read-only | point name | live value with unit | no | yes |
| tree point, writable | point name | live value with unit | yes (binding writes `~set`) | yes |

So `scale` in its range form reads `Input · Input min 0 · Input max 4095 · Output min 0 · Output max 100 · Output 92.6 · Input out of range false`, each with its value; `modulo` reads `Input · Modulo 10 · Quotient · Remainder`. Every block type, field by field: `docs/flow-blocks.md` "How the editor shows each block".

- Value colours: bound `#F6C59A`, bad quality `#E07A5F`, otherwise `#ECE9E1`.
- Ports: 10 × 10 circles centred on the block edge (17 px outside the body padding), at the row's vertical centre. Free: ring 2 `#5A6168`, no fill. Bound: filled and ringed teal; an input bound by a write (into a device point, `set`, `invoke`) ember.
- Variadic blocks (`case`, `if` with several inputs, `add`): a tool row under the fields, top border: `−` `+` (28 × 28) and `<n> cases` / `<n> inputs`.

## 4. Wires
S-curves from the right port to the left port: `M x1 y1 C x1+dx y1, x2−dx y2, x2 y2`, `dx = max(50, |x2−x1|/2)`, width 2, drawn behind the blocks; the selected block's wires are drawn again over them. Teal reads a value; **ember only when the wire writes to a device** (into a writable point, a `set` or an `invoke`). A wire into `publish` (storage) is teal.

**Binding is drag and drop along a wire (owner decision 2026-11-08, as DGLux):**
1. Press a field's right port, or anywhere on its row, and move 3 px (on the screen): a live S-curve follows the pointer from the field's right port.
2. Over a row that takes it, the row lights teal (dashed) and the wire snaps to its left port. Over a row that refuses it, the row lights red, the wire turns red and a chip by the pointer says why: `Outputs cannot be bound`, `<field> takes no input: type its value`, `A block cannot feed itself`, `<type> does not fit <type>` (the catalog's `port_types`; a parameter's echo has the parameter's type), `This closes a loop (only a delay may)`.
3. Let go on a row that takes it: it binds (an input has one wire; a wire already there is replaced). Let go anywhere else: nothing.
4. On a bound input, the left port (and the whole row of a field without an output) picks its wire up; let go on another input, the wire moves there; on the empty canvas, it unbinds. The input it leaves keeps its last value when it is a parameter.
5. A double click or an Alt-click on a bound input unbinds; so does the link icon in the inspector.
6. A new wire let go on a row of the inspector binds that field (a picked-up wire moves between canvas inputs only).

The header moves a block: it stays under the grab point at any zoom and scroll and snaps to the 20 px grid when let go. A palette entry dropped on the canvas lands with the pointer on its header. The empty canvas pans, and so do two fingers on a trackpad; pinch and the wheel zoom; a click on the empty canvas clears the selection.

## 5. Legend
Pinned bottom-left over the canvas (sticky, `rgba(19,23,26,0.92)`, border `#252B30`, radius 8, 12 `#A3ABAF`): teal line `reads a value` · ember line `writes to a device` · grey ring `free field` · `no left port = read-only point`.

## 6. Inspector
- Header: kind label (`Tree node`, `Logic block`, `Sink`, `My block`; 12/600 uppercase), title mono 18/600, note 12 `#8E979C` (the type's description).
- A block with two forms (§3 Forms) first has a `Form` row: a dropdown.
- One row per field (min height 44, columns 104 · 1fr · 32, bottom border `#1D2226`): label 13 `#A3ABAF` with the engine name under it (mono 10 `#8E979C`, when it differs) · editor · link button. A wire dragged from the canvas and let go on a row binds it.
  - bound: a chip `← <block>.<field>` (teal on `#15302A`, ember on `#2A1F16` when it writes);
  - enum: a dropdown; free input: a text field 32 high mono 12;
  - output only: the value and `→ <targets>` or `not bound`.
- Footer: `Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.` and `A bound field shows its source here and in the block; click the link icon to unbind.`
- **Nothing selected** (proposed): label `FLOW`, the flow id, version, deployed by and when, `maxperm`, the problems of the last validation (each clickable, selecting its block). Never an empty panel.

## 7. Tree tab (board `FlowTree`)
The palette shows the tree; a point dropped on a block adds it as a field of that block (the target row lights with a dashed ember box); dropped on the canvas it becomes a tree-node block. An action dropped anywhere becomes an `ACT` block whose fields are the action's parameters, plus `run when` (input) and `ok`, `code`, `message` (outputs). Point rows: tag (`.0`, `01`, `≡`, `Aa`) + mono name + live value; action rows ember with `ACT` and the number of inputs.

## 8. Checklist
- [ ] Palette max 250, three tabs, one-line items with tag chips, no descriptions in the list
- [ ] Blocks 200–220 wide; header chip, mono title, type on the right
- [ ] Rows are fields with values per §3 (no `in.` prefixes, values shown)
- [ ] Ports on both sides per the table; free / bound / write colours
- [ ] Wires teal except device writes
- [ ] Legend pinned bottom-left
- [ ] Inspector rows with chip / dropdown / input / output; flow summary when nothing is selected
- [ ] Top bar: path with the selected block, `Draft saved`, Deploy enabled when the draft differs
- [ ] Goldens: block selected, nothing selected, a bound write wire, a variadic block, the Tree tab with a drag in progress

## 9. Found in the app (screenshot 2026-11-08)
1. Rows show engine port names (`in.input_min:`, `in.then:`, `in.0:`) instead of field names.
2. Parameter values are empty (`input_min`, `input_max`, `output_min`, `output_max` show nothing); only a few rows carry a value.
3. Parameter rows have only a left port and output rows only a right port: fields have no output, so a parameter cannot feed another block.
4. Blocks are ~320 wide instead of 200–220, so the graph spreads and wires cross.
5. Palette items are two lines with a mono description; the board has one-line items.
6. `My blocks` tab missing (show it disabled with the reason).
7. Wires into `publish` are ember; they read, so teal.
8. No legend.
9. With nothing selected the inspector is empty under `BLOCK`.
10. The top bar shows `Version 2` and a disabled Deploy; show `Draft saved` and enable Deploy when the draft differs.

## 10. Owner's findings (2026-11-08, second review) and what changed
1. Binding was a drag of a chip, not a wire: now drag and drop along a live wire (§4), with a lit target, the refusal reason, picking a wire up, double click / Alt-click to unbind.
2. A dragged block jumped from the pointer (deltas summed in the wrong space, the viewer panning with it): the canvas places it from the pointer's canvas position minus the grab offset (§4); widget test at zoom 1.5 with scroll.
3. Rows read engine names with a colon (`input_min:`): human labels (§3 Labels).
4. `scale` showed `k`, `b` and the range at once; outputs without values: forms (§3 Forms) and a field-by-field review of every type (`docs/flow-blocks.md`).

