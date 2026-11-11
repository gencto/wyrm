# Flow editor

Boards: `FlowBind` (fields, bindings, properties), `FlowTree` (dragging points and actions from the tree). Canvas source: `../canvas/FlowBind.dc.html`, `../canvas/FlowTree.dc.html`. `FlowSymbol` (a block made of blocks) is built as custom blocks (§20, ADR 0040); `FlowRepeat` waits for the engine (`docs/studio.md` §10 item 9). The second wave of owner requirements (2026-11-09): §17 keys from a binding, §18 the Tree tab, §19 the action block, §20 custom blocks; what a broker without ADR 0040 turns off: §21.

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
- Tabs, three equal columns, 40 high: `Blocks` · `My blocks` (§20) · `Tree` (§18). `My blocks` is off, with the reason as its tooltip, only on a broker without custom blocks (§21).
- `Find a block`: height 34, radius 6, fill `#1D2226`.
- Categories (13/600 `#C5CBCE`, chevron) from `node_types` `category`, in a fixed order (`paletteCategories` in `flow_fields.dart`): Sources, Variables, Math, Trigonometry, Statistics, Logic, Text, Codecs, Data, Tables, Date and time, Alarms, Outputs, WASM. A category the engine adds later comes after them, in the catalog's order; within a category the catalog's order stays.
- **Items are one line, 32 high**: indent 24, a tag chip (24 × 16, mono 9/600: `IN` teal on `#15302A`, `OUT` ember on `#2A1F16`, `FX` `#C5CBCE` on `#22282D`; `MY`, `LIB` on the My blocks tab), the name 13 `#C5CBCE`. **A block type reads in words** (`rising_edge` → `Rising edge`, `list_children` → `List children`; `blockLabel` in `flow_fields.dart`); the search also finds the engine's name, which is the tooltip's first word. **No description in the list**: it is the tooltip and the inspector note when the block is placed. Cursor `grab`; drag onto the canvas places a block.

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
A block's input and its value are ONE thing: one row holds the field's value, its binding and what it feeds. Never a row for the value, another for the input and a third for the echo.
- A field `p` = parameter `p` ∪ input `in.<p>` ∪ echo output `p`.
- The main value of a variable block (`number`, `string`, `bool`, `const`: input `in`, parameter `value`, output `out`) is ONE field `Value`: one property, `value`. `const` has no input. A typed editor in the inspector: a number box, a text field, a toggle.
- An operator's operands (`in`, `in.0`, `in.1`, …) are fields with a value and both ports. **The value is typed** (ADR 0038 §7, spec 06 0.2.19, owner review 2026-11-08): typing it writes the node's config `values: {"<port>": <value>}` under the engine port (`concat` `values: {"in.0": "AHU-"}`); a binding replaces it on the row and in the engine, the typed value stays in the config and returns on unbind. Only for a type whose catalog says `values: true`, never for a parameter's port (the parameter's config is its value), `stopwatch.reset` or a variable's `in`. The row shows the bound value that comes in (accent), else the typed value; the inspector a text field, read as JSON when it parses (`2` is a number, `AHU-` a text). A removed variable input takes its constant with it (the engine refuses `values.<port>: not an operand input`). Its result (`out`, `quotient`, …) is a field `Output` with a right port only. `scale`: `in` is `Input`, `out` is `Output`.
- Binding INTO a field is an edge to its engine input (`in.<p>`, or `in` for a variable's `Value`); binding OUT of a field is an edge from its echo or output (`out` for a variable's `Value`, `p` for a parameter). An older edge from a variable's echo `value` or `in` draws on the `Value` row.
- Order: operands, parameters, variable inputs, then the trailing parameters (`if` Then, Else; `concat` Strict; `hub` Ignore null), results.
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

**Binding is drag and drop along a wire (owner decision 2026-11-08):**
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
  - a text with usual values (a time zone, a range text, §23): the text field with a chevron at its end that opens a menu of them; any other text may be typed;
  - a list of maps (`mapping`, `aggregates`, §23): under the label, the inspector's width, a header of the keys, a line per item with a field per key (a dropdown where the key has choices) and a remove button, then `Add a row`;
  - a command (§23): an off button with the field's name, and under it why: a sample on its wire presses it;
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
The palette shows the tree; a point dropped on a field wires a block that reads it into that field (the target row lights with a dashed ember box); dropped on the canvas it becomes a tree-node block. An action dropped on the canvas becomes an `ACT` block whose fields are the action's parameters, with `Trigger` (input) and `Ok`, `Error` (outputs). Point rows: tag (`.0`, `01`, `≡`, `Aa`) + mono name + live value; action rows ember with `ACT` and the number of inputs. As built since 2026-11-09 it is the site's real tree: §18. The action block: §19.

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
- [ ] A wire into `Point` asks the scope on the field; `Scope` and `Error` rows; unbinding keeps the scope (§17)
- [ ] The Tree tab is the live tree with value leaves and action rows; a writable value asks Read or Write; an action becomes the action block (§18)
- [ ] The action block's inspector in groups; `Run` on the deployed flow, off with the reason; `Run on start` asks first (§19)
- [ ] `Create custom block…`, an instance with `Open inside`, the inside with `Back` and the path, the My blocks tab with the library (§20)
- [ ] On a broker without ADR 0040 each of these is off with the reason (§21)
- [ ] Goldens: `flow_key_scope`, `flow_scope_prompt`, `flow_tree_tab`, `flow_action_block`, `flow_action_run`, `flow_custom_instance`, `flow_my_blocks`, `flow_custom_inside`, `flow_custom_dialog`

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
5. Every block checked against WYRM's order rule: operands, parameters, variable inputs, then the trailing parameters, results (`if` Then, Else after the inputs; `concat` Strict after them).

## 12. Pins (owner decision 2026-11-09)
"Some fields should be pinnable for viewing on the canvas, and some are not mandatory and can be unpinned." A block draws only its pinned fields; the inspector always lists every field.

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
| `Create custom block…` | ≥ 1 block | the selection becomes one custom block and one instance of it (§20) |
| `Edit custom block` | one instance of a custom block | opens its inside (§20); on any other block it is off: `Not a custom block` |

The last two are off with the reason on a broker without custom blocks (§21). `Create custom block…` stands on `extractSubflow(draft, ids)` (`flow_canvas.dart`), which cuts the selection out as `Subflow {blocks, edges, inputs, outputs}`. An edge with both ends inside stays inside. An edge from outside in becomes an input (one per outside source, so a source that feeds two inside inputs is one input). An edge from inside out becomes an output (one per inside source). A port is named after its inside end: the node for `in`/`out`, else the port without `in.`, with the node in front when two would read alike.

**Clipboard.** `Copy` writes the selection as JSON to the editor's own clipboard (`flowEditor.clipboard`, kept when another flow is opened) AND to the system clipboard, so blocks paste between flows and between windows. The format is a part of a definition (spec 06) under a `format` mark:

```
{
  "format": "wyrm-flow-blocks/1",
  "nodes":  { "<id>": { "type": "…", …config } },
  "edges":  [ ["<id>.<port>", "<id>.<port>"] ],     // only edges among the copied blocks
  "layout": { "<id>": [x, y], "<id>~pin~<field>": [1, 0] },
  "blocks": { "<name>": { …a custom block's definition } }   // only when an instance is copied (§20)
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
| a table typed into a field that holds one (the `table` variable's Value) | the grid itself edits (§24); `Edit as JSON` opens the multi-line editor | the bounds of a table |

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

## 17. Keys from a binding (owner requirement 2026-11-09, ADR 0040 §1)
"I have a text block that holds a node path and it changes dynamically … I do not know how to bind the path straight into a subscribe block."

- **The key is a field.** `Point` of `subscribe`, `liveliness` and `load_value` (`key`, port `in.key`) and `Node` of `list_children` (`path`, port `in.path`) are rows with a left port: drag a wire into them like into any field. Which parameter is a key, and which one holds its scope, is the catalog's word (`params[].scope`: `key` → `key_scope`; `scopedKeyOf`).
- **The scope is asked in place.** A wire into a key of a block that has no scope opens a small card on that field (`ScopePrompt`, 320 wide, ember border, drawn over the canvas under the row; `flowEditor.scopePrompt` holds the block): `This block may read keys under`, a mono field, chips, a note, `Cancel` and `Save`.
  - The field starts with the suggestion: the block's current key's parent and all below it (`downstream/modbus/line1/level` → `downstream/modbus/line1/**`; `scopeSuggestion`); with no key, or a key right under a section, the section (`downstream/**`).
  - Chips: the suggestion, then the site's three sections (`downstream/**`, `dataflows/**`, `storage/**`). A chip fills the field.
  - It is checked as it is typed, by the engine's own rule (`scopeProblem`): not empty; inside `downstream`, `dataflows` or `storage` of this site, the section written out (no wildcard of it); the other segments key segments, `*` or `**`. While it is refused the reason stands under the field in coral and `Save` is off.
  - `Save` (or Enter) writes `key_scope` (`path_scope`) into the block's config. `Cancel` (or Esc) takes the wire away again: a key from a wire without a scope does not compile (`nodes.<id>.key_scope: required when in.key is wired`), so the editor does not leave one. A block that already has its scope is not asked again; `Cancel` then changes nothing.
- **The `Scope` row.** Once a wire feeds the key, or a scope is written, the block has the row `Scope`: read only there (no ports: a scope feeds nothing), with a pencil (`action_edit`, tooltip `Edit the scope`) that opens the card again. In the inspector it is a text field; a scope the engine would refuse says why under it.
- **`Error`.** A refused key (outside the scope, a pattern, another site) reads nothing and says why on the block's `error` output. `Error` is a row of the block while a wire feeds its key.
- **Unbinding** keeps the scope, and keeps the last key that came in as the typed key (as every parameter keeps its last value, §4).
- **A point of the tree dropped on the canvas** is a `subscribe` with its key and no scope: none is needed until a wire feeds the key. Dropped on a key field, it wires in like any source and the scope is asked.
- **Two steps of the history**: the wire, then the scope.
- **Rights are the broker's.** Whoever deploys, and whoever watches or previews, must read all of the scope; for `list_children` also the children (`<path>/*`, `<scope>/*`; ADR 0040 §4, security review 2026-11-10). The editor does not guess rights: a refusal is the engine's `permission_denied` at validate, preview or deploy, shown with the flow's problems.

Code: `scopeAsked`, `scopeSuggestion`, `scopeProblem`, `scopedKeyOf` (`flow_blocks.dart`); `ConnectPortsAction`, `RebindEdgeAction` and `AddBlockAction` open the prompt; `SetScopePromptAction`. Goldens: `flow_key_scope`, `flow_scope_prompt`.

## 18. Tree tab: the real tree (owner requirement 2026-11-09)
"The list of datapoints in the dataflow is not quite what is needed; take the tree we have in the other menu section, but it does not show nodes with values, so extend it for the dataflow, because some nodes have actions which I would also like to drop into the dataflow as a block that I could fill from other blocks and trigger."

- **One tree, one component.** The Tree tab draws the Explorer's own row (`TreeRow` in `ui/lib/trees/tree_row.dart`, 32 high here) from the Explorer's own state: the same live lists (`nodes.table`, `TreeWatchService`), the same open nodes (`nodes.expanded`: a node opened here is open there). The Explorer's look does not change: the row's additions (`tag`, `value`, `ember`, `drag`) are off unless given. The roots are what a flow may read and write: `downstream`, `dataflows`, `storage`.
- **Extended for the editor:**
  - **A value node is a row**: its type tag (`.0`, `01`, `Aa`, `≡`, `{}`) in place of the kind icon, its name in mono, its live value on the right (the editor subscribes to the children of every open node). A value the flow already uses is tinted.
  - **An open node lists its actions first**: ember `ACT`, the action's name, `<n> in`. They come from the node's own `~meta` (`actions`), read once when the node is first opened in this tab (`RetrieveDetailsAction`, quietly; kept in `nodes.detail`). Never an action of level config: a flow acts at `write` at most (spec 06 step 7).
  - **Every node opens** until its list answered empty and it has no action: a node may hold only values, which the Explorer shows in its table and this tree as leaves.
  - The compact row indents 12 per level; a leaf stands where its parent's icon does.
- **The filter** (`Find a point or action`) keeps the rows whose name holds the text, the actions whose name holds it, and the nodes above them, opened (`flowEditor.treeQuery`).
- **Dragging.**

| Dragged | Onto | Gives |
|---|---|---|
| a value | the canvas | a `subscribe` block of that point |
| a value that may be written | the canvas | a small menu where it landed: `Read` (`subscribe`) · `Write` (`set`); with Alt held, `Write` at once |
| a value | a field with a left port | a new `subscribe` wired into that field (onto a key field: the scope is asked, §17) |
| an action | the canvas | the action block (§19): `invoke` with `path`, `action`, and one argument per parameter of the action with its default; required arguments are rows of the block, the others stay in the inspector |

  A tap on a value or an action adds it at a free place, as a tap on a block type does; a tap on a node opens or closes it.
- **The two notes** under the tree say what a drop does.

Code: `_treeRows` in the connector; `blockOfEntry` (`flow_blocks.dart`) maps `key:<point>`, `set:<point>`, `act:<node>/<action>` to a block. Goldens: `flow_tree_tab`.

## 19. The action block (owner requirement 2026-11-09, ADR 0040 §2)
"The trigger block and the deploy-run block are in essence one block, only their behaviour differs."

- **One block.** `invoke` is the action block; there is no trigger block, no button block, no run-on-deploy block. Its header reads `ACT · <id> · <node> · <action>`.
- **On the block by default**: the required arguments, `Trigger`, `Ok`, `Error`. A behaviour that is set (`Every`, `Run on start`, …) becomes a row too, and so does anything wired. The older `in` (`Run when`) and `out` stay in the inspector: a definition that wires them still shows them.
- **The inspector lists its fields in groups** (11/600 uppercase headings; `groupOf`):

| Group | Fields | Editors |
|---|---|---|
| Target | `Node` (`path`), `Action` | text; static (ADR 0040 §1a: a command target takes no wire) |
| Arguments | one per key of `args`, then the action's parameters that have no key yet | as the action's `~meta` types it: choices → a dropdown, bool → a toggle, number, text; or a binding through `arg.<name>`. Typing a value or binding adds the key; emptying an optional one takes it out of the call |
| Behaviour | `Trigger` · `Run when` · `Auto run` · `Every` · `Enabled` · `Run on start` · `Run on` · `Allow bad quality` | `Trigger` bound: the binding. Unbound: the button `Run`. `Every`: a number and its unit (ms, s, min, h; written as `interval_ms`). `Run on start`: a toggle that asks first (`Run on every start?`) with the catalog's own `WARNING:` text |
| Events | `Sent` · `Ok` · `Error` | outputs to wire on; each reads when it last fired (`14:03:27`), `Error` also its code and message (`busy: queue full`) |
| State | `Output` (`out`) · `Result` · `Running` · `Last run` | read only; `Result` opens in the value viewer |

- **`Run`** calls the engine's `dataflows/<id>` ▸ `trigger {node}` on the DEPLOYED flow (`TriggerBlockAction`; inside a custom block the node is `<instance>/<inner>`). It is off, with the reason under the button, when: the broker has no trigger action; the flow is not deployed; the draft differs from the deployed version (`Deploy first: Run acts on the deployed version…`; so also during a preview); the block is disabled; the user lacks `write` on the flow. A refusal of the broker is said in words: `permission_denied` (which carries no text) → `You may not run it: this needs write on the flow and on what the block acts on`; `not_supported` → `The flow is not running`.
- **The same groups** for `set`, `load_value` and `list_children`, where the catalog gives them the fields (`behavesOf`: a `trigger` input and the event outputs). A `set` stays its point on the canvas (one row); `load_value` and `list_children` show their key, `Trigger`, `Error` and `Output`. The readers have no `Run`: the engine's trigger action is for commands.
- **In a preview** the block's trigger row reads `would send …` in the ghost colour, with the `preview` chip: what it would send, nothing is sent (the engine reports `sinks` and `sent` only).
- A wire into `Trigger`, an argument or a behaviour carries no `fires at deploy` chip: only `in` acts on a value sent at start (ADR 0040 §2, the start rule).

Goldens: `flow_action_block`, `flow_action_run`.

## 20. Custom blocks (owner requirement 2026-11-09, ADR 0040 §3)
"We cannot create custom blocks; I see the tab, but…"

- **Create.** `Create custom block…` (the menu of a selection) opens a dialog: `Name` (a free `block<n>` proposed), `Description`, then the ports the selection has — one input per outside source that feeds it, one output per inside field that feeds a block outside (`extractSubflow`) — each with its name in a field and what it is wired to beside it (`← a.out`, `→ mean.in`); an input also has a `default`. Names are `[A-Za-z0-9_]+`, unique among inputs and outputs together, the block's name free in this flow; what is wrong is said in coral and `Create` is off. `Create` replaces the selection by ONE instance (`<name>1`, at the selection's top-left), its wires re-routed to the instance's ports; the definition goes into the flow's `blocks`. One step of the history.
- **An instance** draws like a block: the chip `MY` (ember), its id, the block's name on the right; one row per declared input (both ports: a value or a binding; its constant is the instance's `values.<input>`, else the block's `default`) and per declared output; the last row `Open inside`. Live values come from the inner nodes: an input reads the inner input its `to[0]` names, an output the inner output `from`, under `<instance>/<inner>` in the rows of `watch` and `preview`.
- **Edit.** `Edit custom block` (an instance's menu), `Open inside` (its row, the inspector's button) and `Edit custom block` of a My blocks entry show the block's INSIDE on the same canvas:
  - the path reads `Flows › <flow> › <block>` (each part a link back to its level) with `Back` before it; after it: `<n> instances in this flow · a change here changes them all`;
  - two blocks stand for the boundary: `Inputs` (one right port per declared input; its inspector types each input's default; − / + take or add one, `in1`, `in2`, …) and `Outputs` (one left port per declared output; − / +). A wire from `Inputs.<a>` to an inner field is the input's `to` (it may feed several); a wire from an inner output into `Outputs.<x>` is the output's `from`. They are not copied, cut or deleted;
  - every tool of the canvas works there, with a history of its own; opened from an instance, the inner blocks show that instance's live values;
  - `Validate` and the preview always read the whole flow; `Deploy` is off (`Go back to the flow to deploy`);
  - `Back` (or a part of the path) writes what was drawn as the block's definition, for every instance in this flow; an instance loses the wires and constants of a port the block no longer has. In the flow's history this is one step, and only when something changed.
  A block opens inside itself never, and at most four deep (the engine's limits).
- **My blocks** (the palette's second tab):

| Group | Entries | Drag or tap | Menu |
|---|---|---|---|
| `This flow` | the flow's `blocks`: `MY`, the name, `<n> used` (or `library v<n>` when the library holds another version) | places an instance (not of the block whose inside is open: `A block cannot contain itself`) | `Edit custom block` · `Save to library` (`put_block`; needs config on `dataflows`) · `Rename` (the definition and every instance) · `Update from library` (only when the library's version is not the copied one) · `Delete` (only when no instance is left: `<n> instances use it`) |
| `Site library` | `list_blocks`: `LIB`, the name, `v<n>` | COPIES the block into this flow with the blocks it uses (`get_block`: `def` and `requires`), then places an instance; one step of the history | `Delete from library` (`remove_block`; needs config) |

  A flow copies, it does not link (ADR 0040 §3): a block of the flow with the name of a library block is the flow's own until `Update from library` replaces it. `Save to library` sends the blocks it uses first, when the library does not hold them. The library version a block was copied at is kept as an editor key of the block's `layout` (`_~lib~version: [n, 0]`; spec 06 0.2.26: the engine reads none of `layout`).
- **Clipboard.** A copied instance carries its block's definition, and the definitions that one uses (`blocks` in `wyrm-flow-blocks/1`, §13). Pasted into another flow, the definitions come along; where that flow has a block of the same name, its own stays.
- **Limits** are the engine's (64 blocks, 64 inputs and 64 outputs, depth 4, 1000 nodes, 4000 edges); beyond the dialog's checks they are said by `Validate`.

State: `frames` (a `FlowFrame` per open inside: the draft above, the block, the instance, its history), `library`, `libraryOff`. Selectors: `root` (the flow with every inside folded back), `allTypes` (the catalog with one type per custom block), `caps`. Actions: `CreateCustomBlockAction`, `EnterBlockAction`, `LeaveBlockAction`, `ResizeBlockPortsAction`, `RenameCustomBlockAction`, `RemoveCustomBlockAction`, `RetrieveBlockLibraryAction`, `PlaceLibraryBlockAction`, `SaveBlockToLibraryAction`, `UpdateBlockFromLibraryAction`, `RemoveLibraryBlockAction`. Pure code: `flow_blocks.dart`. Goldens: `flow_custom_dialog`, `flow_custom_instance`, `flow_my_blocks`, `flow_custom_inside`.

**Not built (said, not hidden):** renaming a port of an existing block (take it away and add one); "update every flow that copied a library block" (each flow updates its own copy).

## 21. A broker without ADR 0040
The editor reads what the broker can do; it assumes nothing (`FlowCaps`, `flowCapsOf`).

| Read from | Missing | What the editor does |
|---|---|---|
| a catalog parameter with `scope` | keys from a port | `Point` has no left port; a wire dragged onto it is refused: `This broker cannot bind Point (its flow engine is older than ADR 0040)` |
| a catalog type with `trigger: true` | the trigger action | the action block has the older shape (`Run when`, `Result`); a `Trigger` field, where one exists, has `Run` off: `This broker has no trigger action…` |
| `dyn_inputs.keys` of `invoke` | argument ports | an action dropped from the tree keeps the older definition (`on: rising`, only arguments with a default); arguments are typed, not bound |
| `list_blocks` answering | custom blocks | `My blocks` is off with the reason; `Create custom block…` and `Edit custom block` are off: `This broker has no custom blocks…`; a definition that has `blocks` still draws |

The Tree tab needs nothing new: it works on every broker.

## 22. Owner's requirements (2026-11-09, fifth review) and what changed
1. "Bind the path straight into a subscribe block": the key is a field with a left port; its scope is asked on the field and shown as a row (§17).
2. "Take the tree we have in the other menu section … extend it for the dataflow": the Tree tab is the Explorer's tree with value leaves and action rows; values and actions are dragged into the flow (§18).
3. "The trigger block and the deploy-run block are in essence one block": one action block, its behaviours as fields in groups, `Run` on the deployed flow (§19).
4. "We cannot create custom blocks": create from a selection, open and edit the inside, the My blocks tab with the site's library (§20).
5. The blocks of ADR 0040 §4 are in the palette in words, with their fields (`docs/flow-blocks.md`).

## 23. The third set of blocks (ADR 0044, spec 06 0.2.29)
The catalog has 125 types; the editor draws them from it. What the editor adds for them (`flow_fields.dart`, `table_value.dart`; the rows of each block are in `docs/flow-blocks.md`, "How the editor shows each block"):
- **Labels**: a parameter's `display` from the catalog is the row's label (`atan` `x` → `X`). A block's name follows the broker's rule (ADR 0042: `json_parse` → `JSON parse`). `get_node` names its key `Node`, `date_range` its `range_delimiter` `Delimiter`, `constant` its output `Value`.
- **`router`**: a case and what it routes are one field: `Case 1` ⇄ is `in.0` on the left (its value typed into `values`) and `out.0` on the right; a named case reads its name. − / + adds a case with its output and removes both with every wire into or out of them. `Single output` stands after the cases, then `Else`.
- **Readers** (`load_value`, `list_children`, `load_history`, `get_node`): an unbound `Trigger` is `Run` (§19). A refusal shows the broker's words as they came (`w (downstream of h): …: the caller does not hold write on it`: a trigger needs the rights of every `set` and `invoke` after the block too); Studio adds its own sentence only when the broker sent none. `load_history` shows its query (`Time range`, `Rollup`, `Window`) on the block, `Limit` and `Time zone` in the inspector.
- **Commands**: `date_range` `next`, `previous` and `table_page` `next`, `previous`, `first`, `last` are inputs that a sample presses. On the block each is a button (`▸ Next`) with its left port and no value; it feeds nothing (an older wire out of its echo still draws). In the inspector it is an off button with the reason: the engine has no call that presses an input of a running flow, so a wire does (a timer, a change, a point). It holds no typed constant.
- **Tables**: a value `{columns, rows}` (rows by name or by position) opens in the value viewer as a table window (§24): every row in a grid, `N rows · M columns` above it, Copy CSV and Copy JSON. A list of maps is a table only in a field that holds one (the table inputs and outputs of the Tables blocks, `list_children` and `load_history` `out`, `get_node` `actions`); elsewhere, and in the Explorer, a list stays a tree. A time column `t` reads as dates.
- **Lists of maps**: `table_map_columns` `mapping` (`name`, `from`) and the `aggregates` of `table_group_by` and `table_rollup` (`column`, `method` a dropdown of the engine's methods, `as`) are edited as rows (§6); the field writes the list.
- **Dates**: a date of the engine is microseconds since the epoch (ADR 0044 §3). `now` `out`, `date_time` `out`, `date_parse` `in` and `time`, `date_format` `in`, `date_math` `in` and `out`, `date_range` `start` and `end` show a whole number as the local date and time of this computer (`2026-11-11 12:29:03`); the viewer adds the instant in UTC and the number. `date_range` `duration` is a length, not a date. The `time_zone` of the date blocks, `load_history` and `table_rollup` is a text with a menu of zones (`UTC`, the IANA names of the main regions, `+02:00`; `date_format` also `auto`): any other IANA name or offset is typed, and the engine checks it. A range text (`date_range` `in`, `load_history` `time_range`) is a text with a menu of the named ranges (`today`, `thisWeek`, `current24hours`, `previous7days`, …); `2026-10` or `<a>/<b>` is typed.
- **Order**: `router` `single_output` and `table_recorder` `enabled`, `buffer_size`, `time_window_s`, `ignore_null` stand after the variable inputs (`tailParams`); `table_filter`, `table_remove_rows`, `table_edit_rows` keep `Expression` in the inspector.
- An older broker keeps its catalog's shape: no new section, no `display`, the readers of ADR 0040 as before. Tests: `business/test/flow_third_set_test.dart` on the catalog of 125 types (`business/test/support/catalog_0229.dart`, dumped from `wyrm_flow::catalog::value()`), the older fixtures for the older brokers.

## 24. The table window and lines that do not fit (owner request 2026-11-11)
"For table data also make a data viewer window like the one for text, but in the form of a table; and if the table is editable, let me edit the cells." And a finding: a two-line CSV typed into `table_from_csv`'s Input showed its first line only, with no sign of the rest.

**The table window** (`ui/lib/tables/table_grid.dart` in `ui/lib/overlays/value_viewer.dart`). Any table value (`{columns, rows}`, or a list of maps in a field that holds a table, §23) opens as a grid in the viewer's window (same chrome, place and resize; a first size of 640 × 440):

- Above the grid: a filter over the rows (a cell's text contains it, any case) and the counts: `40 rows · 6 columns`, or `3 of 40 rows` while it filters.
- The grid: a sticky header of the column names, the row number in a gutter (the row's place in the table, also when filtered), horizontal and vertical scrollbars. Only the rows in view are built (fixed rows of 26), so 10 000 rows scroll as ten.
- Cells by type, mono 12: a number right-aligned; `null` dimmed; a bool in amber; a map or a list as compact JSON in grey with the whole of it, indented, in a tooltip; a text of several lines as its first line and `↲ +N`; a date of the time column `t` as the local date and time (the app's `tableCellText`).
- A column is as wide as its header or the widest of its first 500 cells, within 56–320; its header's right edge drags it (40–800).
- The title row: `Copy CSV` (a comma and a header, as `table_to_csv` writes it) and `Copy JSON` (`{columns, rows}`). The type chip says `table`; the counts are above the grid.

**Editing.** A table the user types (the `table` variable's Value; a table typed into a table input or parameter: `holdsTable` and a field typed as JSON or as any value) edits in its grid. It starts from what the config holds, not from the live value; an empty one starts with no columns (`No columns yet. Add one with Add column.`), except `table_from_json`'s Input, which takes a JSON text.

| Key or gesture | What it does |
|---|---|
| a click | selects a cell |
| arrows, Tab, Shift+Tab | move the selection |
| a double click, Enter, F2, a typed character | edit the cell in place (a character starts the text with it) |
| Enter · Tab · Shift+Tab · ↑ · ↓ in the editor | keep the edit and move down · right · left · up · down |
| Esc in the editor | drops the edit |
| Delete, Backspace | empties the cell: `null` (in a CSV tab: an empty text) |
| a double click on a header | renames the column |
| `Add row`, `Add column` | add after the selected row or column (at the end without one); a new column is named at once (`column_<n>`) |
| the `⋯` menu | Rename column, Remove row, Remove column (of the selection) |

- **A cell keeps its type**: a number stays a number when the text reads as one, else it becomes a text; a bool stays a bool for `true`/`false`; a map or a list stays one when the text is its JSON; an empty cell takes a number or a bool when the text is one, else the text; an empty text leaves an empty cell `null`. Cells of the CSV tab stay texts (the block makes texts).
- **Bounds (ADR 0044 §2)** are checked before an edit is kept: at most 10 000 rows, 128 columns, a column name of 1 to 256 bytes and unique, 512 KiB of cells counted as the engine counts them (null and bool 1, number 9, text its bytes + 3, lists and maps their items + 3). A refused edit says why in coral above the grid and changes nothing.
- The first change brings `Discard` and `Save` under the grid with `Cmd+Enter saves · Esc discards the changes` (`Ctrl+Enter` off macOS). Esc drops a cell's edit first, then the changes, then closes the window. `Save` writes the table as `{columns, rows}` JSON (each row a map of every column, as the engine's `Table::to_value`) through the same path as the JSON editor (§15): one undo step, the draft changes, the preview runs again. A table typed as a list of maps, or with rows by position, is written in that one form.
- `Edit as JSON` opens the same table in the multi-line JSON editor (off while the grid has changes).
- **Read only**: a table that arrives on a wire or is a block's output (and every table in the Explorer) has no edit controls; the note under it says why, as §15.

**A CSV text as a table.** The viewer of `table_from_csv`'s Input has two tabs, `Text` and `As table`. `As table` reads the text by the engine's own rules (`business/lib/wyrm/mappers/csv_table.dart`, a mirror of `parse_csv` in `crates/wyrm-flow/src/blocks/tables.rs`: a quoted field is the text between its first and last quote, `""` a quote when it had more than two; every line ended by a break is a row; the last one only with a field; with a header, an empty name is `v<n>` and a name seen before gets `_2`, `_3`, …; without one the columns are `v1`, `v2`, …), with the block's `delimiter` (its first character) and `with_header`. A line above the grid says the rules; when a wire feeds either, it uses the value that came last and says so. A text the block refuses says `parse_error`. When the Input is typed, the grid edits and `Save` writes the table back as CSV (`write_csv`: a field with a quote, the delimiter or a line break is quoted). Read and written again, the text may change its form (quotes, the names made unique), not its table.

**Lines that do not fit** (`ui/lib/indicators/lines_text.dart`). A single-line value that holds several lines shows its first line, then a small mark `↲ +N` (the count of the lines after it; the font has no `⏎`); the whole text (at most 20 lines and 2 000 characters) is the mark's tooltip, and a click on the mark opens the viewer. In a cell narrower than 120 the mark is `+N` alone, and a bound inspector cell of several lines drops its `bound` word (its frame's colour says it), so the first line keeps room. A cut line without a break keeps its ellipsis and shows the whole of it in a tooltip (no mark). While the grid of the "As table" tab has changes, the `Text` tab is off until they are saved or dropped. Where: the value of a block's row on the canvas, the inspector's bound, output and sample cells, the Explorer's point value. The inspector's text editor of such a value already grows to its lines (up to six, then it scrolls); a form's one-line text field whose value has several lines becomes a multi-line field, so the lines are kept.

Goldens: `flow_viewer_table` (dark), `flow_viewer_table_light`, `flow_viewer_table_edit` (a cell in its editor, a change to save), `flow_lines_mark`. Tests: `ui/test/table_viewer_test.dart` (10 000 rows build and only the rows in view are built; a cell edit keeps its type and Save writes JSON; Esc order; rows and columns; bounds; a wired table is read only; the CSV tab round trip; the mark), `business/test/csv_table_test.dart` (the engine's CSV cases), `app/test/value_viewer_test.dart` (one grid per value; a saved grid is the field's value).
