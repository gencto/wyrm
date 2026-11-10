# Errors

Boards (canvas row "Errors"): `ErrorKit` (the rules), `ErrorDialog` (clickable Details) with `ErrReach`, `ErrInput`, `ErrBusy`, `ErrGone`, `ErrBroker`, `ErrStudio`; `ErrorQuiet` (clickable counter) with `ErrorProblems`; `ErrorPanel` with `ErrorFatal`. The boards win for what is visible; this spec says where each error comes from, which surface takes it, and what to change in the code.

Replaces the Material `AlertDialog` that `ExceptionDialog._defaultUserExceptionDialog` shows for every `UserException`, the grey/red `ErrorWidget`, and the plain `Colors.black26` snack bar.

## 1. One error model

Today a broker refusal becomes `UserException(what, reason: '${status.name}: $message')` (`business/lib/wyrm/calls.dart`): the status is flattened into text and lost. Keep it as data.

- New model in `models` (`frx add-model studio_error`, a freezed class): `title` (what did not happen), `message` (the broker's words, as they came), `status` (`wyrm_core` `Status`, null for Studio's own faults), `kind` (enum below), `key` (full key, nullable), `call` (`deploy`, `set`, `subscribe`, `history`, …), `site`, `at` (local time), `quiet` (bool), `retry` (nullable: the action to dispatch again), `field` (nullable: the parameter `invalid_parameter` names), `report` (Studio faults only: type, first line, stack).
- Enum `ErrorKind` (`frx add-enum error_kind`): `rights`, `reach`, `input`, `busy`, `gone`, `broker`, `studio`.
- It travels as a `UserException`, so the store's existing path (observer, `onOk`/`onCancel`, `withDialog`) stays: a subclass `StudioException extends UserException` in `business` holding the `StudioError`, with `title` as the message and `message` as the reason. (If async_redux's `UserException.code` can hold an object in the version in use, carrying it there is equivalent; check before choosing.)
- `call()` in `calls.dart` builds it from `WyrmException` (status, message) plus what the caller knows (`what` → title, key, call). `requireSuccess` builds `broker` errors. `errors.dart` `translateError` builds `studio` errors (no status) with the report.

### Status → kind
| Kind | Statuses | Tone (token) | Icon | Main button | Retry |
|---|---|---|---|---|---|
| rights | `permission_denied` | `warn` / `warnTint` | lock | OK · secondary `See my access` (Access › me) | no |
| reach | `timeout`, `disconnected`, `not_available`, `closed` | `warn` / `warnTint` | wifi off | `Try again` · secondary `Close` | by hand only |
| input | `invalid_parameter`, `invalid_message`, `out_of_range` | `emberSoft` / `emberTint` | pencil | `Back to the form` | no |
| busy | `busy`, `rate_limited`, `resource_exhausted` | `text3` / `ground4` | timer | `Try again in N s` (disabled while counting) · `Close` | once by itself after N s (N = 4, or the broker's hint) |
| gone | `not_found`, `not_supported` | `text3` / `ground4` | search minus | `Refresh` · `Close` | no |
| broker | `internal_error`, and `requireSuccess` failures | `bad` / `badTint` | server x | `Open the log` (System › Log, time filled) · `Close` | no |
| studio | anything not from the broker | `bad` / `badTint` | window ! | OK | no |

Statuses `ok`, `initializing`, `refreshed` never reach here.

## 2. Where an error goes
| Surface | When | Board |
|---|---|---|
| Inline under the field | A value breaks a rule Studio knows from `~meta.cfg` (required, min/max, enum, pattern) or from the screen (a name). Checked as the user types; nothing is sent. | `ErrorKit` §5 |
| Dialog | A call the user started and waits for: Save, Deploy, Install, Apply (Review and apply), a set, an action run. | `ErrorDialog`, `Err*` |
| Toast + mark + Problems | Something Studio did on its own: reads, refreshes, preloads, live streams, history fetches. Every `quiet` action (`ReduxAction.quiet`, `withDialog(false)`) lands here. | `ErrorQuiet`, `ErrorProblems` |
| Panel card | A widget threw while building (`ErrorWidget.builder`). | `ErrorPanel` |
| Start screen | Studio cannot start: its own storage does not open. | `ErrorFatal` |

Rules: validation errors (`Give the link a name.`, `Type the user and the password.`, `The parameters must be one JSON object.`, `Bring a package first.`) become inline errors, not dialogs. One dialog at a time: an error that arrives while one is open goes to Problems only and raises the counter.

## 3. Dialog (`ErrorDialog`)
Replace `_defaultUserExceptionDialog` with `onShowUserExceptionDialog:` passed to `ExceptionDialog` in `app.dart`, which shows a new `ui` widget `ErrorDialog` (`frx add-widget error_dialog --dir dialogs`) fed an `ErrorDialogVm`. A plain `UserException` (no `StudioError`, e.g. from a package) is shown in the same card with its title and reason, kind `studio` styling, and OK.

Layout (board, 1× sizes):
- Scrim `rgba(6, 8, 9, 0.66)` over the whole window. Card max 520 wide, radius 14, fill `ground2`, line `line2`, shadow `0 24 64 rgba(0,0,0,.55)`.
- Header, padding 22/24/0: tone square 40, radius 10, icon 20 in the tone; title 18/600; under it the key and call in mono 12 `text4`: `wy/plant/dataflows/pump-control › deploy`. Close button 32 at the right.
- Body, padding 16/24: label 12 `text4` (`The broker said`; `Studio waited 10 s` for a timeout without a message; `What happened` for Studio faults), then the message in a block (fill `ground0`, line `ground4`, radius 8, padding 12/14, 14/1.55 `text1`), selectable.
- `WHAT YOU CAN DO` (12/600, tracked, `text4`) and one or two lines with a tone dot: from the kind, specific where the caller knows more (role name, field, link).
- Reach on a write (`set`, `deploy`, any `~act` the screen marks as a write): the amber note `A write that timed out may still have been applied. Check the value before you send it again.` (fill `warnTint`, line `warnLine`, text `warn`).
- `Details` disclosure (closed by default; open for `broker` and `studio`): chip with the status name in the tone; rows `Status` (`permission_denied (0x21)`), `Call`, `Site`, `As` (user and role), `Gateway`, `Time`. For `studio`: `Error`, `In`, `Screen`, `Studio` (version, OS), `Time`, `Report` (`the stack trace is in the copied report only`).
- Footer, padding 14/24/20: `Copy details` (ghost, left; `Copy report` for `studio`), secondary (outlined, `line3`), primary (fill `ember`, text `onEmber`; disabled = `ground4` / `text4` with a live countdown for busy).
- Keys: focus starts on the primary button; Esc = Close (= `onCancel` if set, else `onOk`, as today); Enter = primary; Tab stays inside. Role `alertdialog`, title and body linked.

Copy details (plain text): title, key › call, status (code), message, site, user (role), gateway URL, time, Studio version and OS. Never values, arguments, tokens or passwords. `Copy report` adds the Dart type, message and stack trace.

Primary actions:
- `Try again`: dispatches the same action again (`retry` in the model); the dialog closes first.
- `Back to the form`: closes, puts the message under `field` (when the broker named one) and focuses it.
- `Refresh`: dispatches the screen's own load action.
- `Open the log`: navigates to System › Log with the time set to the error's time.
- `See my access`: navigates to Access with the current user selected.

## 4. Quiet errors (`ErrorQuiet`, `ErrorProblems`)
- State: a `problems` substate (`frx add-substate problems`): list of `StudioError` (newest first, at most 200, kept until Studio quits, never persisted), and `unread` count. Every error, shown in a dialog or not, is added; a dialog's entry is marked `shown as a dialog`.
- Top bar: a pill `<n> problems` (`n` = unread) with a `bad` dot when any unread is `broker`/`studio`, else `warn`; hidden at 0. It opens the drawer and clears `unread`.
- Drawer: right side, 400 wide, fill `ground1`, shadow `-24 0 48 rgba(0,0,0,.4)`; heading `Problems · this session`, `Clear all`, close; a sentence on what lands here; one card per error (dot, title, time, key › call in mono, `status: message`, links `Details` (opens the dialog for it, read only, no retry for writes), `Try again` when it has `retry`).
- Toasts: bottom right, 380 wide, at most 3 stacked (older ones fold into the counter), fill `ground3`, line `line2` (the tone's line for a stream that is down), shadow `0 12 32 rgba(0,0,0,.45)`: tone square 28, title, one line, `Details`, `Try again` if any, lifetime on the right (`hides in 8 s`; `stays until edge is back` for a dropped stream, removed when the stream reopens). Replaces `StyledSnackbar` for errors; successes keep a toast of the same shape in `good`.
- Mark on the thing that failed: a row whose value read failed shows the chip `read failed` (`badTint` / `badText`) with the tooltip `Reading the value failed: <status>. Details in Problems.`; its value shows `—`. Same for history (`history unavailable`).
- The existing `OfflineBanner` stays for the gateway socket itself; streams of one site going down are a toast, not a banner.

## 5. A part failed to draw (`ErrorPanel`)
- Set `ErrorWidget.builder` in `main.dart` (release and profile; debug keeps Flutter's red screen so developers see it) to a `ui` widget `PanelFault` (`frx add-widget panel_fault --dir alerts`): dashed `badLine` card in `ground2`, tone square, `The <panel> could not be drawn`, one sentence (`The rest of Studio still works; values and actions elsewhere are not affected.`), the error's first line in mono with the panel and time, buttons `Draw it again` (rebuilds that subtree: wrap each region — tree, inspector, editor canvas, drawer — in a `FaultBoundary` that keys its child and bumps the key) and `Copy report`.
- The panel name comes from the nearest `FaultBoundary(name:)`; without one: `This part`.
- `FlutterError.onError` and `PlatformDispatcher.instance.onError` add a `studio` problem (quiet) and log it; they never open a dialog.

## 6. Studio cannot start (`ErrorFatal`)
- When `KeyValueStorage` (sembast, `database.db`) does not open, `run_env.dart` shows a minimal app with this screen instead of the router: the mark with the head in `bad`, `Studio could not start`, a sentence saying the brokers are not affected, a details box (`Error`, `File`, `Studio`), buttons `Start with fresh settings` (moves `database.db` to `database.db.broken`, then starts normally), `Copy report`, `Quit`; the note on the kept file under them.
- No other condition shows this screen: an unreachable gateway is the log-in screen's job (`login.md`).

## 7. Words
- Title = what did not happen, with its object, from the action: `You can’t deploy pump-control`, `edge did not answer`, `The broker refused these parameters`, `plant is busy, the install did not start`, `pump-control is not there anymore`, `Installing modbus 0.4.2 failed on plant`, `Studio could not open this flow`. Never `Error`, `Something went wrong` or `Try again later` alone (`S.somethingWentWrong` / `S.tryAgainLater` go).
- The broker's message is shown as it came. Studio adds one sentence only when the status has no message (timeouts).
- Every string in `localization/lib/l10n/intl_en.arb` and `intl_uk.arb` (docs/studio.md), the kind lines as messages with placeholders; the broker's message is never translated.

## 8. Found in the app (2026-11-10)
- `ExceptionDialog._defaultUserExceptionDialog`: Material `AlertDialog`, `TextButton`s `Cancel`/`OK`. Replace as §3.
- `calls.dart` flattens `WyrmException` into `reason: 'status: message'`. Carry `StudioError` in `code` (§1).
- `errors.dart` maps every non-`UserException` to `somethingWentWrong` / `tryAgainLater`, dropping what happened. Build a `studio` error with the report (§1, §7).
- `ReduxAction.quiet` turns errors into `withDialog(false)` and they vanish (only logged). Route them to Problems (§4).
- `StyledSnackbar`: `Colors.black26`, Material type, centred. Replace for errors (§4).
- No `ErrorWidget.builder`, no `FlutterError.onError` / `PlatformDispatcher.onError` (§5).
- Storage open failure is unhandled at start (§6).
- Validation thrown as dialogs: `install_link_action.dart` (name, package), `log_in_action.dart` (`Type the user and the password.`), `update_link_params_action.dart` (JSON). Move to inline (§2).

## 9. Checklist
- [x] Every broker refusal shows its kind, title, key › call, the broker's message, the right buttons; Details shows status and code. (`call` / `listOf` / `metaOf` / `invokeAll` / `askAll` and `Action.wrapError`; a refusal thrown raw by the client is wrapped the same way, without a key.)
- [x] Reach on a write shows the may-have-been-applied note; Busy counts down and retries once. (*Try again* needs `Action.again()`: the Retrieve actions and the link, node, flow, profile, quarantine and peer writes have it; an action without it gets OK.)
- [~] Back to the form focuses the named field with the message under it. Done for the node action form (`runNodeAction`: `ActionForm.errors` / `focus`, `refusedField`). The other forms (link grant, add upstream, access) close the dialog and leave the form as it was; the field is named in the dialog.
- [x] Copy details never contains values, args, tokens or passwords (test with a `set` of a secret field). A `StudioError` holds no value and no argument; its message, the gateway URL and the stack are redacted.
- [x] Quiet errors: toast, mark on the row, entry in Problems; counter and drawer as the board. (The mark is on the points table and on the History tab; the tree and the inspector do not show it yet.)
- [x] A throwing panel shows `PanelFault`; `Draw it again` rebuilds only it. (Boundaries: Explorer tree, workspace, inspector; flow editor canvas; every workspace tab; the Problems drawer.)
- [x] Unreadable `settings.db` shows the start screen; fresh settings keep the old file. (The file is `settings.db`, kept as `settings.db.broken`; the board and §6 say `database.db`. It is opened with sembast's `DatabaseMode.create`: the default mode deleted an unreadable file without a word.)
- [x] Validation errors are inline, never dialogs. (`LogInAction` and `InstallLinkAction` no longer throw: their pages validated already. Edit params checks the JSON as it is typed.)
- [x] Goldens: one per frame (`ErrorDialog`, `ErrReach`, `ErrInput`, `ErrBusy`, `ErrGone`, `ErrBroker`, `ErrStudio`, `ErrorQuiet`, `ErrorProblems`, `ErrorPanel`, `ErrorFatal`), dark and light. (`ui/test/goldens/errors_test.dart`, plus `error_dialog_details`; the reference PNGs in `screens/` are renders of the board sources, not canvas exports.)

Not done, or decided here **(proposed)**:
- [~] *Open the log* goes to System › Log and reads it again; it does not fill a time, since `get_log` takes no time and the newest lines are the ones around the failure.
- **(proposed)** A status Studio does not know (user-defined `0x40–0x4F`, an unknown code) is kind `broker`.
- **(proposed)** An error the screen shows itself (`withDialog(false)`: the log-in page) is a line in Problems without a toast; a key the user may not read is a mark and a line, without a toast.
- **(proposed)** The same failure again (kind, status, key, call, title) replaces its line in Problems instead of adding one.
- **(proposed)** ⌘/Ctrl+C in the dialog copies the details; a tap on the scrim does nothing.
- **(proposed)** The busy wait is 4 s: spec 04 carries no hint.
- **(proposed)** `shown as a dialog` and the toast's lifetime use `muted` (the board's `#6B747A` is not a token).
- Titles of a call Studio has no verb for read `run <call> on <thing>`.
