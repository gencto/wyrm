# Messenger links: bots, recipients, templates

The messenger links send messages from the site to chat platforms — alarms, reports, values —
and, where the platform allows, let paired chat users ask for values or switch things. Each
platform is a link of its own on one shared core (`crates/wyrm-messenger`); this page is what
they share. Design and reasoning: ADR 0037.

| Link | Packages | Guide | Can |
|---|---|---|---|
| `telegram` | `telegram` (WASM), `telegram-process` | [telegram.md](telegram.md) | send; chat users with `/get`, `/set`, `/do`; command buttons |
| `slack` | `slack` (WASM), `slack-process` | [slack.md](slack.md) | send; mrkdwn and Block Kit |

## Install

A messenger link is a package, not built into `wyrmd` (it reaches the internet with a
third-party token, so a site installs it on purpose):

1. `sys/links` ▸ Install Link ▸ from Repository: `telegram` / `slack` (WASM) or the
   `-process` package.
2. Give it network: `api.telegram.org:443` or `slack.com:443` in the link's `net`.
3. Grant what templates (and chat users) may name (`sys/links/<id>/~act/grant`): `read` on,
   say, `wy/<site>/downstream/**`; `write` on the points chat users may `/set` or `/do`.

## A bot

`downstream/<link>` ▸ **Add … Bot** {name}, then on the bot ▸ **Set Token** (the platform's
guide says which token).

`status` goes `no_token → checking → ready`; `username` shows whose bot it is. ▸ Test Connection
checks again. The token is kept in the link's sealed store, never shown. Edit fields: `api_url`, `ca_pem`, `timeout_ms`, `format` (the default markup),
`queue_max`, and on platforms that read updates `commands`, `poll_s`, `leave_unknown`,
`rate_per_min`. An Edit that
moves `api_url` or `ca_pem` deletes the token: set it again.

## Recipients

The bot writes only to recipients. ▸ **Add Recipient** {name, chat, thread, silent} (and
`commands` where the platform reads updates); the platform's guide gives the forms of `chat`
and `thread`.

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
- `<bot> ▸ send_raw {method, params}` (config): any other method of the platform's API the
  link offers (its guide lists them); the chat must be a recipient's.

## Who may talk to a bot

Nobody, until an operator invites them, on platforms that read updates (Telegram today): see
[telegram.md](telegram.md#chat-users). Unknown chats and accounts are ignored and counted in
`<bot>/rejected`.

## Status and limits

`<bot>/{status, error, sent, failed, dropped, queued, rejected, last_sent}`, totals in `stats/`.
`429 Too Many Requests` holds the bot as long as the platform asks; network errors back off up to
a minute and keep the message (5 attempts); refused messages are dropped and counted `failed`.
Pacing per chat is the platform's (Telegram: one message per chat per second). Up to 8 bots, 64 recipients, 64 templates
and 100 users per bot.
