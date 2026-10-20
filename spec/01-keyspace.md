# 01 — Key-space

## Граматика
```
key        = "wy/" site "/" branch
site       = seg
branch     = "down/" link ("/" path)? ("/" suffix)?
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
Віртуальних префіксів (`up/`, `remote/`) немає. Ключ має одне ім'я на всіх брокерах mesh і в UI.

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
| `history` | `~val` | `<from>..<to>` RFC 3339 або `since=<ts>` |
| `agg`, `window` | `~val?history` | `avg|min|max|sum|count|first|last|delta`, `1m|5m|1h|1d` |
| `close` | `~act/<a>` | `<rid>` — закрити стрім |
| `dry_run` | `sys/**/~act/*` | `true` |
