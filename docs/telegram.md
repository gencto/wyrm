# Telegram link

`links/telegram`, packages `telegram` (WASM) and `telegram-process`; bots, recipients and
templates as in [messenger.md](messenger.md). ADR 0039.

## Token and network

@BotFather ▸ `/newbot` gives the token (`123456789:AA…`): `<bot>` ▸ Set Token. `net`:
`api.telegram.org:443` (or a local Bot API server named in `api_url`). Turn the bot's *Group
Privacy* off in @BotFather only if paired users should command it in groups.

## Recipients

`chat`: a chat id (`-1001234567890`), `@channel`, or `user:<paired user>` (that user's private
chat, once paired). `thread`: a forum topic id. `commands: true` lets paired users command the
bot in that group.

To find a group's id: add the bot to the group; it is no recipient yet, so it leaves and the
link's log names the chat (`rejected chat -100… (supergroup)`). Add the recipient, add the bot
again.

## Templates

Formats `html` (default; values escaped as HTML entities), `markdown` (MarkdownV2; values
backslash-escaped; a message Telegram cannot parse goes again as plain text), `plain`. Kinds
`text`, `photo` / `document` (`media` = URL or `file_id`, `text` = caption ≤ 1024), `location`.
`buttons` take links and `/command`s (≤ 64 bytes after filling in), a command run for whoever
presses it. `silent`, `protect` (no forwarding or saving), `preview` (link previews).

## Raw requests

`send_raw {method, params}` (config) for the rest of the Bot API: `send*` (polls, media groups,
dice, …), `edit*`, `delete*`, `pin*`, `unpin*`, `forward*`, `copy*`, `stop*`,
`setMessageReaction`, `getChat`, `getMe`, `getChatMemberCount`. `getUpdates`, webhooks,
`logOut`, `close` and `setMyCommands` are not offered: they would take the bot's updates from
the link.

```json
{"method": "sendPoll", "params": "{\"chat_id\": -1001234567890, \"question\": \"Shift OK?\", \"options\": [\"yes\", \"no\"]}"}
```

## Updates

The link reads `getUpdates` every `poll_s` (3 s) — no webhook, no inbound port, works behind
NAT; the next offset is kept in the link's store, so a restart never runs a command twice.
`commands: false` makes a send-only bot (no polling). A webhook set on the same token by
another client makes Telegram answer 409, shown as the bot's `error`.

## Chat users

Nobody, until an operator invites them. Telegram bots are public: anyone can write to one or add
it to a group, so the messenger ignores everyone it does not know.

1. ▸ **Invite User** {name, level, select} (config). `level`: `read` (`/get`) or `write` (also
   `/set`, `/do`). `select`: the keys their commands may name, one per line. You cannot invite
   anyone beyond your own rights.
2. The answer shows a **pairing code** once, valid 15 minutes, single use. Give it to that person
   only (not in a group chat).
3. They open a private chat with the bot and send `/start ABCDE-FGHJK`. The bot binds their
   Telegram account (its numeric id) to the user; `users/<name>/status` becomes `active`.

Then, in the private chat:

```text
/get downstream/plc1/boiler/temp     the value, its quality and time
/set downstream/plc1/boiler/sp 65    write (level write)
/do downstream/alarm/boiler acknowledge
/whoami   /help
```

A command runs only if **all three** allow it: the user's level and keys, the rights of the
operator who invited (or last edited) them, and the link's grants. The messenger itself is never
written from a chat.

- Groups: commands work only in a recipient with `commands: true`, and only from paired users.
  Groups the bot is added to that are no recipient are left.
- A code sent in a group is void at once; 5 wrong codes lock an account out for an hour.
- Lost phone or new account: ▸ **New Pairing Code** (unpairs the old account). ▸ Disable /
  Enable / Edit / Remove at any time.
- Every rejected update counts in `<bot>/rejected` and the log; every command is logged with the
  user and key (never values). 20 commands a minute per user (`rate_per_min`).

Slack bots send only, for now (receiving needs Socket Mode; ADR 0039).


