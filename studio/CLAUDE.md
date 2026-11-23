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

## Waiting: this project diverges from `frx` 0.3.7 (async_redux 30)

`frx add-action -k waiting` still generates the form of async_redux 29: a
getter over `_state.wait` in `selectors.dart`. `AppState` has no `wait`
here, and `Wait`/`WaitAction` are deprecated in async_redux. "Busy" is read
through `Waiting` (`business/lib/redux/common/waiting.dart`), from the
store, never from the state. The full rules are in
`.claude/skills/asyncredux-in-this-template/SKILL.md`, section "Waiting".

To bring a freshly generated waiting action to this form:

1. Run `frx add-action <name> --state <slice> -k waiting --no-selector`. With
   `--no-selector` it writes no getter into `selectors.dart`. The action file
   needs no edit: `class MyAction extends Action with WaitingAction` is the
   form in use (`WaitingAction` is a marker with no hooks).
2. If you ran it without `--no-selector`, delete the getter it wrote into
   `Select<Slice>` in `business/lib/redux/selectors.dart`
   (`bool get isWaiting => _state.wait.isWaitingForType<MyAction>();`). It
   does not compile: `AppState` has no `wait`.
3. Add the name of the wait to `extension WaitingFor on Waiting` in the same
   file: `bool get myThing => on<MyAction>();` (several actions:
   `any(const [A, B])`).
4. Read it where a store is at hand: `waiting.myThing` in the connector's
   `_Factory.fromStore()` or in another action. Put the answer into the
   `_Vm` (it is compared).
5. If the action must cover the app with the barrier, add `BlockingAction`
   to its `with` clause **and** its type to `blockingActions`
   (`app/lib/common/blocking_actions.dart`).
   `app/test/blocking_actions_test.dart` fails while the two disagree.
6. Run `frx doctor`, `dart run tool/check_rules.dart`, `flutter analyze`.

A `StoreConnector` whose `converter` returns only state is not built again
when an action starts or ends, because the state is the same object. Put the
wait into the converter's value, or into the `_Vm`.

`frx doctor` accepts this form (it reports the skills warning only). Do not
run `frx update-skills`: it would write the old "Waiting" text back.
