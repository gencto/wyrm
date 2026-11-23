---
name: frx-add-action
description: >-
  Something that changes state — a reducer, a mutation, an async operation
  a screen dispatches. Wired by `frx add-action` (alias `aa`). Do NOT
  hand-write this artifact or edit the files it wires — run the command.
---

# `frx add-action`

Scaffold a ReduxAction into a substate.

```
frx add-action <name> --state <substate>
```

## What an action is here

An action is a class with a `reduce()` method. You dispatch it; the store calls
`reduce()` and replaces the state with what it returns. Returning `null` means
"no state change" — the action still ran, and observers still see it.

Actions extend **`Action`**, not `ReduxAction<AppState>`. The base lives in
`business/lib/redux/common/action.dart` and is what gives a reducer its three
tools:

```dart
abstract class Action extends ReduxAction<AppState> with Selectors {
  AppDependencies get deps => store.dependencies! as AppDependencies;
  Environment get env => store.environment! as Environment;
}
```

- `Selectors` — the selector facade, so state is read as `login.email`
- `deps` — injected services
- `env` — base URL, prod/dev

**Synchronous.** Parameters arrive through the constructor as `final` fields;
the write is freezed's nested `copyWith`:

```dart
class SetEmailAction extends Action {
  SetEmailAction(this.value);

  final String? value;

  @override
  AppState reduce() => state.copyWith.login(email: value);
}
```

**Asynchronous.** `Future<AppState?> reduce() async`, and every path must
`await`. Reads go through the facade — `login.email`, never `state.login.email`:

```dart
class LogInWithEmailAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await _request(email: login.email!, password: login.password!);

    return state.copyWith(login: const LoginState());
  }
}
```

**This project diverges from the generated form here** (async_redux 30,
owner decision 2026-11-23; the `--help` text below is the tool's and still
describes `Wait`). `with WaitingAction` is a marker with no hooks: it says a
screen draws this action's wait. The store knows the action is in flight; a
screen asks through `Waiting`: `waiting.logIn`, a name in `extension
WaitingFor on Waiting` that is `on<LogInWithEmailAction>()`. `AppState` has
no `wait`, so the getter `-k waiting` writes into `Select<Slice>` does not
compile. After `frx add-action -k waiting`:

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

`WaitingAction` still goes **last** in the `with` clause: `add-action`
writes it there and `frx doctor` checks it. The order no longer matters to
the wait (the store takes an ended action out by itself).

**How it is dispatched**, from a connector's `_Factory`: `dispatchSync` for a
synchronous setter, `dispatchAndWait` when the next step depends on the result,
plain `dispatch` for fire-and-forget.

## Before you run it

- The suffix is optional and idempotent: `ArchiveTask` and
  `ArchiveTaskAction` scaffold the same artifact. Do not strip it yourself,
  and do not add it — pass the name as you have it. `frx remove` reads the
  same rule, so whichever spelling created it removes it.
- Mixins conflict, and the conflict is an **analyzer error**: async_redux
  makes groups mutually exclusive by colliding on a private member, so
  `dart analyze` reports `private_collision_in_mixin_application`. The
  compiler does not — `flutter test` on such a file runs, and an `assert`
  inside async_redux throws on the first dispatch, in a debug build only.
  Ask `frx list-mixins` which exclude which and let the scaffolder write
  the `with` clause; it refuses a bad pair up front.
- `-k waiting` also adds the substate's `isWaiting` getter over
  `_state.wait`. Here that getter does not compile: pass `--no-selector`
  and add the name to `WaitingFor` by hand (steps above).
- The **order** of a `with` clause is load-bearing, and getting it wrong is
  not a compile error. Dart runs one `after()` — the last mixin's — so a
  mixin that overrides it without `super.after()` ends the chain. Through
  async_redux 28.1 `NonReentrant`, `Throttle` and `Fresh` did: `with
  WaitingAction, NonReentrant` analyzed clean and never lowered the wait
  barrier, and the button reading `isWaiting` stayed dead for the session.
  Since 28.3.1 every mixin chains, and since this project reads the wait
  from the store (async_redux 30) no hook can leave it up. The rule stays
  for other hooks and for `frx doctor`: `WaitingAction` goes **last**;
  `add-action` writes it there, `frx list-mixins` says which mixins end the
  chain, and `frx doctor` reports a clause that has it wrong.

## Flags

```
-h, --help                                 Print this usage information.
    --dry-run                              Show the planned changes without writing.
-f, --force                                Overwrite existing files.
    --[no-]format                          Run `dart format` on the changed files.
                                           (defaults to on)
    --json                                 Emit the changeset as JSON instead of the human report (with --dry-run it is marked not applied).
    --root                                 Repo root to search from.
-s, --state                                The substate to add the action to (its folder under business/lib/redux, any casing).
-k, --kind                                 Action body shape.

          [sync] (default)                 AppState? reduce() — synchronous state update.
          [async]                          Future<AppState?> reduce() async — async work.
          [waiting]                        extends Action with WaitingAction — async, and in `Wait` while it runs so a selector can read it. Add BlockingAction by hand for one the modal barrier should cover.

-m, --mixin                                async_redux behaviour mixin (repeatable). Dependencies are added automatically (noDialog → checkInternet, unlimitedRetries → retry).

          [checkInternet]                  Check connectivity first; error dialog when offline
          [noDialog]                       With checkInternet: fail without the dialog
          [abortWhenNoInternet]            Abort silently when offline
          [nonReentrant]                   Ignore a dispatch while already running
          [retry]                          Retry failures with exponential backoff
          [unlimitedRetries]               With retry: never stop retrying
          [debounce]                       Run only after a pause in dispatches
          [throttle]                       Drop dispatches while a recent run is fresh
          [fresh]                          Skip the run while the last result is still fresh
          [sequential]                     Run one at a time, in dispatch order (a queue per key)
          [unlimitedRetryCheckInternet]    Retry forever, treating offline as a failure to retry

    --[no-]selector                        For --kind waiting, also add the substate's `isWaiting` getter to its Select<Pascal> in selectors.dart.
                                           (defaults to on)
```

Every writing command takes `--dry-run` (plan only), `--json` (the changeset as
data), and `--force`. A non-zero exit means none of it landed.

## After

`frx doctor`, then `dart analyze`. When the feature is finished and before the
next one starts, `frx graph` — it is the only one that names code nothing
reaches.
