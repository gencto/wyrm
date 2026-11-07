# Messenger: Telegram and Slack bots

The messenger link sends messages from the site to Telegram and Slack — alarms, reports, values —
and lets paired Telegram users ask for values or switch things from their phone. Design and the
reasoning behind it: ADR 0037.

## Install

The messenger is a package, not built into `wyrmd` (it reaches the internet with a third-party
token, so a site installs it on purpose):

1. `sys/links` ▸ Install Link ▸ from Repository: `messenger` (WASM) or `messenger-process`.
2. Give it network: `api.telegram.org:443, slack.com:443` in the link's `net`.
3. Grant what templates and chat users may name (`sys/links/<id>/~act/grant`): `read` on, say,
   `wy/<site>/downstream/**`; `write` on the points chat users may `/set` or `/do`.

## A bot

`downstream/messenger` ▸ **Add Telegram Bot** or **Add Slack Bot** {name}, then on the bot
▸ **Set Token**:

- Telegram: the token from @BotFather (`123456789:AA…`).
- Slack: the bot user OAuth token (`xoxb-…`, scope `chat:write`); invite the bot to each channel.

`status` goes `no_token → checking → ready`; `username` shows whose bot it is. ▸ Test Connection
checks again. The token is kept in the link's sealed store, never shown. Edit fields: `api_url`
(a local Bot API server works), `ca_pem`, `timeout_ms`, `format` (the default markup),
`queue_max`, and for Telegram `commands`, `poll_s`, `leave_unknown`, `rate_per_min`. An Edit that
moves `api_url` or `ca_pem` deletes the token: set it again.

## Recipients

The bot writes only to recipients. ▸ **Add Recipient** {name, chat, thread, silent, commands}:

| Platform | `chat` | `thread` |
|---|---|---|
| Telegram | a chat id (`-1001234567890`), `@channel`, or `user:<paired user>` | forum topic id |
| Slack | a channel id (`C0123456789`) | `thread_ts` |

To find a Telegram group's id, add the bot, send a message in the group, and read `rejected` /
the link's log: the bot reports the chat it left. Add the recipient, then add the bot again.

## Templates

▸ **Add Template** turns a message into a node with its own Send form:

```text
name     high_temp
kind     text                     (text | photo | document | location)
format   html                     (Telegram html | markdown | plain; Slack mrkdwn | plain)
text     🔥 <b>{{who}}</b>: {{temp:.1}} °C (limit {{limit}}) at {{now}}
values   temp = wy/plant/downstream/plc1/boiler/temp
         who  = wy/plant/downstream/plc1/boiler/name
buttons  Trend | https://grafana.example/d/boiler ;; Ack | /do downstream/alarm/boiler acknowledge
to       ops_group
silent   false   protect false   preview false
```

- `{{name}}` — a variable of the send (`limit` above): the Send form has a field for it.
- `{{alias}}` — a live value from `values` (`{{alias:.1}}` decimals, `{{alias.q}}` quality,
  `{{alias.t}}` time); `n/a` until it has one.
- `{{site}}`, `{{bot}}`, `{{now}}`.
- Values are **escaped for the format**: a device named `<Boiler & Co>` shows as such and never
  breaks the HTML. MarkdownV2 is strict: if Telegram cannot parse a message it is sent once more
  as plain text (the log says so).
- `buttons`: a row per line, `;;` between buttons. `https://…` opens a link; `/command` runs a
  chat command for whoever presses it, within that person's own pairing.
- Slack: `blocks` takes Block Kit JSON; put placeholders inside JSON strings
  (`"text": "*{{who}}* is at {{temp:.1}}"`). `text` is the notification fallback.
- `photo` / `document`: `media` is an `https://` URL (Telegram also takes a `file_id`); `text` is
  the caption. `location`: `lat`, `lon` (numbers or placeholders).

Send it: `templates/high_temp ▸ send {limit: 80}` (write) — from a flow `invoke` node, the alarm
link or by hand; `to` overrides the template's recipients. ▸ **Preview** returns the request it
would make, without sending.

A template keeps the rights of whoever added or last edited it: `values` must be readable by
them.

### Ad hoc and raw

- `<bot> ▸ send {to, text, format, kind, media, lat, lon, silent}` and
  `recipients/<r> ▸ send {text}` (write): a one-off message; only `{{site}}`, `{{bot}}`,
  `{{now}}` are filled in.
- `<bot> ▸ send_raw {method, params}` (config): any other API method — polls, media groups,
  edits, pins, reactions:

  ```json
  {"method": "sendPoll", "params": "{\"chat_id\": -1001234567890, \"question\": \"Shift OK?\", \"options\": [\"yes\", \"no\"]}"}
  ```

  The chat must be a recipient's. `getUpdates`, webhooks and `logOut` are not offered.

## Who may talk to a Telegram bot

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

Slack bots send only, for now (receiving needs Socket Mode; ADR 0037).

## Status and limits

`<bot>/{status, error, sent, failed, dropped, queued, rejected, last_sent}`, totals in `stats/`.
`429 Too Many Requests` holds the bot as long as the platform asks; network errors back off up to
a minute and keep the message (5 attempts); refused messages are dropped and counted `failed`.
Telegram gets at most one message per chat per second. Up to 8 bots, 64 recipients, 64 templates
and 100 users per bot.
