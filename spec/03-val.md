# 03 — `~val`

```
{ 0: v, 1: q, 2: t }
```
| Ключ | Тип CBOR | Опис |
|---|---|---|
| 0 `v` | за `~meta.type`: float64/int → number; tstr → string; bool; uint → enum index; map; array; bstr → binary; any → dynamic; null | значення |
| 1 `q` | uint | 0 good, 1 uncertain, 2 bad |
| 2 `t` | uint | uhlc timestamp джерела, мікросекунди Unix |

Розширений код quality (`bad/disconnected`, `uncertain/stale`, …) — **не тут**, а в attachment ключ 1 (`qual`), бо потрібен рідко.

## Правила
- `t` — час **вимірювання**, не публікації. Якщо джерело не має часу — час на боці конектора.
- Числа: encoder пише найкоротшу форму (int, якщо ціле; float32, якщо точно представиме — опція `cfg.precision`; інакше float64). Decoder приймає будь-яку.
- Пустий `~val` (вузол без значення) не публікується.
- Контейнери `~val` не мають.

## Історія
`get ~val?history=...` → CBOR array of `[t, v, q]` (масив, не map — компактніше для тисяч точок); `?agg=` → array of `[t_start, value]`.

Фікстури: `val_*`.
