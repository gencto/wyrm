# 01 — Key-space

## Граматика
```
key        = "wy/" site "/" branch
site       = seg
branch     = "downstream/" link ("/" path)? ("/" suffix)?
           | "downstream/" site ("/connected")? ("/" suffix)?  ; downstream broker node
           | "upstream/" site ("/connected")? ("/" suffix)?    ; upstream broker node
           | "dataflows/" flowid ("/" ("~def" | "~meta" | "~val" | "~act/" name | "nodes/" seg "/" suffix))?
           | "storage" ("/" path)? ("/" suffix)?                ; broker storage (0.2.2)
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

Розділи сайту мають повні імена, без скорочень: `downstream`, `upstream`, `dataflows`, `sys`, `pub` (0.2.0; до неї — `down`, `up`, `flows`). Брокер переносить збережені ключі зі старими іменами (гранти, спостереження історії) під нові; збережені потоки треба розгорнути знову, бо їхні proofs підписані для старих ключів.

## Сховище брокера
`wy/<site>/storage/**` — вузли і значення, які створюють люди (як `/data` брокера DSA, ADR 0017): папки, значення типу `string`, `number`, `bool`, `array`, `map`, `binary`, `dynamic` з дією `~set`, дії `add_node`, `add_value`, `publish`, `delete`, `rename`, `duplicate`, `export`, `import`. Кожна дія і `~set` потребує `write`. Брокер зберігає дерево і останні значення між перезапусками. Id лінка `storage` зарезервований (0.2.2).

## Брокери-сусіди
Downstream — те, що підключається до брокера: лінки і брокери нижчих сайтів; їх вузли поруч у `downstream/`. Брокер сайту `d`, що підключається до нас, — вузол `wy/<site>/downstream/<d>`. Upstream — брокери, до яких підключається наш: `wy/<site>/upstream/<u>`. Ці вузли — посилання, а не копії: `is = wy:broker`, `attr.site`, `attr.root = "wy/<peer>"` і bool-точка `connected` (liveliness `wy/<peer>/sys/broker`). Ключі сусіда лишаються під його власним ім'ям (`wy/<peer>/…`); клієнт іде за `attr.root`. Id лінка не може збігатися з іменем downstream-сайту.

Запити згори (0.2.3, ADR 0018): upstream може надсилати `~set` і `~act` у `downstream`, `dataflows`, `storage` нижчого сайту завжди, а в `sys` — лише коли нижчий сайт дозволив це для цього upstream (`allow_config`). `ptok` такого запиту має `site` нижчого сайту і підписаний ключем upstream. Брокер публікує ключі, якими підписують запити до нижчих сайтів, у `wy/<site>/sys/signing_keys` (`{<site>: [hex…]}`: свої і ті, що взяв від своїх upstream); нижчий сайт довіряє їм лише у своїх межах і на своїх рівнях.

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
