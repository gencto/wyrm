# Log in

Boards: `Login` (clickable: Log in plays the whole sequence), `LoginSigning`, `LoginWrong`, `LoginUnreachable`, `LoginWelcome`. Source: `../canvas/Login.dc.html` (the four frames mount it with `stage=…`). The page replaces the template's `LogInPage` layout; its fields and `LogInAction` stay.

## 1. Regions

| Region | Size | Background |
|---|---|---|
| Hero (left) | flex 1 1 560, min height 420, padding 40 × 48, right border `#1D2226` | radial gradient, ellipse 120 % × 90 % at 20 % 30 %: `#1A1511` → `#0E1113` at 60 % |
| Form panel (right) | flex 0 1 520, padding 40 × 32, content centred, max width 420 | `#0E1113` |

Below 1080 px wide the hero goes on top (height 420) and the form under it; below 700 px the hero is 220 high with the mark and the logo only, headline 28 **(proposed)**.

## 2. Hero
Top to bottom, space-between:
1. Logo: mark 44 × 26 (the five circles of `ui/assets/svg/icons`' logo), `WYRM` Unbounded 700 18 letter-spacing 0.08 em, `Studio` 15 `#A3ABAF`.
2. The large mark (§4.3, 220 × 130), then the headline `Every device, link and site` / `in one living tree.` (40/600, line height 1.12, letter-spacing −0.02 em; the second line `#F3A766`), then `Browse what your brokers hold, add links, let devices in, connect sites and build flows. Nothing changes until you apply it.` (16, line height 1.6, `#A3ABAF`), gap 22, max width 520.
3. Legend (12 `#8E979C`): teal 14 × 2 line `values flowing` · ember line `commands` · `The animation is decoration; it stops when the system asks for less motion.`

Behind everything, the network (§4.1, §4.2), painted in a 900 × 900 space scaled to cover the hero (`BoxFit.cover`, centred).

## 3. Form
Gap 22 between the blocks; fields gap 16; field label 13 `#C5CBCE`, gap 8 to the field.

1. Title `Log in` (26/600), under it `to a broker’s gateway. Your role there decides what you can change.` (`#A3ABAF`).
2. **Gateway**: field 46 high, radius 10, fill `#161A1D`, border `#2F373D`; a status dot 8 with a 4 px halo (teal `rgba(108,196,176,0.15)` / coral `rgba(224,122,95,0.15)`), the URL in mono 13, a spinner (§4.8) while it is being checked. Under it a status line (12): `<host> · answered in <n> ms` (`#8E979C`) or `No answer from <host>` (`#F0A28D`). Under that, the **recent gateways** as chips (28 high, radius 14, mono 12, a 6 px dot with the last result; the current one ember `#F6C59A` on `#1E1813`, border `#5A3E25`); a click fills the field.
3. **User**: 46 high, radius 10, 15 px text.
4. **Password**: 46 high, a show/hide eye button 36 × 36 inside on the right; hidden text spaced 0.2 em.
5. `Remember the gateway and user on this computer` (checkbox 16, ember).
6. **Log in**: 50 high, radius 10, ember `#E8893A`, ink `#0E1113` 16/600; while signing in: fill `#C9772F`, disabled, the crawl loader (§4.4) before the label `Signing in…`, and the bar (§4.5) along the bottom edge (3 high, `rgba(14,17,19,0.45)`).
7. While signing in, under the button, three steps (13): `Reaching <host>` · `Checking user and password` · `Reading your role and sites`: done = teal check, now = ember spinner and `#ECE9E1`, waiting = grey ring and `#5A6168`.
8. Footer (top border `#1D2226`, 12 `#8E979C`): lock icon teal + `TLS · certificate of the <site> CA` (when the gateway is `https`), `Add a standby gateway` (underlined; opens a second URL field; when set, `Standby: <host:port>`), and at the right `Studio <version> · <language>` — the name of the language in use, in that language (`Studio 1.0 · English`). **Owner decision 2026-11-08:** as the board, the page has no language or theme switchers; they leave the log-in page. **Decided 2026-11-09 (owner):** they live in the account menu of the Studio top bar (the avatar: user and role, `Language` English / Українська, `Theme` dark / light, `Log out`; `docs/studio.md` §7.1); until a user logs in, the language and the theme stay as persisted. The board's line wraps at 420 px: the TLS note and the standby link on the first line, the version at the right of the second.

## 4. Motion
All values from the board's CSS. Use one `AnimationController` per loop, `vsync` from the page; stop every loop when `MediaQuery.disableAnimationsOf(context)` is true (static frame: packets hidden, stars at 0.5, mark at rest, the loader dots still, the bar hidden, the step spinner a static ring).

| # | What | Duration | Curve | Details |
|---|---|---|---|---|
| 4.1 | **Packets** on the network edges | 4.8 s; every odd edge 7.5 s; every third edge starts 2.4 s in | linear, repeat | Each edge is a quadratic curve from node a to node b with control point (mid x, mid y − 40). A packet is a 3 px piece of the path, round caps, width 2.4; packets repeat every 160 px along the path and move 160 px per cycle (`PathMetric.extractPath(s, s + 3)` for `s = (k·160 + t·160) mod length`). Colour: teal, every fourth edge (`i % 4 == 3`) ember. The edge itself: `#2A2F33`, 1.2. |
| 4.1 | Nodes | — | — | Nine nodes at (150,640) (300,560) (470,610) (620,520) (770,600) (380,740) (560,760) (700,720) (240,780); edges 0–1, 1–2, 2–3, 3–4, 1–5, 5–6, 6–7, 2–6, 0–8, 8–5, 4–7. A node: ring r 8 stroke 1.6 on `#13171A` + core r 3; node 2 is the hub: r 11, core 4, ember; others: `i % 3 == 0` grey `#3A4249`, else teal. |
| 4.2 | **Stars** | 3.6 s | ease-in-out, repeat, reverse | 34 dots, `#252B30`, r 0.8–2.2, opacity 0.25 ↔ 0.9, each with its own delay 0–3.6 s. Seeded (LCG `seed = (seed·9301 + 49297) mod 233280`, seed 7) so the picture is the same every time. |
| 4.3 | **Mark: spine** | 1.6 s, once on open | ease-out | Path `M20 85 C45 50 65 45 70 45 S105 25 115 30 S155 40 165 55 S190 95 200 100`, stroke `#5A3E25` 2, drawn from 0 to full length. |
| 4.3 | **Mark: circles** | 3.2 s | ease-in-out, repeat | Circles (20,85,r14) (65,45,r17) (115,30,r20 filled) (165,55,r17) (200,100,r14), rings stroke 5 ember on `#0E1113`; each scales 1 → 1.18 → 1 and opacity 0.9 → 1 → 0.9 about its centre; delays 0, 0.25, 0.5, 0.75, 1.0 s. |
| 4.4 | **Crawl loader** (button and Welcome) | 1.1 s | ease-in-out, repeat | Five dots in a row, bottom-aligned; keyframes 0 %: y 0, scale 1, opacity 0.4 · 35 %: y −6, scale 1.28, opacity 1 · 70 %: y 0, scale 1, opacity 0.7 · 100 % = 0 %; delays 0, 0.11, 0.22, 0.33, 0.44 s. Button: sizes 6, 7, 8, 7, 6, gap 5, `#0E1113` filled. Welcome: 14, 17, 20, 17, 14, gap 10, rings 3 px ember, the middle one filled. One widget `WyrmLoader(size: .small | .large)`. |
| 4.5 | **Bar** | 1.4 s | ease-in-out, repeat | A strip 40 % of the track wide moves from −100 % to +250 % of its own width; clipped by the track. Welcome: track 260 × 4 `#1D2226`, strip a gradient transparent → ember → transparent. |
| 4.6 | **Rise** of the form and hero text | 0.6 s, once | cubic (0.2, 0.7, 0.2, 1) | Opacity 0 → 1, y +14 → 0; stagger 80 ms: title, gateway, user, password, remember + button + footer. |
| 4.7 | **Shake** on a wrong password | 0.45 s, once | linear keyframes | x: 0 → −1 (10 %) → 2 (20 %) → −4 (30 %) → 4 (40 %) → −4 (50 %) → 4 (60 %) → −4 (70 %) → 2 (80 %) → −1 (90 %) → 0. |
| 4.8 | **Spinner** | 0.9 s | linear, repeat | A 3/4 arc (`M12 3a9 9 0 1 0 9 9` in 24 × 24), stroke 2.4–2.6, round cap. |

## 5. States and what drives them

| State | Comes from | Shows |
|---|---|---|
| idle | page open | form, gateway status from a probe (§6) |
| signing | `LogInAction` running (`isWaiting`) | §3.6 and §3.7; the step moves on the action's progress: `Reaching` until the gateway answers TCP/TLS, `Checking` until `/api/login` answers, `Reading` until `me()` returns |
| wrong | `/api/login` answers 401 | password border `#5A3328`, the shake, `User or password is wrong. Ask an administrator to reset it; the gateway never sends it by mail.` (13 `#F0A28D`), focus back in the password |
| unreachable | connect error or no answer in 5 s | the alert block above the form (border `#5A3328`, fill `#1C1513`): `Can’t reach this gateway`, the URL and the reason (`connection refused after 5 s`, `timed out`, `certificate is not trusted`), one line of advice, `Try again`, and `Use the standby` when a standby URL is set; the gateway dot and status line coral |
| welcome | login done, Studio preloading (`OpenTreeAction`) | the form fades out (200 ms), then: large loader, `Welcome, <user>`, `Opening the tree of <site>…`, the bar, the **preload steps** (§5.1) drawn as §3.7, and two lines from `me()` and the first list: `<role> on <site> · reaches <sites>` and `<n> links · <n> flows · <n> waiting in quarantine` (only the parts known). Leave for the Studio shell when the preload ends, shown at least 600 ms so it does not flash and at most 5 s |

### 5.1 Preload (owner decision 2026-11-08)
The board's welcome has no step list; the owner asked for one, so that moving between the tree, the flows and the links does not wait on the broker. `OpenTreeAction` reads, one after the other, and the welcome shows each as a step (`login.preload` = the step running, `login.preloadLate` = the steps that did not finish in time):

| # | Step | Reads | Done when |
|---|---|---|---|
| 0 | `Reading the tree of <site>` | live lists of `downstream` (opened in the tree, as before), `dataflows` and `storage` (listed, **not** opened: the tree looks as it did) | each list answered once (`nodes.listed`) |
| 1 | `Reading the flows` | `RetrieveFlowsAction` | it ends |
| 2 | `Reading the flow blocks` | `RetrieveBlockTypesAction` → `flows.blockTypes`, once per session and site; the flow editor opens from it | it ends (skipped when cached) |
| 3 | `Reading the links` | `RetrieveLinksAction` | it ends |
| 4 | `Reading the sites` | `RetrieveSitesAction` (the switcher) | it ends |

Timings: each step waits at most 2 s, the whole welcome at most 5 s (one deadline for all five) and at least 600 ms. A step that runs out of time goes on in the background and its line ends in `· later`, with an open grey ring. When the deadline comes before a step starts, that step and the ones after it start at once and Studio opens without them. Every preload read is quiet: a failure (no rights on `sys`, say) opens no dialog; the workspace that needs the data reads it again when it opens, and that read shows its errors as usual.

## 6. Gateway probe
On open, on a recent chip and on leaving the URL field: a `GET <gateway>/api/me` without a session, timed. A 401 means the gateway is there: `<host> · answered in <n> ms`. Anything else in 5 s: unreachable. The board's line also shows the site and the wyrmd version; a gateway tells those only after login today, so before login show the host and the time (a public `/api/info` would be a gateway change, `docs/studio.md` §10 item 13).

Recent gateways: the last five URLs that logged in, from `storage`; their dots are the last probe result. `Remember` keeps the URL list and the user, never the password. A standby URL is stored with the main one as a comma list and logged in with `WyrmGateway.loginAny`.

## 7. Checklist
- [ ] Split layout with the sizes of §1; stacking below 1080 and 700
- [ ] Hero: logo, mark, headline (two lines, the second ember), text, legend; network behind it
- [ ] Packets, stars, mark spine and circles as §4.1–4.3, from the same coordinates
- [ ] Form words exactly as §3; recent gateway chips; status line with the probe
- [ ] Button loader, bar, three live steps
- [ ] Wrong password: border, shake, message, focus
- [ ] Unreachable: alert, Try again, Use the standby
- [ ] Welcome with the large loader and the five preload steps (§5.1), leaving when the preload ends (≥ 600 ms, ≤ 5 s)
- [ ] Footer: `Studio <version> · <language>` at the right, no switchers (§3.8)
- [ ] Reduced motion: every loop stops
- [ ] Goldens (animations paused at t = 0 and at one fixed time): idle, signing at step 2, wrong, unreachable, welcome
