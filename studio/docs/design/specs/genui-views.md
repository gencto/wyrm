# GenUI views — prototype brief

Boards: page **GenUI views** of the canvas (`GenView` clickable, `GenViewGenerating`, `GenViewChecks`, `GenViewRefine`, `GenViewKiosk`, `GenCatalog`). Samples in `../genui/`: `pump-station.a2ui.jsonl` (the board's document, keys invented), `pump-station.refine.a2ui.jsonl` (the refine turn), `demo-plant.a2ui.jsonl` (the same ideas on the demo broker's real points).

This is an **experiment**, not a feature: find out whether `genui` (Flutter, A2UI v0.9.1) can render WYRM views from a stored document with live data and Studio-run actions, the same in Studio desktop and in a browser. The answer decides ADR "Views" (declarative document + one Flutter renderer) before any production work.

## 1. Questions the prototype must answer
1. Can `genui` render a surface from A2UI messages we hand it (a stored JSONL), with no model and no `Conversation` in the loop?
2. Can Studio push live values into the surface's data model as they arrive (one `updateDataModel` per changed key, or a direct `DataModel` write), at 10–50 updates/s, without rebuilding the whole surface?
3. Can Studio intercept the surface's actions (`wyrm.set`, `wyrm.invoke`) before anything else sees them, ask first, call the broker with the viewer's session, and show the result?
4. Does a template over a node's children (`~children`, below) work through genui's template support, or does Studio have to expand it into static components?
5. How much of the catalog is cheap: which of the 18 parts are a thin wrapper over existing `ui` widgets (Value tiles, `Trend`, buttons), which need new work?
6. Web: does the same page run under `flutter run -d chrome --wasm`, what blocks it, and what is the size and first-load time of a `--wasm` release build?

Write the answers into §8 of this file as you find them (facts, versions, numbers), even when the answer is no.

## 2. Out of scope
Generation by a model (the samples stand in for it), storing views on the broker, publishing, roles, the views list, a hand editor, SVG import, the kiosk login. No change to `spec/`.

## 3. WYRM conventions on top of A2UI (catalog `wyrm:views/0.1`)
- **A path is a key.** A bound property is `{"path": "/wy/<site>/<section>/…"}`: the JSON pointer is the WYRM key with a leading `/`. Studio subscribes to every such key (its own `LiveValuesService`, the viewer's rights) and writes the value at that path of the surface's data model. Values are never part of the stored document.
- **Children of a node.** `"children": {"path": "/wy/…/<node>/~children", "componentId": "<template>"}` repeats the template once per child of `<node>` (from `list`, kept live: a child added or removed adds or removes an instance). Inside the template, relative paths (`{"path": "temp"}`) resolve to `<child key>/temp`; `{"path": "$name"}` is the child's display name; `{"path": "$key"}` its full key; `{"path": "<rel>/$key"}` the full key of `<rel>`.
- **Actions** are events with two names, handled by Studio and never sent anywhere else:
  - `wyrm.set` `{key, value}` — `value` may be `{"path": "$value"}`, the control's new value (Switch, Slider, Input);
  - `wyrm.invoke` `{key, action, args?}`.
  A component may carry `confirm` (text, `{name}` replaced in a template) and `enabledWhen {path, equals}`.
- **Units and decimals** fall back to the node's `~meta` (`unit`, `precision`) when the component leaves them out.

Catalog for the prototype (subset of `GenCatalog`): `Column`, `Row` (`weights`), `Card` (`title`), `Text` (`variant`), `Value` (`label`, `value`, `unit`, `decimals`, `warnAbove`), `Lamp` (`label`, `on`, `onAbove`, `onText`, `offText`), `Trend` (`title`, `range`, `series`), `Symbol` (`kind: pump`, `running`, `fault`, `value`, `unit`), `Switch`, `Slider` (`min`, `max`, `step`, `unit`), `Button` (`label`, `variant`, `confirm`, `enabledWhen`, `action`), `AlarmList` (static placeholder is enough). Unknown parts render as a placeholder card naming the part.

## 4. Where it goes in Studio
Everything through `frx` (see `CLAUDE.md`, `wiring-artifacts`), dry run first.
- **Dependency:** `genui` (latest; 0.10.x when this was written) and `json_schema_builder` in `ui/pubspec.yaml`. Read the package's own source in the pub cache before writing code: how a `SurfaceController` takes a message without a `Conversation` (look for a method that applies an `A2uiMessage`, or feed the JSONL text through `A2uiTransportAdapter.addChunk`), how the `DataModel` is written from outside, and how user actions come out (an event stream or callback on the controller or the surface). Note the exact API names in §8.
- **Catalog:** `ui/lib/views/catalog/` — one `CatalogItem` per part (`name`, `dataSchema` with `json_schema_builder`, `widgetBuilder`), built from existing widgets (`ui/lib/charts/` trend, value tiles, buttons, theme tokens); `wyrmCatalog()` returns them as one `Catalog` with id `wyrm:views/0.1`.
- **Bridge:** a service in `business` (`frx add-service view_bridge`): reads the document, collects every bound key (expanding `~children` by `list`), opens subscriptions through the existing session, turns each value into a data-model write, and turns `wyrm.*` actions into `set`/`invoke` calls with the confirm dialog and the errors of `specs/errors.md`.
- **Checks:** a pure function in `business` (`checkView(doc, catalog, tree, grants) → List<ViewCheck>`): part in the catalog, properties valid against its schema, every key exists, read right on each, write right on each action target. The board `GenViewChecks` shows the outcome.
- **Page:** `frx add-page views_lab` (route `/views-lab`, logged-in), reached from System for now. Left: pick a sample (`demo-plant`, `pump-station`), or paste JSONL; apply a second file (the refine turn) on top. Centre: the surface, widths Desktop / Panel 10" / Phone. Right: tabs Checks, A2UI (the messages as sent), Data (path → live value). Copy the boards' layout loosely; this is a lab, not the final screen.
- Samples are assets of `app` (`docs/design/genui/*.jsonl` copied to `app/assets/views/`).

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
7. Web (§5).
8. §8 filled in; `frx doctor`, `flutter analyze`, `flutter test` (a widget test that renders `demo-plant` with a fake bridge).

## 7. Done when
`demo-plant` renders in the lab on macOS with live values from the demo broker, the slider writes the BACnet setpoint after a confirm and the value comes back, the template shows one card per BACnet device, the refine turn updates only its parts, §8 answers all six questions, and the web run either works or says exactly what blocks it.

## 8. Findings
_(filled in by the prototype)_
- genui version and API used:
- Q1 messages without a model:
- Q2 live data model writes, rate, rebuild scope:
- Q3 action interception:
- Q4 templates over `~children`:
- Q5 catalog cost per part:
- Q6 web: blockers, transport, size, first load, browsers:
