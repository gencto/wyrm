# Flow editor

Boards: `FlowBind` (fields, bindings, properties), `FlowTree` (dragging points and actions from the tree). Canvas source: `../canvas/FlowBind.dc.html`, `../canvas/FlowTree.dc.html`. `FlowSymbol` and `FlowRepeat` wait for the engine (`docs/studio.md` §10 items 8, 9).

## 1. Regions (1440 wide)

| Region | Size | Background |
|---|---|---|
| Top bar | min height 52, padding 6 × 16; on the desktop it is the window's title bar (below) | `#0E1113`, bottom border `#252B30` |
| Palette | flex 1 1 220, **max 250** | `#13171A`, right border |
| Canvas | flex 999 1 560, scrolls both ways | `#0E1113` with a dot grid: radial `#252B30` 1 px every 20 px |
| Inspector | flex 1 1 320, max 360 | `#13171A`, left border |

**Side panels are resizable (proposed; the boards are fixed).** Drag the inner border of the palette or the inspector to change its width: palette 200–520 (default 220), inspector 280–640 (default 320); the canvas never gets less than 480. Handle, double click to reset, ←/→ and persistence as in `explorer.md` §1.

Top bar: logo (to Explorer) · path `Flows › <flow id> › <selected block>` (14; `Flows` link `#A3ABAF`, separators `#5A6168`, ids mono `#ECE9E1`) · right: state (`Draft saved` with a teal dot 6, `Saving…`, or `Version <n> · deployed` when the draft equals the deployed version; 12 `#8E979C`) · `Validate` (outline 38) · `Deploy` (ember filled 38; outline and disabled only while nothing differs from the deployed version, tooltip `Nothing to deploy`) · close.

**Owner decision 2026-11-09: no window frame on the desktop** (`docs/studio.md` §7.1). The top bar drags the window (a click on the logo, `Flows`, a button or close is still theirs). macOS: the logo starts at 92, after the native window buttons. Windows and Linux: the bar's content, its own close included, ends 138 from the right edge, left of the window's minimize, maximize and close.

## 2. Palette
- Tabs, three equal columns, 40 high: `Blocks` · `My blocks` · `Tree` (`My blocks` disabled with the tooltip `Needs own blocks in the engine` until §10 item 8 exists).
- `Find a block`: height 34, radius 6, fill `#1D2226`.
- Categories (13/600 `#C5CBCE`, chevron) from `node_types` `category`.
- **Items are one line, 32 high**: indent 24, a tag chip (24 × 16, mono 9/600: `IN` teal on `#15302A`, `OUT` ember on `#2A1F16`, `FX` `#C5CBCE` on `#22282D`), the name 13 `#C5CBCE`. **No description in the list**: it is the tooltip and the inspector note when the block is placed. Cursor `grab`; drag onto the canvas places a block.

## 3. Blocks
- Width **200–220** (210 for sinks). Radius 8, fill `#161A1D`, border `#2F373D` (selected: 1.5 ember + ring `rgba(232,137,58,0.14)` 4 px), shadow `0 8px 20px rgba(0,0,0,0.35)`.
- Header 32: tag chip (mono 9/600 with a 1 px border in the kind colour: `NODE` teal, `FX` `#C5CBCE`, `OUT` ember, `MY` ember), title mono 13/600 (the node id), type on the right mono 11 `#8E979C` (`scale`, `if`, `publish`, or the connection for a tree node). Header fill per kind: node `#15302A`, logic `#22282D`, sink `#22282D`.
- Body padding 6 × 12 × 8; **one row per pinned field** (§12), 28 high: label 12 `#A3ABAF` (no colon) · value mono 12 right-aligned (ellipsis) · ports. The row's tooltip is the engine name.

### Labels (owner decision 2026-11-08)
A row reads a human label, never the engine's name:
1. the catalog's own `display` for the parameter, when it has one;
2. else an override: `in` → `Input`, `out` → `Output`, `k` → `Factor`, `b` → `Offset`, `abs` → `Absolute change`, `pct` → `Percent change`, `fn` → `Function`, `op` → `Operation`, `expr` → `Expression`, `msg` → `Message`, `ms` → `Delay (ms)`, `key` → `Point`, `node` → `Value name`, `allow_bad` → `Allow bad quality`, `on_bad` → `On bad quality`; for a parameter of one type `<type>.<name>`: `latch.reset` → `Reset mode` (its input `reset` reads `Reset`), `set.on` → `Write on`, `invoke.on` → `Run on`, `set.path` → `Point`, `invoke.path` → `Node`, `stopwatch.interval` → `Interval (s)`; outputs `invoke.out` → `Result`, `alarm.out` → `Active`, `timer.out` → `Count`;
3. else sentence case with spaces: words split at `_`, the first capitalised, a unit suffix in brackets (`input_min` → `Input min`, `input_out_of_range` → `Input out of range`, `size_s` → `Size (s)`, `period_ms` → `Period (ms)`, `on_change` → `On change`).

Numbered inputs `in.0`, `in.1` read `Input 1`, `Input 2`. A block whose inputs come in pairs (`case`) reads them by position: `Case 1`, `Then 1`, `Case 2`, `Then 2`, and its − / + takes or adds a pair (`<n> cases`). Names a user or a device gave stay as given: a tree point (`level`), an `expression` variable (`a`), a `wasm` port, an `invoke` argument (`ramp_s`). Labels are English, like the catalog's descriptions. The engine name stays visible: small and mono under the label in the inspector, and as the row's tooltip. Code: `flow_fields.dart` `fieldLabel`.

### Forms
A type that does one of two things shows the form in use, never both sets of fields: `scale` is `k × in + b` (rows Input · Factor · Offset · Output; Factor and Offset bind through `in.k`, `in.b` since spec 06 0.2.17) or `Range` (Input · Input min · Input max · Output min · Output max · Output · Input out of range, each range field with both ports). The inspector's first row `Form` picks it; switching removes the other form's config and the wires into and out of its fields, and `Range` writes its four parameters so the definition says the form. A definition with both forms (the engine maps from the range, then applies `k`, `b`) shows both.

### One field = one entity (owner decision 2026-11-08)
A block's input and its value are ONE thing, as in DGLux: one row holds the field's value, its binding and what it feeds. Never a row for the value, another for the input and a third for the echo.
- A field `p` = parameter `p` ∪ input `in.<p>` ∪ echo output `p`.
- The main value of a variable block (`number`, `string`, `bool`, `const`: input `in`, parameter `value`, output `out`) is ONE field `Value` (DGLux: the one property `value`). `const` has no input. A typed editor in the inspector: a number box, a text field, a toggle.
- An operator's operands (`in`, `in.0`, `in.1`, …) are fields with a value and both ports. **The value is typed** (ADR 0038 §7, spec 06 0.2.19, owner review 2026-11-08): typing it writes the node's config `values: {"<port>": <value>}` under the engine port (`concat` `values: {"in.0": "AHU-"}`); a binding replaces it on the row and in the engine, the typed value stays in the config and returns on unbind (as DGLux). Only for a type whose catalog says `values: true`, never for a parameter's port (the parameter's config is its value), `stopwatch.reset` or a variable's `in`. The row shows the bound value that comes in (accent), else the typed value; the inspector a text field, read as JSON when it parses (`2` is a number, `AHU-` a text). A removed variable input takes its constant with it (the engine refuses `values.<port>: not an operand input`). Its result (`out`, `quotient`, …) is a field `Output` with a right port only. `scale`: `in` is `Input`, `out` is `Output`.
- Binding INTO a field is an edge to its engine input (`in.<p>`, or `in` for a variable's `Value`); binding OUT of a field is an edge from its echo or output (`out` for a variable's `Value`, `p` for a parameter). An older edge from a variable's echo `value` or `in` draws on the `Value` row.
- Order as DGLux: operands, parameters, variable inputs, the parameters DGLux draws after them (`if` Then, Else; `concat` Strict; `hub` Ignore null), results.
- **A bound field shows the VALUE that comes in, never the path** (no `← block.field`). The wire and its highlight show the source: the pointer over a bound field lights its wire and the source row. A bound field with nothing known yet shows nothing, not the typed value the binding replaces.

The mapping per block type: `docs/flow-blocks.md` "How the editor shows each block".

### Fields from `node_types`
For a node type with parameters `P` and ports `in`, `in.<p>`, `out`, …:

| Engine | Row label | Value shown | Left port (input) | Right port (output) |
|---|---|---|---|---|
| parameter `p` (with port `in.<p>`) | label of `p` (`Input min`; never `in.p`) | bound: the value that comes in; else the parameter's value, else its default | yes | yes |
| a variable's `value` (`in`, `value`, `out`) | `Value` | what it sends, else what comes in, else its value | yes (`const`: no) | yes (`out`) |
| parameter `p` (no `in.<p>`) | label of `p` (`Factor`) | the value | no | yes |
| input port `in` | `Input` | the last sample (live) | yes | yes |
| numbered inputs `in.0`, `in.1` | `Input 1`, `Input 2` | the last sample | yes | yes |
| output port `out`, `remainder`, … | `Output`, `Remainder`, … | the last output (live) | **no** | yes |
| sink field (`publish.key`, `value`) | the name | the value | yes | no |
| tree point, read-only | point name | live value with unit | no | yes |
| tree point, writable | point name | live value with unit | yes (binding writes `~set`) | yes |

So `scale` in its range form reads `Input · Input min 0 · Input max 4095 · Output min 0 · Output max 100 · Output 92.6 · Input out of range false`, each with its value; `modulo` reads `Input · Modulo 10 · Quotient · Remainder`. Every block type, field by field: `docs/flow-blocks.md` "How the editor shows each block".

- Value colours: bound `#F6C59A` (the value that comes in), bad quality `#E07A5F`, stale `#5A6168` (an invalid draft: the preview's last values), ghost italic ember (what a sink would write in a preview), otherwise `#ECE9E1`.
- A sink with a preview value has a `preview` chip after its title and reads `would write <value>` (`invoke`: `would run on <value>`) on its input row.
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

The header moves a block, and with it the whole selection when the block is part of one (§13): it stays under the grab point at any zoom and scroll and snaps to the 20 px grid when let go. A palette entry dropped on the canvas lands with the pointer on its header. A drag on the empty canvas draws a marquee (§13); a click there clears the selection. Space + drag, the middle button, the wheel and two fingers on a trackpad pan; ⌘/Ctrl + wheel and a pinch zoom (§14).

## 5. Legend
Pinned bottom-left over the canvas (sticky, `rgba(19,23,26,0.92)`, border `#252B30`, radius 8, 12 `#A3ABAF`): teal line `reads a value` · ember line `writes to a device` · grey ring `free field` · `no left port = read-only point`.

Beside it, in the same style, 34 high: the zoom (`100%`, mono 12; a click goes back to 100 %) and the `?` button of the shortcut card (§14; ember tint while the card is open).

## 6. Inspector
- Header: kind label (`Tree node`, `Logic block`, `Sink`, `My block`; 12/600 uppercase), title mono 18/600, note 12 `#8E979C` (the type's description).
- A block with two forms (§3 Forms) first has a `Form` row: a dropdown.
- One row per field, pinned to the block or not (min height 44, columns 18 · 86 · 1fr · 28 · 28, bottom border `#1D2226`): pin (`ui_pin` 14, §12) · label 13 `#A3ABAF` with the engine name under it (mono 10 `#8E979C`, when it differs) · editor · link button · view button (`ui_view`, owner request 2026-11-09). The `Form` row has no pin: its label takes the 104. A wire dragged from the canvas and let go on a row binds it. Every value ends in an ellipsis in its cell (an `Output` of `concat` overflowed by 7.7 px, owner 2026-11-09); the view button opens the value whole in the value viewer (`docs/studio.md` §6.8): a floating window titled `<block>.<field>`, live, styled by type.
  - bound: the value that comes in, read only, mono 12 in the accent colour in a frame (teal; ember when it writes), with a small `bound` mark; no path. The link button opens a menu: `Go to source` (selects the source block), `Unbind`;
  - enum: a dropdown; free input: a text field 32 high mono 12;
  - output only: the value and `→ <targets>` or `not bound`.
- Footer: `Every field has a value, an input and an output. Type a value, or drag from any output onto it to bind.` and `A bound field shows the value that comes in; its wire and source light when you point at it. The link icon goes to the source or unbinds.`
- **Nothing selected** (proposed): label `FLOW`, the flow id, version, deployed by and when, `maxperm`, `Values` (`a preview of the draft; nothing is written` or `the deployed version`), the problems of the last validation and the preview's compiler message (`The draft does not run: …`; each clickable, selecting its block). Never an empty panel.

### Live values of a draft
Values show for the draft being edited, not only the deployed version. While the draft runs otherwise than the deployed version (its layout aside), Studio runs it as a preview: `dataflows/~act/preview {def, max_hz}` (no layout, no version; id `draft` for a new flow), the same rows as `watch` plus `sinks: [{node, op, key, value}]` — what `set`/`invoke`/`publish` would do; nothing is written. `FlowPreviewService`:
1. opens it 300 ms after the last edit; the same definition again (a block moved) does not reopen; an edit ends the preview before at once;
2. opens it again when it ends (ttl 10 min), after a back-off on a failure or `busy`; a stream that ends well before its ttl was ended by the broker's cap (2 previews per subject, a third ends the oldest): no error, its values stay, it opens again after 30 s (not at once, so two windows of one user do not keep ending each other's). The previews an edit closed stay on the broker until the cap ends them; the one in use is always the newest;
3. `invalid_parameter`: the compiler message goes to the flow summary, the last values stay, greyed; the next edit tries again;
4. `not_found` / `not_supported` (a broker without preview) and `permission_denied`: it stops asking until the next login; the editor quietly shows the watch's and the definition's values.
A draft equal to the deployed version ends the preview: the watch shows it. Where no sample is known, a field follows its wire in the draft back to the source field's value (a variable's or parameter's typed value, a point's tree value).

With several blocks selected the inspector shows the flow and the path reads `<n> blocks`.

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
- [ ] Pins: a field taken off a block stays in the inspector; a bound field cannot be taken off; pins survive deploy and reload (§12)
- [ ] Marquee, Shift/⌘-click, the selection moved by a header, the context menu, copy/paste between flows, undo/redo (§13)
- [ ] The shortcut card lists the table the handlers read; no key fires while a text field has the focus (§14)
- [ ] The viewer edits a typed field and says why a bound or output field is read only (§15)
- [ ] Goldens: `flow_pins`, `flow_marquee`, `flow_selection_menu`, `flow_shortcuts`, `flow_shortcuts_ctrl`, `flow_viewer_edit`, `flow_viewer_locked`

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

## 11. Owner's findings (2026-11-08, third review) and what changed
1. "A block's input and its value are one entity": one row per field (§3 One field = one entity); a variable is one field `Value`.
2. "We need the VALUE that comes with the binding, not the path": no `← block.field` in rows or the inspector; the bound value in the accent colour; the source by the lit wire and row on hover, `Go to source` in the link menu.
3. "Blocks do not work in real time, concat does not work": the watch (ADR 0038 §6) records only from its opening, so a value sent once at start (a `string`, then `concat`) is never seen; and a draft had no values at all. Now the draft runs as a preview, and a field without a sample follows its wire to the source's typed value. Engine gaps: `docs/flow-blocks.md`.
4. Data-type blocks redone: `number`, `string`, `bool`, `const` are one field `Value` with a typed editor.
5. Every block checked against the DGLux block of the same purpose: order as DGLux (`if` Then, Else after the inputs; `concat` Strict after them).

## 12. Pins (owner decision 2026-11-09)
"Some fields should be pinnable for viewing on the canvas, and some are not mandatory and can be unpinned." As DGLux (`!ps`): a block draws only its pinned fields; the inspector always lists every field.

- **Per block.** A field is a row of its block when: a wire goes into it or out of it (always); else the user's choice for this block; else the default of its type.
- **Defaults per type** (`FlowField.onBlock` in `flow_fields.dart`): the inputs, the outputs, every parameter with an input port, a form's parameters, a parameter with a value in the config, with a default or required. Off by default: a parameter with no port, no default and no value in the config; every parameter of a tree node (its point shows as the row of its value); `path`, `args` and `allow_bad` of an action block.
- **The pin toggle.** The inspector has a pin before each row's label (`ui_pin` 14: ember = on the block, grey = only here, teal = held by a wire; tooltip `Pin to block` / `Unpin from block` / `A bound field stays on the block`). Right-click on a row of a block: `Unpin “<label>” from block`. Right-click on a block: `Fields ▸`, a checklist of every field (a tick pins or unpins and the menu stays open; a bound field is ticked, greyed and marked `bound`).
- **Binding pins.** A field that gets a wire (in or out) is pinned for good: it stays a row after the wire is gone, until the user takes it off (`pinBound`, called by `ConnectPortsAction`, `RebindEdgeAction`, `AddBlockAction` and `PasteBlocksAction`). A bound field cannot be unpinned.
- **Order.** Rows keep the order of the type's fields (§3); a pin does not move a row.
- **Where it is kept.** In the definition's `layout`, with the positions, so it survives deploy and reload and runs nothing (`layout` is outside a node's config; the preview definition has no `layout`). Only the user's choices are written; a field that follows its type's default has no entry, and a flow without pin data draws the defaults.

```
"layout": {
  "scale1": [320, 60],                 // the block's position (spec 06 0.2.5)
  "scale1~pin~p:k": [0, 0],            // field `p:k` taken off the block
  "scale1~pin~p:input_min": [1, 0]     // field `p:input_min` pinned to it
}
```
Key `<node id>~pin~<field id>` (`pinKey`, `pinKeyOf` in `flow_mapper.dart`); value `[1, 0]` pinned, `[0, 0]` off; the second number is not used. Field ids are those of `fieldsOf`: `p:<parameter>`, `in:<port>`, `out:<port>`, `arg:<name>`. A node id is a key segment, so it never holds `~`: no node is named like a pin.

**Why this shape (decided under ADR 0029, open to the owner).** The engine reads `layout` as `{<key>: [x, y]}` of two finite numbers and refuses any other value (`crates/wyrm-flow/src/def.rs`); it does not look at the keys. So this shape deploys on every broker there is today, with no change to the engine. Spec 06 says the key of `layout` is a node id: a pin key is not one. Two ways to make it clean, both a change to spec 06 and the engine: say in spec 06 that `layout` keys with `~` belong to the editor, or give `layout.<node>` a third element (`[x, y, {"pins": […]}]`). The mapper is the only code that knows the shape.

Actions: `SetFieldPinAction(block, field, pinned)`. Goldens: `flow_pins`.

## 13. Selection and clipboard (owner decision 2026-11-09)
"Mass selection of blocks and a context menu for blocks (cut, copy, delete, create custom block, edit custom block)."

**Selection** (`flowEditor.selection`; the inspector shows a block only when exactly one is selected):
- a click on a block selects it alone; Shift- or ⌘/Ctrl-click switches it in or out of the selection;
- a drag on the empty canvas draws a marquee (1 px ember, fill ember 8 %, radius 2): the blocks it touches read selected while it is drawn and are selected when it ends; Shift adds them to the selection, ⌘/Ctrl switches them; a click on the empty canvas clears;
- every selected block has the outline of §3 (1.5 ember + ring), and its wires are drawn over the blocks;
- the header of a selected block moves the whole selection; the block under the pointer lands on the grid and the others keep their places beside it; a click (no drag) on one of several selected blocks selects it alone;
- ⌘/Ctrl+A selects all; Esc clears.

**Panning does not fight the marquee** (as Figma, Miro, draw.io): Space + drag, the middle button, the wheel (Shift: sideways) and two fingers on a trackpad pan.

**Context menu** (`FlowMenu`, the node menu's style: 260 wide, radius 10, title mono + subtitle, items 34 high with the shortcut on the right, coral for Delete; a disabled item says why in its tooltip). The right button opens it on a block (which is selected alone unless it is part of the selection), on the selection, or on the empty canvas:

| Item | On | Does |
|---|---|---|
| `Cut` · `Copy` | ≥ 1 block | the selection to the clipboard (Cut removes it) |
| `Paste` | always | at the pointer |
| `Duplicate` | ≥ 1 block | a copy one grid step down and right |
| `Delete` | ≥ 1 block | the blocks and every wire to or from them |
| `Select all` | always | |
| `Undo` · `Redo` | the empty canvas, nothing selected | disabled with `Nothing to undo` / `Nothing to redo` |
| `Fields ▸` | one block | the checklist of §12 |
| `Unpin “<label>” from block` | a row of one block | §12 |
| `Create custom block…` | ≥ 1 block | **disabled**: `Needs custom blocks in the engine` |
| `Edit custom block` | one block | **disabled**: `Needs custom blocks in the engine` |

The last two wait for sub-flows in the engine (ADR 0040, `docs/studio.md` §10 item 8). What `Create custom block…` needs from the editor is ready and tested: `extractSubflow(draft, ids)` (`flow_canvas.dart`) cuts the selection out as `Subflow {blocks, edges, inputs, outputs}`. An edge with both ends inside stays inside. An edge from outside in becomes an input (one per outside source, so a source that feeds two inside inputs is one input). An edge from inside out becomes an output (one per inside source). A port is named after its inside end: the node for `in`/`out`, else the port without `in.`, with the node in front when two would read alike.

**Clipboard.** `Copy` writes the selection as JSON to the editor's own clipboard (`flowEditor.clipboard`, kept when another flow is opened) AND to the system clipboard, so blocks paste between flows and between windows. The format is a part of a definition (spec 06) under a `format` mark:

```
{
  "format": "wyrm-flow-blocks/1",
  "nodes":  { "<id>": { "type": "…", …config } },
  "edges":  [ ["<id>.<port>", "<id>.<port>"] ],     // only edges among the copied blocks
  "layout": { "<id>": [x, y], "<id>~pin~<field>": [1, 0] }
}
```
`Paste` reads the system clipboard: a text of this format pastes; any other text pastes nothing (a foreign text is never read as blocks, and never falls back to an older copy). Only where there is no system clipboard, or it is empty, the editor's own copy is pasted. Pasted blocks: the top-left corner of their bounding box goes to the pointer (the menu's place; with ⌘/Ctrl+V where the pointer was last on the canvas, else the middle of the view), on the grid; each id is kept when it is free, else it takes the next free number (`scale1` → `scale2`, `tank` → `tank1`); edges among them follow the new ids; edges to blocks outside were not copied; the pasted blocks are selected. A text over 4 MiB is not read.

**Undo and redo.** Every edit of the draft is one step: add, move (a drag of several blocks is one step), delete, paste, bind, unbind, rebind, a parameter, an operand, a form, − / +, a pin. Typing in one field is one step, and so is a run of arrow-key moves (`undoPush` with a tag). The history holds 100 steps (`undoLimit`); a new edit drops what could be redone. Undo brings back blocks, wires, config, positions and pins; the flow's id and version are not part of it (a deploy is not undone), and the selection keeps the blocks that still exist. Opening another flow starts a new history; the same flow read again (a redeploy) keeps it with its draft.

State: `selection`, `undo`, `redo`, `undoTag`, `clipboard`. Actions: `SelectBlocksAction`, `MoveBlocksAction`, `RemoveBlocksAction`, `PasteBlocksAction`, `SetClipboardAction`, `UndoFlowAction`, `RedoFlowAction`. Goldens: `flow_marquee`, `flow_selection_menu`.

## 14. Shortcuts (owner decision 2026-11-09)
"Add an info card for the dataflow with keyboard shortcuts, for intuitive behaviour like in other canvas apps."

**One table** (`flowShortcuts` in `ui/lib/flows/shortcut_card.dart`): the canvas finds the command of a key in it (`flowCommandOf`) and reads the modifiers of its pointer gestures from it (`flowGestureHeld`); the card and the menu's hints print the same rows. A shortcut that is not in the table does not exist. ⌘ is the primary modifier on macOS, Ctrl elsewhere.

| Group | Command | Keys or gesture |
|---|---|---|
| Selection | Select all | ⌘/Ctrl+A |
| | Select with a marquee | drag on the empty canvas |
| | Add to or take from the selection | Shift+click · ⌘/Ctrl+click · Shift+drag on the empty canvas |
| | Move the selection | drag a header |
| | Move by one grid step (20 px) | ← → ↑ ↓ · Shift: 10 steps |
| | Cancel, clear the selection | Esc |
| Editing | Copy · Cut · Paste · Duplicate | ⌘/Ctrl+C · X · V · D |
| | Delete | Delete · Backspace |
| | Undo | ⌘/Ctrl+Z |
| | Redo | Shift+⌘/Ctrl+Z · ⌘/Ctrl+Y |
| | Unbind a field | Alt+click · double click |
| View and flow | Pan | Space+drag · middle button drag · wheel / two fingers |
| | Zoom | ⌘/Ctrl+wheel · pinch (about the pointer) |
| | Zoom in · out | ⌘/Ctrl + `+` · `−` (× 1.2) |
| | Zoom to 100 % | ⌘/Ctrl+0 · `1` |
| | Fit all blocks | Shift+1 (at 100 % at most) |
| | View the value under the pointer | V |
| | Find a block | `/` · ⌘/Ctrl+K (the cursor goes to the palette's search field) |
| | Deploy | ⌘/Ctrl+Enter, which asks first (`Deploy this flow?`) and does nothing while Deploy is off |
| | This card | `?` |

- **Esc**, in this order: closes the card; cancels a drag in progress; closes the value viewer; clears the selection.
- **Zoom** 25 % … 200 %; the canvas stays within 200 px of the view. The canvas pans and zooms its transform itself (the `InteractiveViewer` only holds it), and reads every pointer in canvas coordinates through that transform, so ports, rows, the marquee and a dragged block are right at any zoom and scroll.
- **The card** (`ShortcutCard`): opened by the `?` button beside the legend and by `?`; closed by ×, Esc, `?` or a click beside it. Three groups in two columns; a key is a chip (mono 11 on `#22282D`, border `#2F373D`, radius 4), alternatives are joined by `or`. On macOS the modifiers are the glyphs ⌘ ⌥ ⇧; IBM Plex has neither them nor the arrows, so they are icons of the set (`key_cmd`, `key_alt`, `key_shift`, `key_left`, `key_right`, `key_up`, `key_down`). Elsewhere: `Ctrl`, `Alt`, `Shift`.
- **When keys are off.** The canvas takes keys while its route is on top (not under a dialog or the menu) and the focus is neither in a text field nor in the value viewer. A press on the canvas takes the focus from a text field. Space pans only then, so it still types a space.

Goldens: `flow_shortcuts` (macOS glyphs), `flow_shortcuts_ctrl`. Widget tests: `ui/test/flow_canvas_test.dart`.

## 15. Value viewer editing (owner decision 2026-11-09)
"When viewing a value, if the field can be edited it would be great to be able to save changes from the popup window."

- A field whose value is typed has an `Edit` button in the viewer's title row (beside `Copy`). The body becomes an editor fit for the type, with the hint `Cmd+Enter saves · Esc cancels` (`Ctrl+Enter` off macOS), `Cancel` and `Save` (ember) under it:

| The field | Editor | Checked |
|---|---|---|
| a parameter with choices | a dropdown | |
| a `bool` parameter | a toggle with its word | |
| a `number` / `int` parameter | a number box, mono 20; Enter saves | `Not a number` |
| a `map` / `array` parameter | a multi-line mono editor | `Not a JSON map or list` |
| a text parameter | a multi-line mono editor | |
| an operand's constant, an `invoke` argument, a `dynamic` parameter | a multi-line mono editor; read as JSON when it parses (`2` is a number, `AHU-` a text) | |

- `Save` writes the field in the draft exactly as the inspector's row does: one function for both (`_setField` in the connector: `fieldEditOf` says the kind, `typedText` reads the text, then `SetBlockParamAction` or `SetOperandValueAction`). An empty text removes the value: the field goes back to its default. While the text is wrong, the reason is said under the editor in coral and `Save` is off. `Save` leaves the editor; the window then shows the new value.
- Esc leaves the editor first and closes the window next; `Cancel` is the first Esc.
- A field that cannot be typed has no `Edit`; a line under the value says why: `Read only: a wire feeds this field. Unbind it to type a value.` · `Read only: the block computes this output.` · `Read only: this input holds no typed value. Bind an output to it.` A field that gets a wire while it is edited closes the editor.
- **Explorer points stay read only in this round.** A point is written through staged changes (`docs/studio.md` §5.3 rule 3); staging from the viewer belongs to the Explorer and is not built here.

Goldens: `flow_viewer_edit`, `flow_viewer_locked`. Widget tests: `ui/test/value_viewer_test.dart`.

## 16. Owner's requirements (2026-11-09, fourth review) and what changed
1. "Some fields should be pinnable … and some … can be unpinned — through a context menu or something like it": pins per block, in the inspector, in the row's menu and in `Fields ▸`; saved in `layout` (§12).
2. "If the field can be edited it would be great to be able to save changes from the popup window": the viewer's Edit mode (§15).
3. "Mass selection of blocks and a context menu for blocks (cut, copy, delete, create custom block, edit custom block)": marquee, modifiers, the menu, the clipboard, undo and redo (§13); custom blocks are in the menu, disabled until the engine has sub-flows.
4. "An info card for the dataflow with keyboard shortcuts": the card and its one table (§14).
