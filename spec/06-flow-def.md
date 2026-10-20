# 06 — `flows/<id>/~def`

CBOR map (на дроті) / JSON (у конфігах і UI) — одна схема. Рядкові ключі (користувацький вміст).

```
{
  "id": tstr,                 // = сегмент ключа
  "version": uint,            // монотонно; engine ігнорує ≤ поточної
  "enabled": bool,            // default true
  "description": tstr?,
  "nodes": { <node_id>: { "type": tstr, ...config, "placement": "local"|"process"|"wasm"? } },
  "edges": [ [ "<node>.<port>", "<node>.<port>" ] ],
  "policy": { "overflow": "drop_oldest"|"drop_newest"|"block", "queue": uint, "state_flush_s": uint, "restart": {"backoff_max_s": uint} },
  "permissions": { "token": tstr, "maxperm": uint }
}
```
Порти: `<node>.out`, `<node>.in`, іменовані `<node>.in.<name>` / `<node>.out.<name>` (у `expression` — `in.<input>`; у `alarm` — `out`, `event`).

## Валідація (порядок, перша помилка зупиняє)
1. схема; 2. унікальність `node_id`, `[A-Za-z0-9_]+`; 3. тип ноди є в реєстрі, конфіг за схемою типу; 4. ребра → існуючі порти, сумісні типи; 5. ациклічність (цикл дозволений лише через `delay`); 6. rhai компілюється; 7. `permissions.maxperm` ≥ мін. рівня всіх `invoke/set`-нод; 8. ліміти пам'яті (`window.max_samples` сума).

Помилка → `flows/<id>/~val = {state: 2 (error), error: "<path>: <msg>"}`; стара версія працює.

## `~val` флоу
`{0: {"state": 0 running | 1 stopped | 2 error, "error": tstr?, "version": uint, "since": uint}, 1: q, 2: t}`
