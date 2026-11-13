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

A person can also get messages without pairing: a recipient whose `chat` is their numeric
Telegram id (`123456789`). They must have written to the bot first (Telegram lets a bot open no
chat); until they are a recipient, the link's log names them (`rejected account 123456789: not
paired`). They can receive only: commands need pairing (Chat users, below).

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

`send_raw {method, params}` (config) for the rest of the Bot API. It fails closed: only these
methods, by exact name, are offered:

- `sendMessage`, `sendPhoto`, `sendAudio`, `sendDocument`, `sendVideo`, `sendAnimation`,
  `sendVoice`, `sendVideoNote`, `sendMediaGroup`, `sendLocation`, `sendVenue`, `sendContact`,
  `sendPoll`, `sendDice`, `sendSticker`, `sendChatAction`;
- `editMessageText`, `editMessageCaption`, `editMessageMedia`, `editMessageLiveLocation`,
  `stopMessageLiveLocation`, `editMessageReplyMarkup`, `stopPoll`, `deleteMessage`,
  `deleteMessages`, `pinChatMessage`, `unpinChatMessage`, `unpinAllChatMessages`,
  `setMessageReaction`, `getChat`, `getChatMemberCount` (all need `chat_id`);
- `forwardMessage`, `forwardMessages`, `copyMessage`, `copyMessages` (need `chat_id` and
  `from_chat_id`);
- `getMe`.

Every `chat_id`, `from_chat_id`, `user_id` and `sender_chat_id` in the params must be a
recipient's chat or a paired user's, whether the method needs it or not; a method's chat param
that is missing refuses the request, and so do `inline_message_id` and `business_connection_id`
(their chat cannot be checked). `getUpdates`, webhooks, `logOut`, `close`, commands and the bot's
profile are never offered: they would take the bot's updates or the bot itself from the link.

```json
{"method": "sendPoll", "params": "{\"chat_id\": -1001234567890, \"question\": \"Shift OK?\", \"options\": [\"yes\", \"no\"]}"}
```

## Updates

The link reads `getUpdates` every `poll_s` (3 s) — no webhook, no inbound port, works behind
NAT; the next offset is kept in the link's store, so a restart never runs a command twice.
`commands: false` makes a send-only bot (no polling). A webhook set on the same token by
another client makes Telegram answer 409, shown as the bot's `error`.

A failed `getUpdates` holds only the reading: `status` stays `ready` while messages go out,
`error` says `updates: <why>`, and the reading tries again after 1 s, doubled up to a minute.
`status` is `waiting` only when sending waits (a 429, a network error on a send).

## Chat users

Nobody, until an operator invites them. Telegram bots are public: anyone can write to one or add
it to a group, so the messenger ignores everyone it does not know.

1. ▸ **Invite User** {name, level, select} (config). `level`: `read` (`/get`) or `write` (also
   `/set`, `/do`). `select`: the keys their commands may name, one per line, each a full node
   key without wildcards (`wy/plant/downstream/plc1`, `wy/plant/storage/dvpsm/cmd`); a key
   covers its whole subtree. Empty: `wy/<site>/downstream`. You cannot invite anyone beyond
   your own rights, and a command works only where the link's grants reach too (`sys/links/<id>`
   ▸ Grant Access; storage since ADR 0046), so give the link the same keys.
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
  Enable / Edit / Remove at any time. New Pairing Code, Enable and Edit hand the user's rights
  to an account, so only an operator who holds the user's level on all its keys may run them.
- Every rejected update counts in `<bot>/rejected` and the log; every command is logged with the
  user and key (never values). 20 commands a minute per user (`rate_per_min`).

Slack bots send only, for now (receiving needs Socket Mode; ADR 0039).


