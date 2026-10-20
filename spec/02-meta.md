# 02 — `~meta`

## Ключі (CBOR map, цілі ключі)
| Ключ | Назва | Тип CBOR | Обов'язк. | Опис |
|---|---|---|---|---|
| 0 | `is` | uint (is_code) або tstr | так | профіль; uint — код з `sys/codes`, tstr — повне ім'я (для невідомих клієнту кодів) |
| 1 | `type` | uint (type_code) | листовий | 0 null, 1 number, 2 string, 3 bool, 4 enum, 5 map, 6 array, 7 binary, 8 dynamic |
| 2 | `unit` | tstr або uint (unit_code) | ні | одиниця |
| 3 | `enum` | array of tstr | type=4 | значення enum; `~val.v` = індекс |
| 4 | `writable` | uint | ні, default 0 | 0 never, 1 config, 2 write |
| 5 | `invokable` | uint | ні, default 0 | мін. рівень для дій: 0 never, 2 read, 3 write, 4 config |
| 6 | `cfg` | map (tstr keys) | ні | системні параметри: `precision min max interval_ms deadband retention_days restricted auto_group enabled` |
| 7 | `attr` | map (tstr keys) | ні | користувацькі |
| 8 | `actions` | map name → action | ні | див. нижче |
| 9 | `children` | array of tstr | контейнер | упорядкований список дітей (тільки `view=full`) |
| 10 | `rev` | uint | так | версія meta, монотонна |
| 11 | `has_children` | bool | `view=list` | |
| 12 | `display` | tstr | ні | = `attr.display`, дубль для `view=list` |
| 13 | `has_override` | bool | `view=list/keys` | є відхилення від профілю → варто тягнути `full` |
| 14 | `children_count` | uint | контейнер | |
| 15 | `q` | uint | `view=list` | поточна quality (щоб UI показав стан без `subscribe`) |

### action
```
{ "params": { <name>: <param-meta> }, "result": type_code | "stream" | "void", "stream": bool, "level": perm }
param-meta = { 1: type_code, 3: [enum...], 2: unit, "default": any, "required": bool }
```

## Успадкування
Відсутнє поле береться з профілю `is` (рекурсивно через `extends` у профілі). Профіль (`pub/<profile>/~meta`) — та сама map, що `~meta`, плюс текстовий ключ `"extends": tstr` (ім'я батьківського профілю); ланцюг ≤ 8, без циклів. `cfg`, `attr`, `actions` зливаються по ключах (власні виграють); `is`, `rev`, `children` і поля `view=list` не успадковуються. `pub/**` пише лише `wyrm-admin`; `?expand=true` — профіль з уже злитим ланцюгом. SDK responder'а відповідає **розгорнутим** `~meta` у `view=full` лише на `?expand=true`; за замовчуванням — тільки власні поля (економія).

## `view=list`
Відповідь — **CBOR array** map'ів дітей з ключами `{0,1,10,11,12?,13?,15?}`; порядок = `children`. Пагінація `from/limit`.

## `view=keys`
Відповідь — CBOR array of tstr з префіксною компресією: елемент із суфіксом `/` = push префікса, порожній `""` = pop, інший = повний ключ під поточним префіксом. Фільтр `match` застосовується responder'ом.

## Patch
`put ~meta` при зміні — `{10: rev, "patch": {<key>: <value>, ...}}`; відсутність `"patch"` = повний `~meta`. Requester, що бачить `rev` ≠ `last_rev+1`, робить `get ~meta`.

Фікстури: `meta_number_full`, `meta_folder_full`, `meta_profile_only`, `meta_view_list`, `meta_view_keys`, `meta_patch`, `profile_extends`.
