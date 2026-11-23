---
name: asyncredux-in-this-template
description: >-
  How async_redux is actually used in this monorepo, where it diverges from the
  library's own documentation, and the pieces no `frx` command owns —
  dispatching, waiting, user-facing errors, persistence and injected
  dependencies. Use before writing the body of a reducer, a connector or a state
  class, and whenever recalled async_redux knowledge is about to be applied
  here.
---

# async_redux, as this template uses it

## Five places the library's docs point the wrong way

| Stock async_redux | Here |
| --- | --- |
| an immutable class with its own `copy()` | `@freezed`, and `state.copyWith.<slice>(…)` for a nested write |
| `extends ReduxAction<AppState>` | `extends Action` — it mixes in `Selectors` and types `deps` and `env` |
| selector functions memoised with `cache1` / `cache2` | a facade of `extension type`s over `AppState`, zero-cost, nothing to memoise |
| `VmFactory` / `Vm` written however | `_Factory` / `_Vm`, private, in the connector file, `with Selectors` |
| `List` / `Map` in state | `IList` / `IMap` / `ISet` |

Everything below is the part no command scaffolds.

## Dispatching

- `dispatchSync` — a synchronous reducer. Setters from a connector use this.
- `dispatchAndWait` — returns the `ActionStatus`; await it when the next step
  depends on whether the action succeeded.
- `dispatch` — fire and forget, including `GoAction` for navigation.
- Never `unawaited(dispatch…(…))` (`studio-rules` §1): start work with
  `dispatch`, show it with `WaitingAction` and `waiting.<name>` (see
  "Waiting"), and put a sequence of steps inside one action that awaits them.

Navigation is itself an action (`GoAction.push` / `replace` / `navigate` / `pop`
/ `popUntilRoot`), so it is observable and testable like any other, and
connectors never poke the router.

## Waiting

**This project diverges from what `frx` 0.3.7 generates** (owner decision
2026-11-23, async_redux 30). async_redux deprecated `Wait`, `WaitAction`,
`WaitOperation` and `WaitReducer` in 29.3.2; none of them is used here.
`AppState` has no `wait` field, and nothing about an action in flight is
written to the state. The store knows the actions it runs.

`Waiting` (`business/lib/redux/common/waiting.dart`) is the one way to read
"busy". It wraps the store's `isWaiting`:

```dart
waiting                       // in an `Action` and in a `VmFactory` (`with Selectors`)
Waiting(store.isWaiting)      // beside a store: a dialog, a service
Waiting.fixed({MyAction})     // in a test of a selector or a view
const Waiting.none()          // in a test: nothing is in flight
const Waiting.unasked()       // a view made from a state alone (asserts if asked)
```

`Selectors` needs two members, `state` and async_redux's own `isWaiting`,
and makes `waiting` from them. An action and a `VmFactory` have both, so a
connector's `_Factory` writes `with Selectors` and nothing more. A holder
with no store adds a mixin: `WaitingGiven` (it was handed a `Waiting`),
`StateAlone` (it draws no wait; asking asserts), `NothingInFlight` (a
test). Every wait a screen
draws has a name in `extension WaitingFor on Waiting` (`selectors.dart`):
`waiting.logIn`, `waiting.linkActing`. A selector that needs both the state
and a wait is in `extension WaitingComposites on Selectors`. A pure view
function takes the `Waiting` as an argument (`flowViewOf(state, waiting, id)`).
Never read a wait from a slice selector (`Select<Slice>`): it has the state
only.

`WaitingAction` is a marker with no hooks: `Waiting.on<T>()` accepts only a
type that has it. An action that no screen draws does not mix it in.

### A new waiting action: bring the generated form to this one

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

### Rebuilds: the wait must be in what the connector compares

The state does not change when an action starts or ends. The store tells its
listeners at both moments only for an action type that somebody has asked
about with `isWaiting` (`Store._awaitableActions`). So:

- a view-model asks again on every run, and puts the answer into the value
  it returns (`_Vm(equals: [...])`); a view-model that asked is told, also
  for an action dispatched with `notify: false`;
- a `StoreConnector` whose `converter` returns only state is **not** built
  again when an action starts. Put the wait into the converter's value:
  `converter: (s) => (s.state, Waiting(s.isWaiting).linkLog)`;
- a memoized view (`Memo`) has every wait it reads among its inputs;
- an action nobody asks about tells nobody when it starts. That replaces
  `notifyBefore => false`, which is gone.

`business/test/waiting_action_test.dart` holds this on the real store;
`app/test/rebuild_explorer_test.dart` and `app/test/shell_parts_test.dart`
hold it at the widget level.

### The barrier

`Store.isWaiting` compares exact runtime types, so it cannot be asked about
the `BlockingAction` mixin. `TopLevelPageConnector` asks about the list
`blockingActions` (`app/lib/common/blocking_actions.dart`). An action blocks
when it has the mixin and is in the list; a test reads the sources and fails
while they disagree.

### Several keys under one action type

Override `Object? get statusKey` in the action and ask with
`isWaiting(MyAction, statusKey: key)`. An action that covers several keys at
once reads `store.actionsInProgress()`
(`RetrieveFlowDefsAction.reading(store, id)`).

### In a test

Run the real action and hold its answer at the fake gateway
(`api.hold('<key> ▸ history')`), then pump. Where the work cannot be held,
`HeldStore` (`business/test/support/held_store.dart`) says a type is in
flight. Do not write a wait into an `AppState`: there is no place for it.

## Errors the user should see

Throw `UserException` from a reducer and async_redux shows it. `store.dart`
installs a `GlobalErrorObserver` that logs, wraps anything else into a
`UserException`, and gives the app a first chance to translate through a
`UserErrorWrapperHandler` returning a `LocalizedMessage` (title + message) — so a
message can be localised without `business` depending on the app's locale.

## Persistence

`AppPersistor` (`business/lib/persistor.dart`) is a `Persistor<AppState>` over
`KeyValueStorage` from `storage`. Boot goes through `createStore`: open storage,
read the persisted state, fall back to `AppState.initial()`. The app layer never
touches the storage backend. A persistor rebuilds state without dispatching,
which is why `frx graph` gives it a node of its own.

## Injected dependencies and environment

`AppDependencies` is built once by the store and reaches a reducer as `deps` on
the `Action` base; `Environment` (base URL, prod/dev) reaches it as `env`. Both
are already typed there — reading `store.dependencies` and casting is the long
way round.

## What this template does not use

Undo/redo, stream and timer actions, the provider integration, flutter_hooks,
events, `abortDispatch`, the optimistic-update mixin, and async_redux's testing
helpers — the template ships no test harness at all. If a task genuinely needs
one of these it is new ground here, not an established pattern: say so rather
than adopting it silently.
