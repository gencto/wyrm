# Trend chart

Boards: `Trend` (clickable: hover, drag to zoom, click for marker A, brush window, legend toggles), `TrendHover`, `TrendZoomed`, `TrendPinned`, `TrendGap` (canvas row "Design system", right of App icon), and `History`, which now mounts `Trend` in place of its static chart. The boards win for what is visible; this spec says how it is built, where the data comes from and how every gesture behaves.

One widget for every time chart in Studio: History (watch group trend), Explorer (a point's "View History"), System (router traffic, live ring), and later the Views `Chart` element. Replaces `ui/lib/charts/trend_chart.dart` (`TrendChart`, static min/max labels, no interaction) and the drawing inside `traffic_card.dart`.

## 1. Regions (board `Trend`, 1× sizes)
Card: padding 16, radius 10, fill `ground1`, line `line1`, gap 10. Light theme uses the same tokens; the brush scrim is `ground0` at 62 % in both.

1. **Header row** (wraps): one legend button per series (height 28, radius 6, line `line2`; 16×2 swatch, the key in mono, the label in `text4`; `aria-pressed`; off = opacity 0.45, line `line1`), the `no data` key (dashed `bad` box), then right-aligned the visible range (`Wed 12:30 – 15:55`, mono `text2`), `· 15 min avg` (`muted`), and `Reset zoom` (pill 26, `emberTint` / `emberLine` / `emberSoft`) only while zoomed.
2. **Main plot**: Y labels column 44 wide (mono 11 `text4`, right aligned, the top one carries the unit), 8 gap, plot 240 high. Grid lines at each Y tick (`ground3`), lines 2 px, gaps as a `bad` band (fill 12 %, dashed outline).
3. **Time axis**: 5 labels under the plot, the first left-aligned and with the weekday (`Wed 12:30`), the last right-aligned, a label at midnight also gets the weekday.
4. **Brush** (overview): label `all` (11, `muted`) in the Y column, a strip 56 high (fill `ground0`, line `ground4`, radius 6) with every series of the whole range at 1.2 px, gaps in `bad` 18 %. Outside the window: a scrim (`ground0` at 62 %); the window itself: top and bottom 2 px `ember`, fill `ember` 6 %; two handles 6×28 radius 3 `ember` centred on the edges (hit area 12 wide). Under it 5 time labels (10, `muted`), the last is `now` when the range ends now.
5. **Hint line** (11, `muted`): `Hover for values · drag on the chart to zoom · click to set marker A · drag or resize the window below · double-click resets · ← → move the focused handle`. Hidden below 600 px wide.

## 2. Tooltip
On hover over the plot (pointer, and long-press on touch):
- A vertical crosshair (1 px `muted`) at the bucket under the pointer (snaps to the nearest sample or bucket, never between).
- A dot per shown series on its line: 9 px, fill `ground1`, 2 px ring in the series colour.
- The card: 232 wide, 12 below the top, 14 px from the crosshair on the right side; when the crosshair is past 60 % of the width it flips to the left side. Fill `ground2` at 97 %, line `line2`, radius 10, shadow `0 12 32 rgba(0,0,0,.5)`, padding 10/12, gap 8, `pointer-events: none`, live region `polite`.
  - Header: time `HH:MM` (mono 13), day `Wed 11 Nov` (11 `text4`), right: the bucket `15 min avg · 14:25–14:30` (11 `muted`); raw data shows `raw · 14:25:07`.
  - One row per shown series: swatch 10×2, label (`text3`), value (mono 14, right aligned) in the point's unit with the point's decimals, unit (11 `text4`). Under it (11):
    - rollup: `min 81.9 · max 83.0` (`muted`) when min and max are loaded (§4);
    - raw with quality `uncertain`/stale: `uncertain · stale reads in this bucket` (`warn`);
    - no row for that time: value `no data` in `bad`, under it the reason when the historian or the live ring knows it (`comm_fail · device not reachable`), else `no data recorded`.
  - With marker A set: a line above a hairline: `Δ from A (13:00): +2.4 °C t1 over 1 h 25 min` (first shown series; per series when two units differ).
  - Footer hint (11 `muted`): `Click to set marker A`, or with A set `Click A again to clear it`.
- Keyboard: when the plot has focus (it is focusable, `role="img"` with a description of the range), ←/→ move the crosshair one bucket, Home/End jump to the ends, Esc hides it. The tooltip text is the same that a screen reader hears.

## 3. Gestures
| Gesture | Result |
|---|---|
| Hover / long-press | tooltip (§2) |
| Drag on the plot (> 1 % of its width) | ember band while dragging; on release the window becomes that span (never shorter than the minimum, §4) |
| Click on the plot | sets marker A at that bucket (dashed `text3` line, chip `A · 13:00` at the top); click within 4 px of A clears it |
| Double-click on the plot / `Reset zoom` | window = the whole loaded range |
| Drag inside the brush window | moves the window, its width kept, clamped to the range |
| Drag a handle | resizes from that side, never below the minimum |
| Drag on the brush outside the window | draws a new window from there |
| Handle focused + ← / → | moves that edge one bucket; with Shift one hour (or 1/24 of the range) |
| Click a legend button | hides / shows that series in the plot, the brush and the tooltip; the Y range follows |
| Mouse wheel / pinch over the plot | zooms around the pointer (×1.25 per notch); over the brush: moves the window |

The Y range always fits what is visible in the window (shown series, min/max when loaded), rounded to a step of 1, 2, 2.5 or 5 × 10ⁿ with 3–5 ticks; the unit sits on the top label. Series with different units get a second axis on the right (same rules) and the tooltip keeps each unit.

## 4. Data
- **History** (History page, Explorer "View History"): what `docs/studio.md` §7 History already says stays: up to three picked points, the live append of new samples (`AppendSamplesAction`), reads only for picked points. The brush shows the page's range (`1 h`, `24 h`, `7 d`, `30 d` buttons stay and set the brush range, not the window). Load the whole range once at a coarse window and re-query only the window at a finer one:
  - window choice: aim for ~300 buckets in the window: `window` = the smallest of `1m, 5m, 15m, 1h, 6h, 1d` that keeps ≤ 300, raw rows when the window is ≤ 2 h and the point has ≤ 5 000 rows in it;
  - per series and query: `agg=avg` for the line; `agg=min` and `agg=max` with the same `window` for the tooltip's min/max (three calls per series, made in parallel; min/max may arrive later, the tooltip shows them when they are in);
  - raw rows carry `q` (spec 03 `[t, v, q]`): draw `uncertain` runs dashed (5/4), never draw `bad` (a gap). Rollups skip `bad` and carry no quality: a bucket without a row is a gap;
  - re-query after the window stops moving for 250 ms; keep the coarse line visible meanwhile; cancel a request a newer one supersedes;
  - the header names what is drawn: `15 min avg`, `raw`.
- **Live** (System traffic; Explorer when a point is open without history): a ring of samples kept while Studio runs (System spec §Traffic), at most one hour; the window follows `now` until the user moves it (then `Follow now` replaces `Reset zoom`); no min/max line in the tooltip.
- **Minimum window**: 12 buckets of the brush's resolution (one hour on 24 h at 5 min) or 10 samples live.
- **Gaps**: a stretch with no row longer than 2 buckets is a gap band; the reason comes from the historian when it recorded the point's `comm_fail` (bad rows) in that stretch, else none is invented.

## 5. Build
- One widget in `ui`: `frx add-widget trend --dir charts`, fed a `TrendVm` (series with label, key, colour index, unit, decimals, points `(t, v, q?)`, optional `minMax` points; the full range; the window; the rollup label; flags `live`, `loading`). Gestures report to the connector: `onWindow(start, end)`, `onSeriesToggle(id)`; hover, marker A and the drag band are local widget state (they never reach the store).
- Painting: `CustomPainter` for lines, grid, gaps and the brush; the tooltip, crosshair dots and chips as widgets in an `Overlay`/`Stack` so text renders with the theme. Repaint the crosshair layer on hover only (a separate `RepaintBoundary`).
- Data actions in `business` (per page, with frx): `LoadTrendRangeAction` (coarse, whole range), `LoadTrendWindowAction` (fine, debounced 250 ms, cancels the previous), `LoadTrendExtremesAction` (min/max). Selectors compute the visible slice and the Y range so the widget stays dumb (`data-driven-widgets` skill).
- Replace `TrendChart` in `history_page.dart` and `explorer_page.dart`, and the chart inside `TrafficCard` (System) with `Trend`; delete `trend_chart.dart` when nothing uses it (`frx remove`).
- Colours by series index: `ember`, `good`, `warn`, `badText`, `text2` (the History board shows `t1` ember, `t2` teal). Tokens as in `ui/lib/theme/extensions/colors.dart`.

## 6. States
| State | Shows |
|---|---|
| loading the range | brush and plot skeleton (`ground4` bars), header range text, no tooltip |
| loading a finer window | the coarse line stays; a 2 px `ember` bar at the top of the plot animates |
| nothing recorded | plot area: `No values recorded in this range.` (`text4`), brush empty |
| one series hidden | its legend button dimmed, gone from plot, brush and tooltip |
| every series hidden | plot area: `All series are hidden.` |
| a series the viewer may not read | legend button with a lock, `You may not read <key>`; never queried |
| live, not following | `Follow now` pill instead of `Reset zoom` |

## 7. Found in the app (2026-11-12)
- `TrendChart` (`ui/lib/charts/trend_chart.dart`): static, min/max labels only, two time labels, no tooltip, no zoom, no brush, no gaps or quality, first series teal. Replace (§5).
- `TrafficCard` draws its own lines (`inSeries`/`outSeries`) with an axis list; move its plot to `Trend` (live mode), keep its header (measure switch, figures).
- `history_page.dart` reads about 300 buckets for the whole range per picked point; keep that as the brush's coarse range and add the window and extremes reads (§4). Live append keeps working: while the window ends at `now` it moves with the new samples (the right edge follows), once the user moves it away it stays.
- `explorer_page.dart` "View History" uses `TrendChart` with `trendLabels`; same replacement, one series.

## 8. Checklist
- [ ] Tooltip: time, bucket, values with units and decimals, min/max when loaded, quality line, no-data line, Δ from A; flips side past 60 %.
- [ ] Crosshair snaps to buckets; keyboard ←/→/Home/End/Esc on the plot.
- [ ] Drag-to-zoom, click marker A and clear, double-click reset, wheel/pinch zoom.
- [ ] Brush: move, resize, draw new, keyboard on handles, minimum window, scrim outside.
- [ ] Y range fits the window; second axis for a second unit.
- [ ] History: coarse range + fine window + min/max, debounce, cancel; raw rows dashed when uncertain, gaps as bands.
- [ ] System traffic and Explorer use the same widget; `TrendChart` removed.
- [ ] Goldens: `Trend` (idle), `TrendHover`, `TrendZoomed`, `TrendPinned`, `TrendGap`, and `History` (dark and light).
