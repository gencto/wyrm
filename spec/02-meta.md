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
| 11 | `has_children` | bool | `view=list` | діти є зараз (будь-які) |
| 12 | `display` | tstr | ні; також у `view=list` | = `attr.display`, дубль для `view=list`: назва вузла для людини (див. «Назви для людей») |
| 13 | `has_override` | bool | `view=list/keys` | є відхилення від профілю → варто тягнути `full` |
| 14 | `children_count` | uint | контейнер | |
| 15 | `q` | uint | `view=list` | поточна quality (щоб UI показав стан без `subscribe`) |
| 16 | `has_history` | bool | `view=list` | `attr.history` не порожній: вузол записується (UI показує значок історії без `~meta` на кожен рядок) |
| 17 | `has_nodes` | bool | контейнер; також у `view=list` | є дитина без `type` (вузол, не значення), яку бачить цей requester: дерево UI малює трикутник лише тоді. Responder публікує `~meta` контейнера знову, коли поле змінюється (дитину додано, прибрано, значення стало вузлом), тож `list` батька дає `Changed` |

### action
```
{ "params": { <name>: <param-meta> }, "result": type_code | "stream" | "void", "stream": bool, "level": perm,
  "timeout_ms": uint, "display": tstr, "group": tstr }
param-meta = { 1: type_code, 3: [enum...], 2: unit, "default": any, "required": bool,
               "display": tstr, "description": tstr, "placeholder": tstr, "editor": tstr }
```
Поля для UI (як `$name`, `$actionGroup`, `$params` у DSA), усі необов'язкові:
- `display` дії — назва для людини (`"Add device"`); ключ у `actions` лишається сегментом ключа (`add_device`, spec 01).
- `group` — меню, у якому UI показує дію: `"new"` — дії, що додають дітей; `"edit"` — дії, що змінюють або видаляють сам вузол; інше ім'я — окреме підменю; без `group` — верхній рівень меню.
- `display` параметра — підпис поля; ключ параметра лишається ім'ям у `args`.
- `description` — підказка; `placeholder` — приклад значення в порожньому полі.
- `editor`: `"password"` — значення приховане, UI не показує його й не підставляє (секрет); `"textarea"` — багаторядковий текст; `"file"` — параметр типу `binary`, значення — вміст локального файлу, який вибирає користувач (UI може надіслати такий виклик поза WebSocket-кадром, ADR 0011); `"daterange"` — текст `<from>/<to>` у RFC 3339, UI пропонує готові проміжки (сьогодні, вчора, останні 7 днів, …) і вибір дати й часу (0.2.4); `"date"` — одна мить у RFC 3339, вибір дати й часу (0.2.4; також `attr.editor` значення сховища, ADR 0017); `"duration"` — число секунд, UI дає ввести його в одиниці поруч (с, хв, год, дн) і надсилає секунди (0.2.4). Невідомий `editor` UI ігнорує.

## Назви для людей (0.2.28, ADR 0042)
Ключ (вузла, дії, параметра) — ім'я на дроті: сегмент шляху або ім'я в `args`; його не змінюють заради вигляду. Людина бачить `display`:
- **Вузол.** `attr.display` (і ключ 12 у `view=list`) — необов'язкова назва вузла для людини (`t1` → `"Supply temperature"`). Ніколи не частина шляху: шлях, ключі `view=keys`, гранти й посилання беруть лише ключ. Ставить responder під час declare; у фреймворку драйверів — також користувач: необов'язковий параметр `display` у `add_*` і `edit` з'єднання, пристрою й точки (`edit` без `display` лишає наявну назву, `null` або `""` прибирає її; `edit` лише з `display` — перейменування, параметри лишаються; ≤ 128 байт; ключ `display` зарезервований на цих рівнях). UI показує `display`, а без нього — ключ.
- **Дія й параметр.** `display` дії й параметра. Responder SDK заповнює відсутній `display` з ключа за правилом нижче, тож у `~meta` він є завжди; явний `display` лишається як є. Для `~meta` старого responder'а без `display` клієнт може вивести назву з ключа (точне правило — `wyrm_core::display`).
- **Правило з ключа** (`wyrm_core::display::humanize`): токени між `_`, `-`, `.`; перше слово з великої, решта з малої; акроніми й назви — як у списку (`url` → `URL`, `id` → `ID`, `mqtt` → `MQTT`); останній токен-одиниця (`ms`, `s`, `hz`, `mb`, `mib`, `kib`, `pct`, `days`, `us`) — у дужках: `timeout_ms` → `Timeout (ms)`, `unit_id` → `Unit ID`, `add_device` → `Add device`.
- **Стиль явного `display`**: sentence case, коротко, без крапки в кінці, акроніми великими, одиниці в дужках; дія починається з дієслова (`Add connection`, `Read registers`), параметр — іменник (`Poll rate (s)`). Значення enum (`3`) і `group` — значення на дроті, не назви: їх UI показує як є або за тим самим правилом.

## Успадкування
Відсутнє поле береться з профілю `is` (рекурсивно через `extends` у профілі). Профіль (`pub/<profile>/~meta`) — та сама map, що `~meta`, плюс текстовий ключ `"extends": tstr` (ім'я батьківського профілю); ланцюг ≤ 8, без циклів. `cfg`, `attr`, `actions` зливаються по ключах (власні виграють); `is`, `rev`, `children` і поля `view=list` не успадковуються. `pub/**` пише лише `wyrm-admin`; `?expand=true` — профіль з уже злитим ланцюгом. SDK responder'а відповідає **розгорнутим** `~meta` у `view=full` лише на `?expand=true`; за замовчуванням — тільки власні поля (економія).

## `view=list`
Відповідь — **CBOR array** map'ів дітей з ключами `{0,1,2?,4?,10,11,12?,13?,15?,16?,17?}` (власні поля дитини, без профілю); порядок = `children`. Пагінація `from/limit`.

## `attr.history`
Масив ключів сховищ, що записують цю точку (як `@@getHistory` у DSA). Ключ під `wy/<site>/sys/history/` — історик брокера сайту: для точки свого сайту він відповідає на ключі самої точки (`<point>/~val?history=`, spec 01/03; права як на читання значення), а на ключі watch (`<store>/~val?history=`) — для будь-якої своєї точки; точку сайту нижче читають лише там (ADR 0020). Такий `attr.history` кладе не брокер лінка, а сайт, що записує: його gateway зливає `sys/overlays/.sites` у `meta`/`list` вузлів інших сайтів. Будь-яке інше сховище відповідає на `<store>/~val?history=` саме. Брокер кладе `attr.history` поверх `~meta` лінка (накладка, ADR 0016); власний `attr.history` лінка зливається з нею (об'єднання).

## `view=keys`
Відповідь — CBOR array of tstr з префіксною компресією: елемент із суфіксом `/` = push префікса, порожній `""` = pop, інший = повний ключ під поточним префіксом. Фільтр `match` застосовується responder'ом.

## Patch
`put ~meta` при зміні — `{10: rev, "patch": {<key>: <value>, ...}}`; відсутність `"patch"` = повний `~meta`. Requester, що бачить `rev` ≠ `last_rev+1`, робить `get ~meta`.

Фікстури: `meta_number_full`, `meta_folder_full`, `meta_action_ui`, `meta_profile_only`, `meta_view_list`, `meta_view_keys`, `meta_patch`, `profile_extends`.
