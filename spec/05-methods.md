# 05 — Методи

| Метод | Zenoh | Payload запиту | Відповідь | `ptok` |
|---|---|---|---|---|
| `list(path, from, limit)` | `get path/~meta?view=list` + `subscribe path/*/~meta` + liveliness-subscribe `path/*` | — | array (02-meta) + далі події | лише `cfg.restricted` |
| `meta(path)` | `get path/~meta[?rev=]` | — | map або `status=ok,rev` без тіла | лише `cfg.restricted` |
| `resolve(path, match, depth)` | `get path/~meta?view=keys&match=&depth=` | — | array of tstr (стиснуті) | лише `cfg.restricted` |
| `subscribe(pattern, qos)` | `get pattern/~val` (storage) + `subscribe pattern/~val` | — | `Stream<Sample{key, v, q, t}>` | ні (ACL сесії) |
| `history(path, from, to, agg?)` | `get path/~val?history=` | — | array (один або кілька reply, 03) | ні (ACL сесії на `~val`, як `subscribe`) |
| `set(path, v)` | `get path/~set` | `{0: v}` | attachment `status` | так |
| `set_meta(path, field, v)` | `get path/~set?field=` | `{0: v}` | `status` | так (config) |
| `invoke(path, action, args)` | `get path/~act/<a>` | map args (tstr keys) | одна відповідь або стрім | так |
| `close(path, action, rid)` | `get path/~act/<a>?close=<rid>` | — | `status=closed` | так |
| `check(path, action, args)` | `get path/~act/<a>?check` | map args, як `invoke` | `status=ok` без тіла, або відмова, як дала б дія | так |

## `check` (0.2.33)
Responder перевіряє виклик так, як його взяла б дія: `ptok` і рівень, аргументи за `~meta` дії, а потім власний розбір аргументів драйвером (форма, права автора, отримувачі). Нічого не робить: ні запису, ні команди, ні зміни стану; усе, що драйвер попросив у host під час перевірки, відкидається. Відмова така сама, як дала б дія (той самий статус і текст); успіх — `status=ok` без тіла. В аудиті — окремий запис `check`.

Responder, що відповідає на `check`, має в `~meta` свого кореня (`wy/<site>/downstream/<link>`, `sys`, `dataflows`, `storage`) `attr.check = true`. Requester надсилає `?check` лише такому: старіший responder не знає параметра і виконав би дію. Без `attr.check` перевірка закінчується на `~meta` дії, на боці requester'а.

WASM-компонент світу `wyrm:app` 0.3.0 не має виклику перевірки: його перевірка закінчується на `~meta` дії (host її робить); власний розбір — з наступним світом.

## Стріми (`actions.*.stream = true`)
- `mode="reply"` (default): N відповідей на один query, `rid` однаковий, `seq` зростає від 0, остання `last=true`. Query-таймаут на боці requester'а скидається кожною відповіддю.
- `mode="topic"`: перша відповідь `{status: initializing}` з payload `{"stream": key}`; requester підписується; responder публікує на `key`; `close` зупиняє; responder видаляє ключ.

## Таймаути
Default `get` — 10 с; `initializing` продовжує; `invoke` з `actions.*.timeout_ms` перевизначає. Відсутність будь-якої відповіді → SDK мапить у `disconnected` **лише якщо** liveliness власника відсутній, інакше `timeout`.

## QoS
| Zenoh | `~val` | `~meta` | `~set/~act` | аудит/метрики |
|---|---|---|---|---|
| Priority | Data | DataHigh | InteractiveHigh | Background |
| CongestionControl | Drop | Block | Block | Drop |
| Reliability | per `cfg.qos` (default BestEffort) | Reliable | Reliable | BestEffort |
| express | false | false | true | false |

## Помилки транспорту vs застосунку
Застосунок: `status ≥ 0x20` у attachment. Транспорт: відсутність reply / розрив сесії → SDK, не responder.
