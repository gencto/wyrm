# GenUI views — prototype brief

Boards: page **GenUI views** of the canvas. Row 1: `GenView` (clickable), `GenViewGenerating`, `GenViewChecks`, `GenViewRefine`, `GenViewKiosk`; `GenCatalog`. Row *Project*: `GenProject` (desktop), `GenProjPump` (drill-down), `GenProjPanel`, `GenProjPhone`, `GenProjPhonePump`, `GenProjKiosk`. Row *Style contract*: `GenStyle` (rules and the manifest), `GenStyleLight`, `GenStylePanelLight`, `GenStylePhoneLight`.

Samples in `../genui/`: `pump-station.a2ui.jsonl` (the board's document, keys invented), `pump-station.refine.a2ui.jsonl` (the refine turn), and a two-page project on the demo broker's real points: `demo-plant.project.json` (manifest), `demo-plant.a2ui.jsonl` (Overview), `demo-device.a2ui.jsonl` (page `Device {device}`).

This is an **experiment**, not a feature: find out whether `genui` (Flutter, A2UI v0.9.1) can render WYRM views from a stored document with live data and Studio-run actions, the same in Studio desktop and in a browser. The answer decides ADR "Views" (declarative document + one Flutter renderer) before any production work.

## 1. Questions the prototype must answer
1. Can `genui` render a surface from A2UI messages we hand it (a stored JSONL), with no model and no `Conversation` in the loop?
2. Can Studio push live values into the surface's data model as they arrive (one `updateDataModel` per changed key, or a direct `DataModel` write), at 10–50 updates/s, without rebuilding the whole surface?
3. Can Studio intercept the surface's actions (`wyrm.set`, `wyrm.invoke`) before anything else sees them, ask first, call the broker with the viewer's session, and show the result?
4. Does a template over a node's children (`~children`, below) work through genui's template support, or does Studio have to expand it into static components?
5. How much of the catalog is cheap: which of the 18 parts are a thin wrapper over existing `ui` widgets (Value tiles, `Trend`, buttons), which need new work?
6. Web: does the same page run under `flutter run -d chrome --wasm`, what blocks it, and what is the size and first-load time of a `--wasm` release build?
7. Style: with only Studio's own catalog widgets (no genui `CoreCatalogItems`), does every surface follow the theme (dark and light) and the density of where it is shown, with the document unable to set a colour or a font (§3.2)?
8. Project: can a manifest of pages, a menu and a frame (§3.3) sit around genui surfaces — one surface per page, `wyrm.open` with parameters, back stack and breadcrumbs, the menu changing form by width, alarm badges on menu items?

Write the answers into §8 of this file as you find them (facts, versions, numbers), even when the answer is no.

## 2. Out of scope
Generation by a model (the samples stand in for it), storing views on the broker, publishing, per-page roles, the views list, a hand editor, SVG import, faceplates generated from device profiles (a later step: one standard card per `<vendor>:<model>`, composed by the model, not drawn by it), the kiosk login. No change to `spec/`.

## 3. WYRM conventions on top of A2UI (catalog `wyrm:views/0.1`)

### 3.1 Bindings and actions
- **A path is a key.** A bound property is `{"path": "/wy/<site>/<section>/…"}`: the JSON pointer is the WYRM key with a leading `/`. Studio subscribes to every such key (its own `LiveValuesService`, the viewer's rights) and writes the value at that path of the surface's data model. Values are never part of the stored document.
- **Children of a node.** `"children": {"path": "/wy/…/<node>/~children", "componentId": "<template>"}` repeats the template once per child of `<node>` (from `list`, kept live: a child added or removed adds or removes an instance). Inside the template, relative paths (`{"path": "temp"}`) resolve to `<child key>/temp`; `{"path": "$name"}` is the child's display name; `{"path": "$key"}` its full key; `{"path": "<rel>/$key"}` the full key of `<rel>`.
- **Actions** are events with two names, handled by Studio and never sent anywhere else:
  - `wyrm.set` `{key, value}` — `value` may be `{"path": "$value"}`, the control's new value (Switch, Slider, Input);
  - `wyrm.invoke` `{key, action, args?}`.
  A component may carry `confirm` (text, `{name}` replaced in a template) and `enabledWhen {path, equals}`.
- **Units and decimals** fall back to the node's `~meta` (`unit`, `precision`) when the component leaves them out.
- **Page parameters.** In a page with parameters, `{name}` inside a path is replaced by the parameter's value (a full key): `{"path": "{device}/temp"}` with `device = wy/plant/downstream/bacnet/sim/d1` reads `/wy/plant/downstream/bacnet/sim/d1/temp`.
- **A third action**, `wyrm.open` `{page, params}`, opens another page of the project (§3.3).

### 3.2 Style contract (board `GenStyle`)
The surface is drawn only by Studio's catalog widgets, which use the theme tokens of `ui/lib/theme/common.dart` (dark and light). The document chooses **parts and variants**, never looks:
- may: `size` (s, m, l) on Value, Gauge, Symbol; `variant` (primary, neutral, danger) on Button, (plain, outlined) on Card; `emphasis` (normal, key) on Card; `weights` in a Row; limits (`warnAbove`, `warnBelow`, `badAbove`, `badBelow`) when `~meta` has none;
- never: a colour (the `theme` of `createSurface` is ignored), a font, a pixel size or position outside a mimic canvas, a rule that colours something by hand, markup or URLs. The catalog schemas leave these properties out, so a document that carries them fails the check.
- State colours are fixed (after ISA-101): normal `text1`, running/on `good`, warning (warn limits, uncertain) `warn`, alarm/fault (bad limits, fault, active alarm) `bad`, stopped/no data/not readable `muted`.
- Density comes from where the surface is shown, never from the document: desktop (values 24 px, buttons 38–44, header 56, gap 12), panel 10–15" (values 34, buttons 56, header 68, gap 16, menu as top tabs 52 high), phone (values 22, buttons 56, bottom bar), kiosk (as panel, menu hidden). A `ViewDensity` passed down by the page; the catalog widgets read it.

### 3.3 Project: pages, menu, frame (boards `GenProject*`, manifest in `GenStyle`)
A view project is a manifest (our format, JSON) around A2UI documents; A2UI itself has no pages. Fields (see `../genui/demo-plant.project.json`):
- `pages[]`: `id`, `title` (may use a parameter: `Device {device}`), `doc` (the page's A2UI document; one surface per page), `params` (`{name: {under: <key>}}`: the value is a child of that node), optional `roles`;
- `nav[]`: up to two levels; an item is `{page}` or `{label, children}`; `children: {page, each: <param>}` makes one item per child of the parameter's node (one per pump, kept live);
- `frame`: an A2UI document drawn around every page (title, clock, alarm banner with Acknowledge); for the prototype a fixed Studio widget is enough;
- `home`; `kiosk {rotate: [page?param=value…], every_s}` (rotation pauses 60 s after a touch and stops while an alarm is unacknowledged).

Behaviour:
- `wyrm.open {page, params}` opens the page with its parameters; Studio keeps the back stack and shows breadcrumbs (`Overview › Pumps › Pump 2`), and a deep link `/view/<project>/<page>?<param>=<key>` opens the same.
- The menu changes form by width: sidebar with groups (desktop), top tabs 52 high (panel), bottom bar of five with *More* (phone), hidden with rotation dots (kiosk).
- A menu item carries a badge with the number of active alarms whose source is one of the keys its page reads (Studio knows them from the bindings), coloured by the worst.
- A page none of whose keys the viewer may read is left out of their menu.

Catalog for the prototype (subset of `GenCatalog`): `Column`, `Row` (`weights`), `Card` (`title`, `variant`, `emphasis`, `action`: a whole card can open a page), `Text` (`variant`), `Value` (`label`, `value`, `unit`, `decimals`, `warnAbove`), `Lamp` (`label`, `on`, `onAbove`, `onText`, `offText`), `Trend` (`title`, `range`, `series`), `Symbol` (`kind: pump`, `running`, `fault`, `value`, `unit`), `Switch`, `Slider` (`min`, `max`, `step`, `unit`), `Button` (`label`, `variant`, `confirm`, `enabledWhen`, `action`), `AlarmList` (static placeholder is enough). Unknown parts render as a placeholder card naming the part.

## 4. Where it goes in Studio
Everything through `frx` (see `CLAUDE.md`, `wiring-artifacts`), dry run first.
- **Dependency:** `genui` (latest; 0.10.x when this was written) and `json_schema_builder` in `ui/pubspec.yaml`. Read the package's own source in the pub cache before writing code: how a `SurfaceController` takes a message without a `Conversation` (look for a method that applies an `A2uiMessage`, or feed the JSONL text through `A2uiTransportAdapter.addChunk`), how the `DataModel` is written from outside, and how user actions come out (an event stream or callback on the controller or the surface). Note the exact API names in §8.
- **Catalog:** `ui/lib/views/catalog/` — one `CatalogItem` per part (`name`, `dataSchema` with `json_schema_builder`, `widgetBuilder`), built from existing widgets (`ui/lib/charts/` trend, value tiles, buttons, theme tokens); `wyrmCatalog()` returns them as one `Catalog` with id `wyrm:views/0.1`.
- **Bridge:** a service in `business` (`frx add-service view_bridge`): reads the document, collects every bound key (expanding `~children` by `list`), opens subscriptions through the existing session, turns each value into a data-model write, and turns `wyrm.*` actions into `set`/`invoke` calls with the confirm dialog and the errors of `specs/errors.md`.
- **Checks:** a pure function in `business` (`checkView(doc, catalog, tree, grants) → List<ViewCheck>`): part in the catalog, properties valid against its schema, every key exists, read right on each, write right on each action target. The board `GenViewChecks` shows the outcome.
- **Page:** `frx add-page views_lab` (route `/views-lab`, logged-in), reached from System for now. Left: pick a sample (`demo-plant`, `pump-station`), or paste JSONL; apply a second file (the refine turn) on top. Centre: the surface, widths Desktop / Panel 10" / Phone. Right: tabs Checks, A2UI (the messages as sent), Data (path → live value). Copy the boards' layout loosely; this is a lab, not the final screen.
- Samples are assets of `app` (`docs/design/genui/*.jsonl` and `*.project.json` copied to `app/assets/views/`).
- **Project shell (Q8):** in the lab, a *Project* switch loads `demo-plant.project.json` and shows the menu (sidebar / top tabs / bottom bar by width), a fixed frame widget with the alarm banner, and one genui surface per page; `wyrm.open` from the device cards of Overview opens `Device {device}`, with breadcrumbs and back. Navigation inside the lab is local state (not new routes) for the prototype.
- **Density and theme (Q7):** a `ViewDensity` (desktop, panel, phone, kiosk) chosen by width with an override in the lab, and the app's light/dark switch; render `demo-plant` in all eight combinations in one widget test (goldens optional).

## 5. Web (question 6)
Studio does not build for the browser today: `dart/wyrm_client/lib/src/gateway.dart` uses `dart:io` (`HttpClient`, `WebSocket`), so do `business/lib/wyrm/session.dart` and `business/lib/redux/store.dart`, and the gateway sends no CORS headers. For the lab:
1. Measure first: `cd studio/app && flutter run -d chrome --wasm --route /views-lab` and write down every compile error with its file.
2. Give `wyrm_client` a browser transport behind a conditional import (`if (dart.library.js_interop)`): login and ticket over `package:web` `fetch`, the socket over `package:web` `WebSocket` (binary frames), the same `FrameTransport` interface as `WebSocketTransport`. The `dart:io` path stays as it is.
3. Same origin instead of CORS: serve the web build from the gateway in development (a `gateway.web_root` directory served on `/` for loopback only), or run Chrome against a local reverse proxy; pick one, note it in §8, and keep it out of release builds. A change in `crates/wyrm-gateway` is a separate pull request with its own tests.
4. Record: `flutter build web --wasm --release` size (total and `main.dart.wasm`), first load on the demo machine, and whether live values and a `wyrm.set` work in Chrome, Firefox and Safari.

## 6. Steps
1. Demo up (`examples/demo/run.sh`); with `wyr list` check the keys in `demo-plant.a2ui.jsonl` (`s7/plc1/cpu/{temp,counter,mw}`, `bacnet/sim/d1/{temp,sp}`) and fix the file if the tree differs.
2. Read the `genui` source (§4) and answer question 1 in a few lines of §8 before writing the catalog.
3. Catalog (5 parts first: Column, Row, Card, Value, Text), page, render `demo-plant` with values fixed in the data model.
4. Bridge: live values, then `~children`, then `wyrm.set` (Slider on `bacnet/sim/d1/sp`, Button on `s7/plc1/cpu/mw`) with confirm.
5. The rest of the catalog subset; `pump-station` renders with placeholders where its invented keys do not exist (that is the Checks tab's job).
6. Refine: apply `pump-station.refine.a2ui.jsonl` on top; only the changed parts rebuild.
7. Style: variants and density (§3.2) in the catalog widgets; light and dark.
8. Project: manifest, menu by width, `wyrm.open` with parameters, breadcrumbs, badges (§3.3).
9. Web (§5).
10. §8 filled in; `frx doctor`, `flutter analyze`, `flutter test` (a widget test that renders `demo-plant` with a fake bridge).

## 7. Done when
`demo-plant` renders in the lab on macOS with live values from the demo broker, the slider writes the BACnet setpoint after a confirm and the value comes back, the template shows one card per BACnet device, the refine turn updates only its parts, a click on the device card opens `Device d1` with breadcrumbs and back, the menu takes its three forms by width, light and dark both follow the theme, §8 answers all eight questions, and the web run either works or says exactly what blocks it.

## 8. Findings
_(filled in by the prototype)_
- genui version and API used: `genui` 0.10.4 with `a2ui_core` 0.1.1 and `json_schema_builder` 0.1.7 (Flutter 3.50.0).
- Q1 messages without a model: yes. `SurfaceController(catalogs: [wyrmCatalog()])`, then `controller.handleMessage(A2uiMessage.fromJson(map))` per stored line, and `Surface(surfaceContext: controller.contextFor(surfaceId))` draws it; no `Conversation`, no `Transport`, no model. `A2uiMessage` is a class of `a2ui_core`, which `genui` does not export, so `ui` depends on `a2ui_core` itself. `A2uiMessage.fromJson` refuses every `version` but the exact text `v0.9` (the samples say `v0.9.1`), so Studio rewrites the field before it hands a line over.
- Q2 live data model writes, rate, rebuild scope:
- Q3 action interception:
- Q4 templates over `~children`:
- Q5 catalog cost per part:
- Q6 web: blockers, transport, size, first load, browsers:
- Q7 style: theme and density followed, properties refused:
- Q8 project: manifest, menu forms, `wyrm.open`, back stack, badges:
