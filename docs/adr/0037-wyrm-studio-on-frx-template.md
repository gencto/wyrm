# ADR 0037 — WYRM Studio: the Flutter app as an AsyncRedux monorepo made with `frx`

**Status:** accepted · 2026-11-08 (owner: "the Flutter project is built on the flutter_redux_templates approach and structure; what WYRM has in Flutter was the development version and is replaced").

## Context
`dart/wyrm_flutter` (iteration 7) was a development explorer: a lazy tree, an action flyout, a history chart and the dataflow editor of ADR 0019, styled as the DSA explorer (`WyStyle` constants), with one example app. It proved the gateway and FFI paths, but it has no state model, no navigation, no localization and no tests above widget level, and every screen added to it grew `explorer.dart` (1 800 lines).

The owner designed WYRM Studio (a design canvas of every screen and its states: Explorer, Links and Add a link, Sites, Flows and the field-based flow editor, History, Access, System, Assistant) and chose [`flutter_redux_templates`](https://github.com/pro100andrey/flutter_redux_templates) as its base: a Pub-workspace monorepo (`app`, `ui`, `business`, `models`, `storage`, `localization`) on AsyncRedux, with the `frx` CLI that creates **and wires** every artifact (substates, actions, fields, selectors, pages, routes, navigation, services, widgets) and audits the wiring (`frx doctor`).

## Decision
1. **`studio/` is the app**, created by `frx create wyrm_studio --org uk.gencto --title 'WYRM Studio' --without http_client` (frx 0.3.7). Its own `CLAUDE.md`, `.claude/skills` and hook come with it; work on Studio from `studio/`.
2. **`dart/wyrm_flutter` is removed.** Its code stays in git history (`6199482`) as a reference for the tree's lazy loading, `editor: file` uploads and the ADR 0019 editor.
3. **`dart/wyrm_core`, `wyrm_client`, `wyrm_ffi` stay** where they are, outside the Studio workspace, so the fixture job in CI keeps running with plain `dart`. `studio/business` depends on `wyrm_client` by path; it takes the place of the template's `http_client` (the gateway has four REST routes; everything else is CBOR frames over one WebSocket).
4. **Every artifact is made with `frx`**, by hand only inside bodies. The scaffold is declared as batch files in `studio/docs/batches/` (checked with frx 0.3.7: applied in order on a fresh project, `frx doctor` reports only the codegen it has not run). After a hand edit: `frx doctor`, then `dart analyze`.
5. **Live values do not go into the store one sample at a time.** A service subscribes only to the keys on screen and dispatches one batched action at most every 200 ms; connectors select only their keys.
6. **Generated UI in the assistant is a closed catalogue of cards** (plan, step, choices, run, result, error) rendered from the task record (`tasks/<id>` `~state`); the model never chooses widgets. A step shows its key and `args` verbatim (security review AI-4).
7. **The look comes from the design canvas**: its tokens replace the template's `_Brand`/`_Neutrals` constants and `AppColors`; IBM Plex Sans/Mono are bundled (no font download at run time: edge machines are often offline); icons are the canvas's SVG paths in `ui/assets/svg/icons/`.

The plan, phase by phase with the commands, is [`docs/studio.md`](../studio.md).

## Consequences
- Studio targets desktop and mobile first. `wyrm_client` uses `dart:io` (HTTP, WebSocket), so the web build needs a second transport before it works.
- What the design needs from the broker and the agent link that does not exist yet is listed in `docs/studio.md` §10; each item becomes its own change on the Rust side.
- The template's machinery (the `frx` sources, its CI) is not in this repository; `frx` is installed as a binary (`frx upgrade`).

## Alternatives
- **Keep `wyrm_flutter` and grow it:** no state model or navigation to grow into; the owner called it the development version.
- **Put the Studio packages and `dart/` in one workspace:** `dart pub get` in `dart/wyrm_core` would then resolve Flutter packages and the fixture job would need Flutter.
- **Riverpod or Bloc instead of AsyncRedux:** no generator that wires and audits, which is what keeps a large app consistent when assistants write much of it.
