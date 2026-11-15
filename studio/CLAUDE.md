# CLAUDE.md

Guidance for agents working in this repository.

## Before hand-writing a file of this architecture, check `frx`

**Run `frx --help` first — it lists every command with what each one wires.**

This monorepo has a CLI that creates *and wires* every artifact of its
architecture: a state slice, a screen and its route, an action, a field, a
computed selector, a navigation hop, a connector, a widget, a service, an API
client. Writing those files by hand writes the files and misses the wiring — the
state slot and its `initial()` entry, the selector facade, the route
registration, the auth-guard membership. Wiring one navigation hop is five edits
across two packages, four of which leave code that does not compile on their own.

This rule is unconditional, and it applies to editing an existing artifact as much
as to creating one: **after any hand edit, run the audit** (`frx doctor`), then
`dart analyze`. The audit knows this architecture; the analyzer knows Dart.

## The owner's code rules (2026-11-15)

**Read `.claude/skills/studio-rules/SKILL.md` before writing or reviewing any
Studio code.** It wins over older text in the other skills. In short: no
`unawaited` around a dispatch; enums, not strings; each package owns its types
and a connector only maps; no `BuildContext` in connectors or `business`; text
resolved in `ui`/`localization`, never in a connector; theme tokens, not
numbers; callbacks typed in `ui/lib/models/value_changed.dart`; one typed
decode boundary for wire values; one dispatch per intent, with each rebuild
decided (`notify: false`, one state at the end, `null` when nothing changed).

`dart run tool/check_rules.dart` (CI job `studio`) counts every forbidden
pattern per file against `tool/rules_baseline.json`. A count may only go down;
a new file starts at zero. After removing violations, run it with `--lower` and
commit the smaller baseline. Never raise a baseline number by hand.
