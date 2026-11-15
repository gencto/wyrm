---
name: studio-rules
description: >-
  The owner's code rules for WYRM Studio (2026-11-15), checked by
  `tool/check_rules.dart` in CI: no `unawaited` around a dispatch, enums not
  strings, each package owns its types, no `BuildContext` in connectors or
  business, text resolved in `ui` and `localization` and never in connectors,
  theme tokens instead of numbers, typed callbacks from `value_changed.dart`,
  one typed decode boundary for wire values. Read before writing or changing any
  connector, action, reducer, mapper, widget or view-model in `studio/`, and
  before reviewing Studio code. These rules win over any older text in another
  skill.
---

# Studio code rules

The owner wrote these after reading the code (2026-11-15). They win over any
older text in `data-driven-widgets` or `asyncredux-in-this-template`. Each rule
has the rule, why, a bad/good pair from this codebase, and its check.

`tool/check_rules.dart` counts every pattern below per file against
`tool/rules_baseline.json`. **A count may only go down. A new file starts at
zero.** CI job `studio` runs it. After you remove violations, run
`dart run tool/check_rules.dart --lower` and commit the smaller baseline. Never
raise a number in the baseline by hand.

Two bugs reached the owner live on 2026-11-15 because of rules 2 and 8: Studio
sent the platform `mac` where the gateway takes `macos` (a string where an enum
belonged), and the flow editor did `maxperm as String?` on a value the spec
allows to be a number (untyped decoding). Both compiled, both passed the tests.

---

## 1. No `unawaited` around a dispatch

**Rule.** `unawaited(dispatch(…))`, `unawaited(dispatchAndWait(…))` and
`unawaited(store.dispatch…)` are not written anywhere. A callback that starts
work calls `dispatch(SomeAction())` and returns. If the screen must show that
the work runs, the action has `WaitingAction` and the connector reads
`isWaitingForType<SomeAction>()`. If two steps must run in order, they are one
action whose `reduce` awaits each step — the sequence lives in the action, not
in the connector.

**Why.** `unawaited(dispatchAndWait(x))` asks for a future and then throws it
away: it only hides the wait. On the local demo every reply comes in
milliseconds, so nothing shows. With a remote broker the same code gives a
button with no progress state, a second click that sends the request twice, and
replies that land out of order (seen 2026-11-14: `doc` replies out of order left
a task `running` for good). The fix is to model the wait, not to hide it.

```dart
// bad — app/lib/connectors/assistant_page_connector.dart
onMode: (m) => unawaited(dispatchAndWait(StageAgentParamAction.mode(m))),

// good — the action carries its own wait state; the connector starts it
onMode: (m) => dispatch(StageAgentParamAction.mode(m)),
isStaging: isWaitingForType<StageAgentParamAction>(),
```

```dart
// bad — business/lib/dependencies.dart: five reloads, none observable
unawaited(store.dispatchAndWait(RetrieveLinksAction()));
unawaited(store.dispatchAndWait(RetrievePackagesAction()));

// good — one action that owns the reload and awaits its parts
class ReloadSiteAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    await Future.wait([
      dispatchAndWait(RetrieveLinksAction()),
      dispatchAndWait(RetrievePackagesAction()),
    ]);
    return null;
  }
}
// and the caller: dispatch(ReloadSiteAction());
```

A service that must not block (a stream listener, a timer) dispatches with
`dispatch(…)`; it never wraps it.

**Check.** `unawaited-dispatch` in `app/lib`, `business/lib`, `ui/lib`.

## 2. Enums, not strings

**Rule.** A value from a fixed set is an enum. A wire string becomes an enum
once, at the decode boundary (rule 8), through the enum's own
`fromWire`/`fromName`, and the enum is used from there on. `switch` arms on
string literals (`'mac' =>`, `case 'write':`) are not written outside that
boundary. An enum that crosses the wire has its wire name in the enum
(`final String wire;`), as `wyrm_core`'s `Perm`, `Quality`, `TypeCode` do.

**Why.** A string switch compiles when the value is misspelt, when a case is
missing, and when the other side renames a value. The `mac`/`macos` bug was
exactly this. An enum switch is exhaustive: the compiler names the missing case.

```dart
// bad — app/lib/common/unlock.dart
String unlockStore(String platform) => switch (platform) {
  'macos' => S.current.unlockStoreMac,
  'windows' => S.current.unlockStoreWindows,
  _ => '',
};

// good — the platform is an enum with its wire name; the switch is exhaustive
enum DevicePlatform {
  macos('macos'), windows('windows'), ios('ios'), android('android');
  const DevicePlatform(this.wire);
  final String wire;
  static DevicePlatform? fromWire(String s) =>
      values.where((p) => p.wire == s).firstOrNull;
}
```

**Check.** `string-case` in `app/lib`, `business/lib`, `ui/lib` (decode
boundary excepted, rule 8).

## 3. Each package owns its types; a connector maps, it does not compute

**Rule.**
- `models` holds the domain: freezed models and domain enums. It knows nothing
  of colours, icons or text.
- `ui` holds what is drawn: widgets, their render models (`…Vm`), and **its
  own enums**. A `ui` enum is an enhanced enum that carries what drawing needs:
  its tone, its icon, and its label (rule 5).
- `app` joins them. The mapping from a domain enum to a `ui` enum is one
  exhaustive `switch` in a mapper extension in `app/lib/mappers/`, not inline
  in a connector. A connector's `fromStore` reads selectors, calls mappers and
  builds render models — it does not filter, sort, aggregate, parse or format.
  Anything computed from state is a selector in `business`.
- A connector file over 400 lines is a sign that one of the above leaked into
  it.

**Why.** Today a domain enum is matched to a colour in one connector, to a
label in another and to an icon in a third, and the 20 connectors hold 14 344
lines. The same mapping is written several times and drifts. And `fromStore`
runs on every dispatch: work done there is redone on every dispatch in the
app.

```dart
// bad — a connector decides the colour and the text of a state, inline
tone: switch (task.state) {
  'running' => Tone.warn,
  'done' => Tone.good,
  _ => Tone.neutral,
},
label: switch (task.state) { 'running' => S.current.running, … },

// good — ui/lib/<family>/task_badge.dart owns the drawn enum
enum TaskBadge {
  running(Tone.warn, Icons.sync),
  done(Tone.good, Icons.check),
  failed(Tone.bad, Icons.close);
  const TaskBadge(this.tone, this.icon);
  final Tone tone;
  final IconData icon;
  String get label => switch (this) {        // rule 5: text in ui
    running => S.current.taskRunning,
    done => S.current.taskDone,
    failed => S.current.taskFailed,
  };
}

// app/lib/mappers/task_mappers.dart — one exhaustive map, used everywhere
extension TaskStateBadge on TaskState {
  TaskBadge get badge => switch (this) {
    TaskState.running => TaskBadge.running,
    TaskState.done => TaskBadge.done,
    TaskState.failed => TaskBadge.failed,
  };
}

// the connector: badge: task.state.badge,
```

**Check.** `connector-lines` (lines per connector file) and the checks of rules
2, 5 and 8, which are what a fat connector is made of.

## 4. No `BuildContext` in connectors or in `business`

**Rule.** `BuildContext` appears in `ui` widgets and in `app` pages and dialogs
that draw. It does not appear in a connector's `_Factory` or `_Vm`, in a mapper,
in an action, a selector or a service. A connector that needs something from
the context (a theme colour, a size, a localization) is asking for a value that
belongs in `ui` (rules 3, 5, 6).

**Why.** A view-model built from a context is rebuilt when the context changes,
not when the state changes; it cannot be tested without a widget tree; and it
ties `business` to Flutter's widget layer.

**Check.** `context-in-connector` in `app/lib/connectors`, `app/lib/mappers`
and `business/lib`.

## 5. Text belongs to `localization` and `ui`, not to connectors

**Rule.**
- `localization` is the one place text is defined: the `.arb` files and the
  generated `S`.
- `ui` resolves text. A widget's own words come from `S.current` in the widget.
  A `ui` enum's label is a getter on the enum (rule 3). A formatted value — a
  count, a date, a duration, a size, an age — is passed to `ui` **as a typed
  value** (`int`, `DateTime`, `Duration`) and formatted there, by a formatter
  in `localization` or `ui` (`Formats.bytes(n)`, `Formats.age(d)`), not as a
  ready string.
- A connector does not call `S.current`. It passes enums, numbers, times and
  domain text (a node's name, a user's name, a message from the broker) — never
  a sentence built from the locale.
- This replaces the older rule "content arrives resolved, in the connector"
  in `data-driven-widgets`.

**Why.** 1 426 `S.current` calls sit in connectors today. The same sentence is
built in several connectors, a language switch must rebuild every view-model,
and no widget test can check a label without a whole store.

```dart
// bad — a connector builds the sentence
subtitle: S.current.unlockDevicesCount(devices.length),

// good — the connector passes the number; ui says it
// connector:  deviceCount: devices.length,
// widget:     Text(S.current.unlockDevicesCount(vm.deviceCount)),
```

**Check.** `l10n-in-connector`: `S.current` and `S.of(` in `app/lib/connectors`,
`app/lib/mappers` and `business/lib`.

## 6. Tokens, not numbers

**Rule.** Sizes, gaps, radii, font sizes, durations and colours come from the
theme: `AppSpacing`, `Gaps`, `Insets` (`ui/lib/theme/spacing.dart`),
`AppRadii` (`radii.dart`), the text styles of `typography.dart`, `Motion`
(`motion.dart`) and `context.colors`. A number in a `fontSize:`, an
`EdgeInsets`, a `SizedBox(width:/height:)`, a `BorderRadius`/`Radius.circular`
or a `Color(0x…)` is written only inside `ui/lib/theme/`. A value the design
needs that has no token gets a token first — in the theme, named by what it is
for.

**Why.** `spacing.dart` and `radii.dart` exist, and 486 `fontSize:` numbers and
314 `EdgeInsets` numbers bypass them. A design change is then a search through
every file, and two screens never quite line up.

```dart
// bad
padding: const EdgeInsets.only(top: 12),
style: TextStyle(fontSize: 12, color: c.text4),

// good
padding: Insets.top.sm,
style: AppText.caption.copyWith(color: c.text4),
```

When you swap a literal for a token of the same value, goldens must stay
byte-identical. Snapping a value to a different token is a visible change: do
it in its own commit and look at every golden PNG it changes.

**Check.** `number-literal` in `ui/lib` (except `ui/lib/theme/`) and
`app/lib`.

## 7. Callbacks have shared types

**Rule.** A view-model does not declare its own function type field such as
`final void Function(String key, bool add) onPoint;`. A value and its change is
`FieldVm<T>`; a pick from data is `ChoiceVm<T>`; a toggle of one item in a set
is `ToggleVm<T>`; an action on one row is `RowAction<T>`; anything else that
recurs gets its own named type in `ui/lib/models/value_changed.dart` (or a
sibling file there) — with its `props` rule written once — before a second
view-model needs it.

**Why.** 55 hand-written `Function(…)` fields in connectors today: each one
decides its own equality (usually wrongly, see `data-driven-widgets`), its own
null meaning, and its own parameter order.

```dart
// bad
final void Function(String key, bool add) onPoint;

// good — value_changed.dart
final class ToggleVm<T> extends Equatable {
  const ToggleVm({required this.selected, required this.onToggle});
  final ISet<T> selected;
  final void Function(T item, {required bool on}) onToggle;
  @override
  List<Object?> get props => [selected];
}
// the view-model: final ToggleVm<String> points;
```

**Check.** `ad-hoc-callback`: `Function(` fields in `app/lib/connectors` and
`ui/lib` (except `ui/lib/models/`).

## 8. One typed decode boundary

**Rule.** A wire `Value` (`VMap`, `VStr`, …) becomes a typed Dart value exactly
once: in a decoder for that shape. A decoder is a `fromValue` factory on the
model or a function in `business/lib/wyrm/decode/`, it returns a typed model or
a typed failure, and it has a test — against `spec/fixtures` when the shape is
in the spec. Wire-level shapes shared with other clients belong in
`dart/wyrm_client`. Downstream of the decoder there is no `Value`, no
`Map<Object?, Object?>`, no `Map<String, Object?>` for wire data, no
`as String?`/`as int`/`as Map` cast and no `toDart(…)`. The helpers in
`business/lib/wyrm/mappers/values.dart` (`str`, `text`, `integer`, …) may be
used inside decoders only, and shrink as decoders replace them.

**Why.** `business/lib/wyrm` is 8 831 lines in 39 files, much of it reading
loose maps field by field with helpers that turn any shape into `null`. A field
renamed on the broker, or a value the spec allows in two forms, becomes a silent
null or a cast exception at the screen (`maxperm`, 2026-11-15), far from the
cause. A typed decoder fails at the edge, with the field's name, in a test.

```dart
// bad — app/lib/connectors/flow_editor_page_connector.dart
final Map<Object?, Object?> m => m['maxperm'] as String?,

// good — decoded once, typed from there on
final class FlowPermissions {
  const FlowPermissions({required this.maxperm});
  final Perm? maxperm;
  static FlowPermissions fromValue(Value v) => switch (v) {
    VMap(:final v) => FlowPermissions(maxperm: switch (v['maxperm']) {
      VInt(:final v) => Perm.fromCode(v),
      VStr(:final v) => Perm.fromName(v),
      _ => null,
    }),
    _ => const FlowPermissions(maxperm: null),
  };
}
```

**Check.** `untyped-wire` in `app/lib` and `business/lib` outside
`business/lib/wyrm/decode/` and `business/lib/wyrm/mappers/values.dart`.

---

## Before you call a Studio change done

1. `dart run tool/check_rules.dart` — no count above the baseline.
2. `frx doctor`, `flutter analyze`, `flutter test` in every package you touched.
3. If you removed violations: `dart run tool/check_rules.dart --lower`, and
   commit the baseline with the change.
