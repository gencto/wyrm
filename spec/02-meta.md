# 02 — `~meta`

## Ключі (CBOR map, цілі ключі)
| Ключ | Назва | Тип CBOR | Обов'язк. | Опис |
|---|---|---|---|---|
| 0 | `is` | uint (is_code) або tstr | так | профіль; uint — код з `sys/codes`, tstr — повне ім'я (для невідомих клієнту кодів) |
| 1 | `type` | uint (type_code) | листовий | 0 null, 1 number, 2 string, 3 bool, 4 enum, 5 map, 6 array, 7 binary, 8 dynamic |
| 2 | `unit` | tstr або uint (unit_code) | ні; також у `view=list` | одиниця; UI пише її після числового значення (`21.5 °C`), не після enum, bool чи тексту |
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
| 16 | `has_history` | bool | `view=list` | `attr.history` не порожній: вузол записується (UI показує значок історії без `~meta` на кожен рядок) |

### action
```
{ "params": { <name>: <param-meta> }, "result": type_code | "stream" | "void", "stream": bool, "level": perm,
  "timeout_ms": uint, "display": tstr, "group": tstr }
param-meta = { 1: type_code, 3: [enum...], 2: unit, "default": any, "required": bool,
               "display": tstr, "description": tstr, "placeholder": tstr, "editor": tstr }
```
Поля для UI (як `$name`, `$actionGroup`, `$params` у DSA), усі необов'язкові:
- `display` дії — назва для людини (`"Add Device"`); ключ у `actions` лишається сегментом ключа (`add_device`, spec 01).
- `group` — меню, у якому UI показує дію: `"new"` — дії, що додають дітей; `"edit"` — дії, що змінюють або видаляють сам вузол; інше ім'я — окреме підменю; без `group` — верхній рівень меню.
- `display` параметра — підпис поля; ключ параметра лишається ім'ям у `args`.
- `description` — підказка; `placeholder` — приклад значення в порожньому полі.
- `editor`: `"password"` — значення приховане, UI не показує його й не підставляє (секрет); `"textarea"` — багаторядковий текст; `"file"` — параметр типу `binary`, значення — вміст локального файлу, який вибирає користувач (UI може надіслати такий виклик поза WebSocket-кадром, ADR 0011). Невідомий `editor` UI ігнорує.

## Успадкування
Відсутнє поле береться з профілю `is` (рекурсивно через `extends` у профілі). Профіль (`pub/<profile>/~meta`) — та сама map, що `~meta`, плюс текстовий ключ `"extends": tstr` (ім'я батьківського профілю); ланцюг ≤ 8, без циклів. `cfg`, `attr`, `actions` зливаються по ключах (власні виграють); `is`, `rev`, `children` і поля `view=list` не успадковуються. `pub/**` пише лише `wyrm-admin`; `?expand=true` — профіль з уже злитим ланцюгом. SDK responder'а відповідає **розгорнутим** `~meta` у `view=full` лише на `?expand=true`; за замовчуванням — тільки власні поля (економія).

## `view=list`
Відповідь — **CBOR array** map'ів дітей з ключами `{0,1,2?,4?,10,11,12?,13?,15?,16?}` (власні поля дитини, без профілю); порядок = `children`. Пагінація `from/limit`.

## `attr.history`
Масив ключів сховищ, що записують цю точку (як `@@getHistory` у DSA). Ключ під `wy/<site>/sys/history/` — історик брокера сайту: він відповідає на ключі самої точки (`<point>/~val?history=`, spec 01/03; права як на читання значення). Будь-яке інше сховище відповідає на `<store>/~val?history=` саме. Брокер кладе `attr.history` поверх `~meta` лінка (накладка, ADR 0016); власний `attr.history` лінка зливається з нею (об'єднання).

## `view=keys`
Відповідь — CBOR array of tstr з префіксною компресією: елемент із суфіксом `/` = push префікса, порожній `""` = pop, інший = повний ключ під поточним префіксом. Фільтр `match` застосовується responder'ом.

## Patch
`put ~meta` при зміні — `{10: rev, "patch": {<key>: <value>, ...}}`; відсутність `"patch"` = повний `~meta`. Requester, що бачить `rev` ≠ `last_rev+1`, робить `get ~meta`.

Фікстури: `meta_number_full`, `meta_folder_full`, `meta_action_ui`, `meta_profile_only`, `meta_view_list`, `meta_view_keys`, `meta_patch`, `profile_extends`.
