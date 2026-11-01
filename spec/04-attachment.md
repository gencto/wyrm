# 04 — Attachment

CBOR map з цілими ключами. Відсутній attachment = `{}`.

| Ключ | Назва | Тип | Напрям | Опис |
|---|---|---|---|---|
| 0 | `status` | uint | reply | код; **обов'язковий у кожній відповіді** на `~set`, `~act`, `~meta` get |
| 1 | `qual` | tstr | both | розширений код quality `bad/disconnected` |
| 2 | `ts` | uint | both | для raw payload без `{v,q,t}` |
| 3 | `refreshed` | bool | reply | |
| 4 | `ptok` | bstr | request | див. нижче |
| 5 | `maxperm` | uint | request | 0..4 |
| 6 | `audit` | tstr | reply | |
| 7 | `err` | tstr | reply | |
| 8 | `rev` | uint | both | |
| 9 | `rid` | uint | both | кореляція стріму |
| 10 | `seq` | uint | reply | |
| 11 | `last` | bool | reply | |
| 12 | `origin` | tstr | both | `user:<id>` \| `flow:<id>` \| `link:<id>` \| `svc:<id>` \| `broker:<site>` — довіряється лише при валідному `ptok` або CN-сесії; з `ptok` responder приймає лише `origin == sub` або `<sub>/...`, інакше підставляє `sub` |
| 13 | `trace` | bstr(16) | both | |
| 14 | `enc` | tstr | reply | `zstd` — payload стиснуто |

## Статуси
| Код | Ім'я | Код | Ім'я |
|---|---|---|---|
| 0x00 | ok | 0x24 | busy |
| 0x01 | initializing | 0x25 | internal_error |
| 0x02 | refreshed | 0x26 | not_supported |
| 0x08 | not_available | 0x27 | not_found |
| 0x10 | closed | 0x28 | timeout |
| 0x20 | disconnected | 0x29 | out_of_range |
| 0x21 | permission_denied | 0x2A | rate_limited |
| 0x22 | invalid_message | 0x40–0x4F | user-defined |
| 0x23 | invalid_parameter | 0x2B | resource_exhausted |
`resource_exhausted` — досягнуто межу виконавця (вузли, таймери, підписки, запити в роботі, команди за подію, квота сховища; ADR 0023); повтор не допоможе, поки щось не звільнено. `rate_limited` — повтор пізніше допоможе.

Група: `< 0x10` — успіх/прогрес; `0x10–0x1F` — закриття; `≥ 0x20` — помилка.

## `ptok v1`
```
ptok = version(1 байт = 0x01) || claims(CBOR) || sig(64 байти, Ed25519 над version||claims)
claims = { "sub": tstr, "roles": [tstr], "grants": [ {"k": key_expr, "p": perm} ],
           "max": perm, "iat": uint, "exp": uint, "jti": bstr(16), "site": tstr,
           ? "auth": [ {"k": key_expr, "p": perm} ] }
```
`auth` (необов'язковий, з 0.2.10): усі grants викликача на цьому сайті. Його несуть лише токени на дії (`~act/*`). Він **ніколи** не дає прав на сам запит — права дає лише `grants`. Responder, який діє від імені викликача (DQL, scheduler), перевіряє за ним ключі, які викликач назвав у аргументах. SDK обмежує кожен grant з `auth` так само, як ефективний рівень: `min(p, max, attachment.maxperm, cap ключа)`, а для обмеженого ключа (`LimitedKey`) лишає тільки ключі в межах його scopes. Токен без `auth` означає, що права викликача невідомі; responder, якому вони потрібні, відмовляє.
Перевірка responder'ом, у цьому порядку: version == 1 → sig публічним ключем admin'а (kid не потрібен: один активний + один попередній ключ) → `exp > now` → `site` == свій → перший `grants[i].k`, що збігається з ключем запиту (Zenoh key-expr intersect) → `jti` не в replay-кеші → `effective = min(p, max, attachment.maxperm)` → `effective ≥ required`. Будь-яка відмова → `permission_denied`, без деталей у `err`.

`jti` (0.2.11): токен одноразовий для кожного responder'а. Responder пам'ятає `jti` до `exp` і вдруге відмовляє. Пам'ять — у процесі: після перезапуску responder'а токен, який він бачив, проходить знову до свого `exp`. Тому `exp` не може бути далі ніж 15 хв від `now` (інакше `permission_denied`). Коли кеш повний (65 536 токенів, що ще не спливли), responder відмовляє новим токенам, а не забуває старі.

`jti` (0.2.12): responder запам'ятовує `jti` лише після того, як знайшов grant для ключа запиту. Токен без такого grant відмовляється і не займає місця в кеші. Один `sub` займає не більше чверті кешу (16 384 токени, що ще не спливли). Коли його частка повна, responder відмовляє новим токенам цього `sub`, а інші `sub` проходять.

Фікстури: `att_*`, `ptok_claims_v1`, `ptok_claims_auth`.
