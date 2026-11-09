# Explorer

Boards: `Main` (device selected, a point selected, review drawer), `Actions` (node menu and action groups), `ActionDetail` (one action), `PropertySheet`. Canvas source: `../canvas/Main.dc.html` and the others named.

## 1. Regions (1440 wide)

| Region | Size | Background | Border |
|---|---|---|---|
| Top bar | min height 56, padding 8 × 16, gap 12/20, wraps; on the desktop it is the window's title bar (below) | `#0E1113` | bottom `#252B30` |
| Rail | 76 | `#13171A` | right `#252B30` |
| Tree | flex 1 1 260, max 300 | `#13171A` | right `#252B30` |
| Workspace | flex 999 1 560 | `#0E1113` | — |
| Inspector | flex 1 1 320, max 360 | `#13171A` | left `#252B30` |

**Side panels are resizable (proposed; the boards are fixed).** Drag the inner border of the tree or the inspector to change its width: tree 200–520 (default 260, 240 below 1100 wide), inspector 280–640 (default 320); the workspace never gets less than 480, so on a narrow window both panels shrink to their minimum first. The 8 px handle shows the `col-resize` cursor and turns its 1 px border ember on hover, drag or focus; a double click restores the default; with the handle focused, ← and → move the border by 16 px. Each viewer's widths are kept across restarts (`SidePanels`, `docs/studio.md` §6.5).

Top bar, left to right: logo (mark + `WYRM` Unbounded 700 16, letter-spacing 0.08 em + `Studio` 14 `#A3ABAF`) · site switcher (height 40, radius 8, border `#2F373D`, fill `#161A1D`: status dot 8, site name mono 14, **route** `via edge · central` 12 `#8E979C`, chevron) · search (flex 1 1 280, max 520, height 40, placeholder `Go to a node, action or link`, `⌘K` key cap) · right: **Review and apply** (ember filled, count badge 22 high on `#0E1113`, count text `#F3A766`; disabled outline when 0) · account avatar 40 round.

**Owner decision 2026-11-09: no window frame on the desktop** (`docs/studio.md` §7.1; the boards draw none either). The top bar is the window's drag area; a double click on its empty space maximizes or restores. macOS: the native close, minimize and zoom buttons stay at the left and the logo starts at 92 instead of 16 (16 again in full screen). Windows and Linux: minimize, maximize / restore and close (46 × 32 each, icons 16) sit in the window's top right corner over the bar, and the bar's content ends 138 from the right edge; the Review drawer starts 32 lower, under them. The smallest window is 1180 × 680, so the inspector is always there on the desktop.

## 2. Tree
- Header: `TREE · <SITE>` (12, 600, uppercase, 0.06 em, `#8E979C`).
- **Filter field** under it: height 36, radius 6, fill `#1D2226`, border `#252B30`, search icon, placeholder `Filter`. Filters the loaded nodes by name; matches keep their ancestors open.
- Rows: height 40 (32 compact), radius 6, indent 10 + 16 × depth; chevron 14 (rotates 90° open); kind icon 16 (`node_*` icons: folder, link, conn, device, flow, lock); name **IBM Plex Mono 13**, 400 (600 when selected); then optional chip (run mode: 11, padding 2 × 6, radius 4, fill `#22282D`, ink `#A3ABAF`), optional meta (count or `draft`, 12, `#8E979C`), optional status dot 8 (teal connected, amber connecting/quarantine, coral failed).
- Selected row: fill `#2A1F16`, icon ember; on the selected row a `⋯` button (32 × 32, fill `#3A2A1C`, ink `#F3A766`) opens the node menu (§5).
- Footer (12, `#8E979C`, top border): `The tree shows data only.` `sys/**` `is edited in` Links, Access, Sites `and` System, the four as links to those workspaces.

## 3. Workspace for a device (other kinds: §3a)
1. **Key line**: the full key in mono 13 `#8E979C`, last segment `#ECE9E1`, then a **Copy key** icon button 28 × 28 (copies the full key, §6).
2. **Title row**: the node's **name** (last key segment) in mono 26/600, never its display name, a status pill (24 high, radius 12, `Connected` teal on `#15302A`; `Connecting` amber, `Failed` coral, `Stopped` grey), and under it one subtitle line 14 `#A3ABAF`: `<kind> · unit <n> · <host>:<port> · last read <hh:mm:ss>` (from the node's `~meta` and its connection), then the display name. Name and subtitle are one line each with an ellipsis and the full text as a tooltip: a display name can be a sentence, a segment 50 characters. Right side: **Ping** (outline 40) and **Actions ▾** (outline 40, opens the action menu, §5).
3. **Tabs** (44 high, current one with a 2 px ember underline): `Points 9` · `Parameters` · `Actions 7` · `History` · `Audit`. A count is plain 12 `#A3ABAF` text after the label, not a pill.
4. **Toolbar** (padding 16 × 24, gap 8): `Add point` (outline, fill `#161A1D`), `Import CSV or DSA tree`, `Apply profile` (quiet outline), and on the right `Filter points` (240 wide, height 40). Buttons are the device's own actions; a button whose action the user's level does not allow is disabled with the reason as a tooltip.
5. **Points table** (border `#252B30`, radius 10, fill `#13171A`, horizontal scroll under 860):

| Column | Width | Content |
|---|---|---|
| select | 44 | checkbox 16, ember when checked |
| Point | 1.5fr | staged dot (6, ember) when edited · name mono 13 `#ECE9E1` · display name 13 `#8E979C`, ellipsis |
| Register | 1.1fr | mono 13 `#C5CBCE` (`HR 40003`, `Coil 00001`, `IR 30001`) |
| Type | 0.9fr | mono 13 `#A3ABAF` (`float32`, `bool`) |
| Unit | 0.6fr | `°C` or `—` |
| Poll | 0.9fr | `1 s`; when staged: ember 600 and `was 1 s` (12) under it |
| Value | 0.9fr | mono 13, **without** the unit |
| Quality | 1fr | ring dot 7 + word: good teal filled, uncertain amber ring, bad coral filled, `not applied` grey ring |
| Write | 0.5fr | `RW` `#ECE9E1` or `R` `#8E979C` |

   Header row 40, 12/600 uppercase 0.04 em `#8E979C`. Rows 40 (32 compact), bottom border `#1D2226`; selected row fill `#1D2226`; staged row fill `#191714`. Under the table: `Values update live. Edits are staged in this session; nothing is written to the device until you apply.` (13 `#8E979C`). **No Time column**: the time of the selected point is in the inspector.

   Rows are the device's **points** only. Its diagnostic values (`status`, `error`, `requests`, `errors`, `timeouts`, `exceptions`, `reopens`, `last_rtt_ms`, `avg_rtt_ms`) are not points: `status` drives the pill, `last read` the subtitle, and the counters are a **Diagnostics** section in the inspector when nothing is selected **(proposed)**.

## 3a. Frames by node kind (proposed)
The node's kind picks the frame. It comes from its place, its profile (`is`) and its actions, in this order (`business/lib/wyrm/kinds.dart`, `nodeKindOf`; it agrees with the tree icon):

| Kind | Rule | Pill | Subtitle | Header buttons | Tabs |
|---|---|---|---|---|---|
| folder | a section (`downstream`, `dataflows`, `storage`, `upstream`), a plain node | — | `folder · <n> children · <display>` | Actions ▾ | Contents · Parameters · Actions · History · Audit |
| flow | `wy:flow`, or `dataflows/<f>` | `~val` state: `v2 deployed` teal, `v2 stopped` grey, `v2 · error` coral, `not deployed` | `dataflow · deployed by <who> · <error> · <display>` | **Edit dataflow** (opens the flow editor route; needs read), Actions ▾ | Parameters (a **State** section from `~val`: state, version, deployed by, since, error; then attributes) · Actions · Audit |
| broker | `wy:broker`, or `upstream/<u>` | `connected` child: Connected / Offline | `broker · <attr.root> · <n> children · <display>` | Actions ▾ | Contents · Parameters · Actions · History · Audit |
| link | `wy:link`, or `downstream/<l>` | the link's `sys/links/<id>/state` | `<driver> link · <display>` | Actions ▾ | Contents · Parameters · Actions · History · Audit |
| storage | anything under `storage/` | — | `storage · <n> children · <display>` | Actions ▾ | Contents · Parameters · Actions · History · Audit |
| connection | profile holds `conn` | its `status` | `<driver> connection · <host>:<port> · <display>` | Actions ▾ | Contents · Parameters · Actions · History · Audit |
| device | profile holds `device`, a `<vendor>:<model>` profile, or the node has `add_point` (a modbus folder under a device too) | its `status` | as §3.2 | Ping, Actions ▾ | Points · Parameters · Actions · History · Audit (§3) |

- **Only a device** gets Points, Ping, Add point, Import CSV or DSA tree and Apply profile (§3.3–3.5).
- **Contents**: a table of the node's children (columns Name: mono name with the display name under it · Kind: a node's kind word, or a value's type and `RW` · Value: with its unit, `—` for a node). Selecting a node row opens it in the tree; selecting a value shows it in the point inspector (§4). A link's or a connection's diagnostic values (`status`, counters) are not rows: `status` drives the pill, the counters are in the inspector's Diagnostics.
- A tab kept from the node before stays when the next node has it; else the frame's first tab shows.
- Inspector with nothing selected: label = the kind (`Folder`, `Dataflow`, `Broker`, `Link`, `Storage`, `Connection`, `Device`), title = the name; a flow shows its State section; a Parameters section only when the node has `edit` or `cfg`.

## 4. Inspector
- **A point selected**: label `POINT`; name mono 18/600 + display name `#A3ABAF`; value mono 22 with unit, one line with an ellipsis; quality · time (12); the view button (`ui_view`) opens the value whole in the value viewer (`docs/studio.md` §6.8). Sections (12/600 uppercase): **Register** (Area, Address, Data type, Word order: 2 columns, fields 36 high), **Value** (Unit, Scale, Precision: 3 columns), **Polling** (segmented 250 ms · 500 ms · 1 s · 5 s; `staged · was 1 s` in ember on the right), **Write** (`Writable` switch, `Turning this on needs config level`), **What the tree will publish** (the `~meta` and `~val` it produces, mono 12, on `#0E1113`). Every field is built from the point's `~meta.cfg` with `param_form` and stages its change (§7).
- **Nothing selected** (proposed): label `DEVICE`, the device's parameters as the same form (from `cfg`), then Diagnostics (counters, last RTT). Not a raw key/value dump of `~meta`.
- No close button: the inspector is part of the layout.

## 5. Menus
- Node menu (tree `⋯`, right-click, long press; also **Actions ▾**): width 300, radius 10, fill `#1A1F23`, border `#3A4249`, shadow; items 38 high grouped under headers from the action `group`, label + level hint (`config`, `write`, `read`) on the right, danger items `#F0A28D`; an item with parameters ends in `…` and opens the action form (board `ActionDetail`). Footer row: `Copy key` with `⌘⇧C`.
- The action groups and order come from `~meta.actions` (`group`, `display`); the menu never hard-codes them.

## 6. Selection, multi-select, copy (proposed where the board is silent)
- Points table: click a row selects it (inspector shows it); the checkbox toggles it into the selection without moving the inspector; ⌘/Ctrl-click toggles; Shift-click selects the range; the header checkbox selects every row that passes the filter; Esc clears.
- With 2 or more checked, a selection bar replaces the toolbar: `<n> selected` · `Copy keys` · `Set poll…` · `Record in history…` · `Remove…` (each only when the user's level allows it) · `Clear`.
- Tree: single selection; ⌘/Ctrl-click and Shift-click add rows to a selection for `Copy keys` only.
- Copy: **Copy key** (button by the key line, menu footer, `⌘⇧C`) copies the full key `wy/<site>/downstream/…` of the current node; with several rows checked, `Copy keys` copies one key per line. A toast `Key copied` / `3 keys copied` for 2 s. Plain `⌘C` copies the selected cell's text.

## 7. Staging and review
Edits to points (poll, register, unit, writable, add, remove) are staged in the session, not sent. `Review and apply <n>` opens the drawer (width min(500, 100 %), scrim `rgba(5,7,8,0.66)`): title `<n> staged changes`, `Site <site> · applied with your rights: <user>, <role> (<level>)`, one card per change (op chip, key, `field from → to`, the level it needs and whether the user has it), and the footer `Each write is checked by the link and recorded in sys/audit/<link>. A value shows only after it is read back.` with `Apply <k> changes` and, when some need a higher level, `Ask an admin for <m>`.

## 8. States
Loading (tree rows as skeletons, table header with 6 skeleton rows) · empty device (`No points yet` + `Add point`, `Import CSV or DSA tree`) · offline (banner under the top bar, values greyed, quality `stale`) · no rights for an action (disabled with the reason) · action error (`{code, message}` under the form, verbatim).

## 9. Checklist
- [x] Site switcher shows the site and its route (`via edge · central`)
- [x] Filter field in the tree
- [x] Tree names in mono 13; chips, counts, dots as §2
- [x] Key line with Copy key; last segment highlighted
- [x] Status pill and subtitle line; Ping and Actions ▾
- [x] Tabs: Points, Parameters, Actions, History, Audit; counts as plain text
- [x] Toolbar: Add point, Import CSV or DSA tree, Apply profile, Filter points
- [x] Table columns exactly: select, Point (+ display name), Register, Type, Unit, Poll, Value, Quality, Write; no Time
- [x] Row height 40; staged marks; selected fill
- [x] Diagnostics out of the points table
- [~] Point inspector with the five sections; device inspector when nothing is selected — Word order is read-only, derived from the `dtype` suffix; Precision is disabled (the modbus driver has no such parameter)
- [~] Multi-select, selection bar, Copy key / Copy keys, ⌘⇧C — plain ⌘C copies the selected point's value (the table has no cell selection)
- [x] Review drawer as §7
- [x] Goldens: device with a point selected, nothing selected, review drawer open, empty device, offline
- [x] Frames by node kind (§3a): the device frame only for devices; a flow with its state and Edit dataflow; Contents for the rest. Goldens: a flow selected, a folder selected
- [x] Long names (§3.2): name and subtitle one line with an ellipsis and a tooltip; the node menu header, inspector title, tree names, table cells and key line end in an ellipsis. Golden: a long name and display name at 1100; widget test at 1440, 1100, 900 and 760

## 10. Found in the app (screenshot 2026-11-08)
1. Site switcher shows `edge` only; the route is missing.
2. Tree has no Filter field; the footer text differs (`Right-click a node…`); keep the board's text and links.
3. Key line has no Copy key button and does not highlight the last segment.
4. Title row lacks the status pill, the subtitle, Ping and Actions ▾.
5. Tabs lack Audit; counts are pills.
6. The toolbar row is missing (Add point, Import, Apply profile, Filter points).
7. Table has Point, Type, Value, Quality, Time, Write: no select column, no Register, Unit, Poll; units are glued to values; a Time column the board does not have; rows are ~56 high instead of 40; names are bold sans instead of mono with a display name.
8. Device diagnostics (`status`, `requests`, `errors`, …) are listed as points.
9. The inspector shows a raw `NODE` dump (`key`, `is`, `Actions`, `CFG`) with a close button instead of the point/device inspector.
10. No multi-select and no copy.

11. (2026-11-08) A flow showed its display name (a sentence) as the title and overflowed the title row and the node menu header; it showed the device frame (Ping, `Points 0`, Add point, an empty points table) with the subtitle `node`. Fixed by §3.2 and §3a.

**Decided in the app (owner to confirm):** the points table scrolls under 720, not 860: at 1440 the workspace is 784 wide, and at 860 the Quality and Write columns were hidden.
