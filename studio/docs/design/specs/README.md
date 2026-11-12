# Screen specs

A spec turns one screen of the design canvas into rules that can be checked: regions and sizes, every label word for word, every control and what it calls, selection, menus, copy, keyboard, and every state. It exists because a board is a picture with sample data: it does not say what happens on Shift-click, what is copied, or what shows when a list is empty, and a picture read as HTML loses sizes and details on the way to Flutter.

## Which wins
1. The board (its PNG in `../screens/`, else its source in `../canvas/`) for anything visible: layout, sizes, colours, words, order.
2. This spec for behaviour and for what the board does not show.
3. `docs/studio.md` for wiring and broker calls. Where it disagrees with a board or a spec, it is wrong; fix it in the same pull request.

A rule marked **(proposed)** is not in the design; it was decided here to close a gap. Change it if the owner decides otherwise.

## The loop for one screen (Claude Code, in `studio/`)
1. Export the screen's artboards as PNG from the canvas into `studio/docs/design/screens/<Board>.png` (1440×1000, 2×). Without PNGs the source in `canvas/` is the reference, which is weaker.
2. Prompt:
   > Bring the Explorer to `docs/design/specs/explorer.md` and `docs/design/screens/Main.png`. Go through the spec's checklist item by item. Render the golden of each frame, open it next to the reference PNG, list every difference you can see (layout, sizes, words, missing controls), fix, render again; stop when only font rasterisation differs. Then fix every item under "Found in the app". Use frx for new artifacts, `frx doctor`, `flutter analyze`, `flutter test`. Do not commit.
3. Review the diff and the goldens yourself, then commit and open the pull request.

One screen per pull request. The golden of every frame is committed with it.

## Specs
| Screen | Spec | Boards |
|---|---|---|
| Log in | [login.md](login.md) | `Login`, `LoginSigning`, `LoginWrong`, `LoginUnreachable`, `LoginWelcome` |
| Explorer | [explorer.md](explorer.md) | `Main`, `Actions`, `ActionDetail`, `PropertySheet` |
| Flow editor | [flow-editor.md](flow-editor.md) | `FlowBind`, `FlowTree` |
| System | [system.md](system.md) | `System`, `SystemAvail`, `SystemAvailLag`, `SystemAvailNone`, `SystemLog`, `SystemMaint` |
| Errors | [errors.md](errors.md) | `ErrorKit`, `ErrorDialog`, `ErrReach`, `ErrInput`, `ErrBusy`, `ErrGone`, `ErrBroker`, `ErrStudio`, `ErrorQuiet`, `ErrorProblems`, `ErrorPanel`, `ErrorFatal` |
| Trend chart | [trend.md](trend.md) | `Trend`, `TrendHover`, `TrendZoomed`, `TrendPinned`, `TrendGap`, `History` |
| App icon | [app-icon.md](app-icon.md) | `AppIcon` |

The other screens follow the same template: Regions, Words, Controls, Selection and menus, States, Checklist, Found in the app.
