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
| 12 | `origin` | tstr | both | `user:<id>` \| `flow:<id>` \| `link:<id>` \| `svc:<id>` \| `broker:<site>` — довіряється лише при валідному `ptok` або CN-сесії |
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
| 0x23 | invalid_parameter | | |
Група: `< 0x10` — успіх/прогрес; `0x10–0x1F` — закриття; `≥ 0x20` — помилка.

## `ptok v1`
```
ptok = version(1 байт = 0x01) || claims(CBOR) || sig(64 байти, Ed25519 над version||claims)
claims = { "sub": tstr, "roles": [tstr], "grants": [ {"k": key_expr, "p": perm} ],
           "max": perm, "iat": uint, "exp": uint, "jti": bstr(16), "site": tstr }
```
Перевірка responder'ом, у цьому порядку: version == 1 → sig публічним ключем admin'а (kid не потрібен: один активний + один попередній ключ) → `exp > now` → `site` == свій → `jti` не в replay-кеші → перший `grants[i].k`, що збігається з ключем запиту (Zenoh key-expr intersect) → `effective = min(p, max, attachment.maxperm)` → `effective ≥ required`. Будь-яка відмова → `permission_denied`, без деталей у `err`.

Фікстури: `att_*`, `ptok_claims_v1`.
