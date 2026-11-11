# Flow blocks: coverage of the reference palette

This table maps each of the 152 palette items of the reference dashboard
product (DGLux5 build 1.1.9443, plus the Lua block of its port) to WYRM. The
behaviour reference is the owner's handoff (`docs/blocks/`, kept outside the
repository). ADR 0044 records the decisions behind the table. The guide for
every WYRM block is `docs/flow-blocks.md`.

Status words:

- **have**: a WYRM type does what the item does.
- **have, differs**: a WYRM type does it, with the difference given. "closed"
  means this set added what was missing; "kept" means the difference stays on
  purpose (ADR 0044 §5).
- **add**: a new WYRM type of this set (ADR 0044).
- **covered by**: another WYRM mechanism does it.
- **not for a broker**: the item needs a screen, a browser, the editor, a
  style, a device sensor or the dashboard server's file API.
- **deferred**: computation that belongs on the server, left for a later set,
  with the reason.

## Counts

| Status | Items |
|---|---|
| have | 19 |
| have, differs | 12 (closed 5, kept 7) |
| add | 66 items as 60 new types |
| covered by | 22 |
| not for a broker | 30 |
| deferred | 3 |
| **total** | **152** |

The set also adds types for nodes that the reference registers but does not
show in its palette: the codecs (`base64_encode`, `base64_decode`,
`url_encode`, `url_decode`, `to_camel_case`, `from_camel_case`, `hash`) and
`json_parse` / `json_stringify` for values. `node_types` now lists 115 types.

## Variables

| Item | Status | WYRM |
|---|---|---|
| String `string` | have | `string` |
| Number `number` | have | `number` |
| Boolean `bool` | have | `bool` |
| Color `color` | not for a broker | a fill or colour of a view (style) |
| Binary `binary` | covered by | `const` (a value may be bytes) |
| Table `table` | add | `table`: a table literal, sent at start as a variable |

## Data services

| Item | Status | WYRM |
|---|---|---|
| String Loader `strLoader` | covered by | the HTTP link (`links/http`): a flow reads its points; a flow does no HTTP of its own |
| String Uploader `strUploader` | not for a broker | the dashboard server's file API |
| List Files `listFiles` | covered by | the file store links (`links/localfs`, `s3`, …): `list_children` on their `files` node |
| Get Children `getChildren` | have, differs (kept) | `list_children`: rows `{name, path, type, display, is, unit, writable, has_children}`, no `icon`/`enum` |
| Get Node `getNode` | add | `get_node`: a node's summary and its actions with their parameters |
| Project-Info `projectInfo` | not for a broker | the dashboard project and the viewer's session |
| Relativize `relativize` | covered by | `concat` builds the key, `in.key` with `key_scope` reads it (ADR 0040 §1) |
| Multi-Histories `loadHistories` | add | `load_histories`: several keys merged into one table by time |
| Zip Upload `zipUpload` | not for a broker | the dashboard server's file API |
| Zip Download `zipDownload` | not for a broker | a browser download |
| Zip Parser `zipParser` | deferred | needs an archive codec with bounds on expansion; files reach a flow through the file store links |
| Load Value `loadValue` | have | `load_value` |
| Load History `loadHistory` | add | `load_history`: the historian's rows as a table |
| Download File `downloadFile` | not for a broker | a browser download |

## DSA

| Item | Status | WYRM |
|---|---|---|
| List Node `listNode` | covered by | `list_children` with `interval_ms` or `trigger`, and `get_node` |
| Get Default Parameters `getDefaultParams` | covered by | `get_node`: each action's parameters carry their `default` |
| Dsa Connection `dsaConnection` | not for a broker | the flow runs inside the broker: there is no connection to make |

## Browser API

| Item | Status | WYRM |
|---|---|---|
| Jsonp Loader `jsonpLoader` | not for a broker | a browser script tag |
| Geo-Location `geoLocation` | not for a broker | a device sensor |
| Device Orientation `deviceOrientation` | not for a broker | a device sensor |
| Device Motion `deviceMotion` | not for a broker | a device sensor |
| Web-Document `webDocument` | not for a broker | the browser document |
| Local Storage `localStorage` | covered by | broker storage (`storage/…`): `load_value` reads, `set` writes |
| Blob URL `blobUrl` | not for a broker | a browser object URL |
| IFrame Message `iframeMessage` | not for a broker | browser frames |
| Export HTML `exportHtml` | not for a broker | the view |
| Export Paginated PDF `exportPaginatedPDF` | not for a broker | the view |
| Get View Property `getViewProperty` | not for a broker | the view |
| Lua file `javascript` | not for a broker | a browser script file; WYRM runs `expression` (rhai) and `wasm` |
| Close Warning Dialog `closeWarningDialog` | not for a broker | the browser window |

## Logic

| Item | Status | WYRM |
|---|---|---|
| If `if` | have | `if` |
| Case `case` | have, differs (closed) | `case` gets the operator `regexp` (bounded, ADR 0044 §6) |
| Router `router` | add | `router`: `in` goes out on the output of the first case that matches |
| Hub `hub` | have | `hub` (`index` is the input's position, a number) |
| Event Gate `eventGate` | add | `event_gate` |
| Script `script` | covered by | `expression` (rhai) and `wasm`; no JS, no Lua |
| Trace `trace` | have | `trace` |
| Stop Watch `stopwatch` | have | `stopwatch` |
| Delay `delay` | have, differs (kept) | `delay`; its modes `window` and `wait` are `throttle` and `debounce`; one value per block, no pairs |
| State `changeState` | covered by | `set` and `invoke` write points; animation is a view matter |
| Mouse Event `mouseEventData` | not for a broker | a view event |
| Keyboard Event `keyboardEventData` | not for a broker | a view event |
| Scroll Event `scrollEventData` | not for a broker | a view event |
| Resize Event `resizeEventData` | not for a broker | a view event |
| Drag Position `dragPosition` | not for a broker | drag in a view |
| Drag Size `dragSize` | not for a broker | drag in a view |
| Repeater `repeater` | deferred | one instance per row is known only at run time; the 1000-node budget and the deploy proofs are computed at compile time (ADR 0044 §7) |
| Catch Error `catchError` | add | `catch_error`: the `error` outputs wired into it, as one text, code and event |
| Make Object `makeObject` | have | `make_object` |
| Map Series Data `mapSeriesData` | not for a broker | chart geometry |
| Property Hub `propertyHub` | covered by | `publish` (`dataflows/<id>/nodes/<n>`) and `subscribe` share named values |
| Property Hub Modifier `propertyHubModifier` | covered by | as Property Hub |
| Symbol Profiler `symbolProfiler` | not for a broker | an editor tool; `watch` shows a running flow |

## Operations

| Item | Status | WYRM |
|---|---|---|
| Lua `lua` | covered by | `expression` (rhai); no Lua |
| And `if` | have | `if` with `op: and` |
| Or `if` | have | `if` with `op: or` |
| Not `not` | have | `not` |

## String operations

| Item | Status | WYRM |
|---|---|---|
| Concatenate `concat` | have | `concat` |
| Left `left` | add | `left` |
| Length `length` | have | `length` |
| Right `right` | add | `right` |
| Substring `substring` | have, differs (closed) | `substring` gets `end` (a negative `end` counts from the end); an overrun is clamped, not `null` (kept) |
| Replace `replace` | have, differs (closed) | `replace` gets `regexp` (bounded) |
| Trim `trim` | add | `trim` |
| Split `split` | have, differs (kept) | `split` gives a list of texts; the reference gives a table `{row, value}` (`table_from_map` or `make_object` make one) |
| Localize `localize` | not for a broker | the dashboard project's locale files |

## Math operations

| Item | Status | WYRM |
|---|---|---|
| Add `add` | have | `add` |
| Divide `divide` | have | `divide` (by 0: `null`, as every result that is not finite) |
| Factorial `factorial` | add | `factorial` |
| Logarithm `log` | add | `log` |
| Modulo `modulo` | have, differs (kept) | `modulo`: the remainder is never negative; the reference takes the sign of the dividend |
| Multiply `multiply` | have | `multiply` |
| Power `power` | add | `power` |
| Root `root` | add | `root` |
| Scale `scale` | have, differs (kept) | `scale` with the range form; it does not clamp to the output range (`bound` does) |
| Subtract `subtract` | have | `subtract` |

## Number formatting

| Item | Status | WYRM |
|---|---|---|
| Absolute `abs` | have | `abs` |
| Bound `bound` | add | `bound` |
| Round `round` | have | `round` |
| Round Up `roundUp` | add | `round_up` |
| Round Down `roundDown` | add | `round_down` |
| Gradient Mapping `gradientMapping` | not for a broker | a colour for a view (style) |
| Format Number `formatNumber` | add | `format_number` |
| Parse Number `parseNumber` | add | `parse_number` |

## Statistical functions

| Item | Status | WYRM |
|---|---|---|
| Average `average` | add | `average` |
| Maximum `max` | have, differs (kept) | `max`: no number gives `null`; the reference gives 0 |
| Median `median` | add | `median` |
| Minimum `min` | have, differs (kept) | `min`: no number gives `null`; the reference gives +Infinity (its own bug) |
| Mode `mode` | add | `mode` |
| Standard Deviation `stdDeviation` | add | `std_deviation` |
| Variance `variance` | add | `variance` |

## Trigonometric functions (degrees)

| Item | Status | WYRM |
|---|---|---|
| Arc Cosine `acos` | add | `acos` |
| Arc Sine `asin` | add | `asin` |
| Arc Tangent `atan` | add | `atan` (with `x`: the angle of the point `x`, `in`) |
| Cosine `cos` | add | `cos` |
| Cotangent `cot` | add | `cot` |
| Degree `toDegree` | add | `to_degrees` |
| Radian `toRadian` | add | `to_radians` |
| Sine `sin` | add | `sin` |
| Tangent `tan` | add | `tan` |

## Table operations

| Item | Status | WYRM |
|---|---|---|
| CSV Parser `csvParser` | add | `table_from_csv` |
| CSV Writer `csvWriter` | add | `table_to_csv` |
| JSON Parser `jsonParser` | add | `table_from_json` |
| Table To JSON String `tableToJsonString` | add | `table_to_json` |
| Column Mapping `tableColumnMapping` | add | `table_map_columns` |
| Sort `tableSort` | add | `table_sort` |
| Filter `tableFilter` | add | `table_filter` |
| Group By `tableGroupBy` | add | `table_group_by` |
| Join `tableJoin` | add | `table_join` |
| Multi-Join `tableMultiJoin` | covered by | `table_join` (left) in a chain |
| Page `tablePage` | add | `table_page` |
| Rollup `tableRollup` | add | `table_rollup` |
| Advanced Rollup `tableAdvancedRollup` | add | `table_rollup` with one method per column (one type for both) |
| Aggregation `tableAggregation` | add | `table_aggregate` |
| Select Rows `tableSelectRows` | add | `table_select_rows` |
| Select Columns `tableSelectColumns` | add | `table_select_columns` |
| Get Columns `tableGetColumns` | add | `table_columns` |
| Table Row Cells `tableRowCells` | add | `table_row_cells` (read; a write is `table_edit_rows`) |
| Add Row `tableAddRow` | add | `table_add_row` (a pure transform) |
| Remove Rows `tableRemoveRows` | add | `table_remove_rows` (a pure transform) |
| Edit Rows `tableEditRows` | add | `table_edit_rows` (a pure transform) |
| Transpose `tableTranspose` | add | `table_transpose` |
| Realtime Recorder `realtimeRecorder` | add | `table_recorder` |
| Series Realtime Recorder `seriesRealtimeRecorder` | covered by | `table_from_map` of a `make_object`, then `table_transpose` |
| Map to Table `mapToTable` | add | `table_from_map` |

## Date and time

| Item | Status | WYRM |
|---|---|---|
| Date Time `datetime` | add | `date_time` |
| Date Format `dateFormat` | add | `date_format` |
| Parse Date Time `parseDateTime` | add | `date_parse` |
| Date Math `dateMath` | add | `date_math` |
| Date Range `dateRange` | add | `date_range` |

The set also adds `now`, the current time on each sample of `in`.

## Constants

| Item | Status | WYRM |
|---|---|---|
| PI | add | `constant` with `name: pi` |
| E | add | `constant`, `e` |
| SQRT2 | add | `constant`, `sqrt2` |
| LN2 | add | `constant`, `ln2` |
| LN10 | add | `constant`, `ln10` |
| LOG2E | add | `constant`, `log2e` |
| LOG10E | add | `constant`, `log10e` |
| NAN | covered by | `const` with `null`: a WYRM value has no NaN (ADR 0044 §5) |

## Editors

| Item | Status | WYRM |
|---|---|---|
| Text Editor `textEditor` | not for a broker | a form component |
| Enum Editor `enumEditor` | not for a broker | a form component |
| Boolean Editor `boolEditor` | not for a broker | a form component |
| Number Editor `numberSliderEditor` | not for a broker | a form component |
| Percentage Editor `percentSliderEditor` | not for a broker | a form component |
| Color Editor `colorEditor` | not for a broker | a form component |
| Fill Editor `fillEditor` | not for a broker | a form component |
| Gradient Editor `gradientListEditor` | not for a broker | a form component |
