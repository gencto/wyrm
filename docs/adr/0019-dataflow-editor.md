# ADR 0019 — Dataflow editor in the explorer

**Status:** accepted · 2026-10-24 (owner decisions: a separate large window; changes go live with a Deploy button; WYRM node types drawn as DSA blocks).

## Context
Flows (spec 06) could only be deployed as JSON (`wyr flow deploy`, `dataflows/~act/deploy`). The owner asked for editing in the explorer, as a DSA client edits a dataflow: blocks on a canvas, wires between their pins, a palette, properties. The DSA editor (`remote_dataflow.html`) is studied in the DSA repository's `docs/dataflow/editor.md` and its prototype `tool/dataflow_editor/index.html`; it binds inputs to outputs and saves each edit at once.

## Decision
- **Window:** `Edit Dataflow` on a flow node (`dataflows/<id>`) and `New Dataflow` on `dataflows` open one large window over the explorer, as View History does: the palette on the left, the canvas in the middle, the properties of the selected block (or of the flow) on the right, the state, the check result and Deploy on top.
- **Model stays spec 06:** nodes with a type and a config, edges `["<node>.<port>", "<node>.<port>"]`. The DSA look is kept (a block is a header and one row per port, inputs with a pin on the left, outputs on the right; S-curve wires; drag from an output pin to an input pin links them, a double click on an input pin unlinks it; an input takes one link, a new one replaces it, as DSA binds an input to one source), the DSA model (bindings on inputs, saving each edit) is not.
- **Positions:** `~def.layout` = `{<node>: [x, y]}` (spec 06 0.2.5), outside every node's config, so moving a block keeps its state on a hot swap.
- **Palette and forms from the engine:** `dataflows/~act/node_types` (level `read`) answers the catalog (`wyrm_flow::catalog`): type, category, description, ports (fixed, or named by a parameter: `expression` `in.<name>`, `wasm` ports), parameters with type, choices, default and editor hint. A test checks every type's sample configuration against `nodes::ports`, so the catalog cannot drift from the compiler.
- **Load, check, deploy:** the current definition is the last item of `dataflows/<id>/~act/history` (level `read`); every edit is checked with `dataflows/~act/validate` (debounced) and the error shown; Deploy sends the whole definition with `version` + 1 through `dataflows/~act/deploy` (the gateway adds the deployer's proofs for `set`/`invoke` targets, ADR 0008). A flow with a `set` or `invoke` node gets `permissions.maxperm: write` when it has none. Fields the editor does not know (`policy`, …) are kept.

## Consequences
- Deploying needs `config` on `dataflows` (as before); `validate`, `history` and `node_types` need `read`, so a viewer can open a flow and see it, not change it.
- Each Deploy is a version with history and rollback; there is no undo in the window.
- Live values on pins are not shown yet (a later slice).

## Alternatives
- **Saving each edit (DSA):** every move or link would deploy a version and restart the flow; a half-made flow does not compile.
- **Positions in each node's config:** `only()` refuses unknown keys, and a moved node would get a new hash and lose its state.
