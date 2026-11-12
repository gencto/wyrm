# Design reference

`canvas/` is a snapshot of the **WYRM Studio design canvas** (Claude Design, version 74, 2026-11-12). The canvas itself is the source of truth; this copy is here so that people and agents working in `studio/` can read every screen and state without access to it.

The boards do not render on their own (they run inside the canvas). Read them as source:

- the markup is the layout, with every colour, size and spacing written out;
- the `<script type="text/x-dc">` block at the end holds each board's data and states (`renderVals()`): lists, labels, which controls are enabled when, what a click changes;
- `data-props` at the top of that block lists the props a board takes (`stage`, `tab`, `shape`, `startStep`, …); a storyboard frame is a small file that mounts a component with one set of props (`<dc-import name="LinkInstall" start-step="2" …>`);
- `canvas.json` places the boards in rows; titles say what each frame shows.

| Row | Boards | Studio |
|---|---|---|
| Log in | `Login` (clickable), `LoginSigning`, `LoginWrong`, `LoginUnreachable`, `LoginWelcome` | `specs/login.md` |
| App screens | `Main` (Explorer), `Flow` (Flows list), `Links`, `Sites`, `Access`, `System` | `docs/studio.md` §7.2–7.7 |
| Details | `Actions`, `ActionDetail`, `History`, `LinkInstall` (Add a link, clickable); `PackageInstall` is an earlier variant, not built | §7.3, §7.4, §7.7 |
| System | `System` (clickable tabs, in the app screens row), `SystemAvail`, `SystemAvailLag`, `SystemAvailNone`, `SystemLog`, `SystemMaint` | `specs/system.md` |
| Flow editor | `FlowBind`, `FlowTree`, `FlowSymbol`, `FlowRepeat` | §7.6 |
| Add a link, official | `AddLinkB00`, `AddLinkO1`–`O4`, `AddLinkB10` | §7.3 |
| Add a link, custom | `AddLinkC1`–`C4b` | §7.3 |
| Who controls what | `LinksRemote`, `LinksQuarantine`, `SitesChainQ`, `SitesStar`, `SitesTwoUp` | §7.2, §7.5 |
| Assistant | `AssistantAsk`, `Assistant` (clickable), `AssistantRun`, `AssistantDone`, `AssistantFailed`, `AssistantRights`, `AssistantDrawer` | §7.8 |
| Design system | `DesignSystem` (tokens, type, components, scrollbars), `Icons`, `PropertySheet` | §6 |
| Trend chart | `Trend` (clickable: tooltip, zoom, marker, brush), `TrendHover`, `TrendZoomed`, `TrendPinned`, `TrendGap`; mounted by `History` | `specs/trend.md` |
| Errors | `ErrorKit`, `ErrorDialog` (clickable) with `ErrReach`, `ErrInput`, `ErrBusy`, `ErrGone`, `ErrBroker`, `ErrStudio`; `ErrorQuiet` (clickable) with `ErrorProblems`; `ErrorPanel` with `ErrorFatal` | `specs/errors.md` |
| GenUI views (page *GenUI views*, experiment) | `GenView` (clickable), `GenViewGenerating`, `GenViewChecks`, `GenViewRefine`, `GenViewKiosk`, `GenCatalog`; project and menu `GenProject`, `GenProjPump`, `GenProjPanel`, `GenProjPhone`, `GenProjPhonePump`, `GenProjKiosk`; style `GenStyle`, `GenStyleLight`, `GenStylePanelLight`, `GenStylePhoneLight`; samples in `genui/` | `specs/genui-views.md` |
| App icon | `AppIcon` (variants, every platform; its images are canvas uploads, `/_blob/<id>`, copied here by name to `canvas/icon/`) | `specs/app-icon.md` |

Each frame is one golden test (`docs/studio.md` §9). When the canvas changes, refresh this folder in the same pull request as the code that follows it.
