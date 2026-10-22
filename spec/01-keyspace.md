# 01 — Key-space

## Граматика
```
key        = "wy/" site "/" branch
site       = seg
branch     = "down/" link ("/" path)? ("/" suffix)?
           | "down/" site ("/connected")? ("/" suffix)?        ; downstream broker node
           | "up/" site ("/connected")? ("/" suffix)?          ; upstream broker node
           | "flows/" flowid ("/" ("~def" | "~meta" | "~val" | "~act/" name | "nodes/" seg "/" suffix))?
           | "pub/" profile "/~meta"
           | "sys/" syspath
path       = seg ("/" seg)*
suffix     = "~meta" | "~val" | "~set" | "~act/" name | "~state"
seg        = 1*( ALPHA / DIGIT / "_" / "-" / "." )     ; без "/", без пробілів, не починається з "~"
link       = seg ; = Link id, = cert CN
profile    = "wy:" seg ; або "<vendor>:" seg
```

## Зарезервовано
- Суфікси `~meta ~val ~set ~act ~state ~def`; будь-який сегмент, що починається з `~` — помилка валідації в SDK.
- Zenoh-спецсимволи `* ** $* ? # @` у сегментах заборонені; протокольні імена з ними — percent-encoding (`%2A`), SDK декодує в `display`.
- Дія `~remove` у `~act/` зарезервована (видалення вузла/атрибута).
- Префікси `wy/<site>/sys/` і `wy/<site>/pub/` пише лише `wyrm-admin`.

## Повні імена
Віртуальних префіксів (`remote/`) немає: ключ має одне ім'я на всіх брокерах mesh і в UI.

## Брокери-сусіди
Downstream — те, що підключається до брокера: лінки і брокери нижчих сайтів; їх вузли поруч у `down/`. Брокер сайту `d`, що підключається до нас, — вузол `wy/<site>/down/<d>`. Upstream — брокери, до яких підключається наш: `wy/<site>/up/<u>`. Ці вузли — посилання, а не копії: `is = wy:broker`, `attr.site`, `attr.root = "wy/<peer>"` і bool-точка `connected` (liveliness `wy/<peer>/sys/broker`). Ключі сусіда лишаються під його власним ім'ям (`wy/<peer>/…`); клієнт іде за `attr.root`. Id лінка не може збігатися з іменем downstream-сайту.

## Селектори
`key?param=value&...` — параметри **не** впливають на маршрутизацію. Визначені:
| Параметр | Де | Значення |
|---|---|---|
| `view` | `~meta` | `list` \| `keys` \| `full` (default `full`) |
| `from`, `limit` | `~meta?view=list` | пагінація; `limit` ≤ 1000 |
| `match` | `~meta?view=keys` | `is:<code>;type:<code>;unit:<str>;tag:<str>` (AND) |
| `depth` | `~meta?view=keys` | 1..∞ (default ∞) |
| `rev` | `~meta` | повернути `status=ok,rev` без тіла, якщо не змінилось |
| `field` | `~set` | `cfg.<name>` \| `attr.<name>` — запис метаданих замість значення |
| `history`, `since` | `~val` | `history=<from>..<to>` RFC 3339 (дата — її північ UTC; порожній `<to>` — зараз) або `since=<from>` |
| `agg`, `window` | `~val?history` | `avg|min|max|sum|count|first|last|delta|and|or`; вікно `<n>s|m|h|d|w` (`5m`, `1h`) від `<from>`; `agg` без `window` — один рядок на весь діапазон, `window` без `agg` — перше значення вікна |
| `limit` | `~val?history` | рядків відповіді, 1..100 000 (default 10 000) |
| `close` | `~act/<a>` | `<rid>` — закрити стрім |
| `dry_run` | `sys/**/~act/*` | `true` |
