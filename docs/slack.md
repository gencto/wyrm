# Slack link

`links/slack`, packages `slack` (WASM) and `slack-process`; bots, recipients and templates as in
[messenger.md](messenger.md). ADR 0039.

## Token and network

Create a Slack app, add the bot scope `chat:write` (and `reactions:write`, `pins:write` for
those raw methods), install it to the workspace and copy the *Bot User OAuth Token*
(`xoxb-…`): `<bot>` ▸ Set Token. `net`: `slack.com:443`. Invite the bot to each channel it posts
in (`/invite @bot`).

## Recipients

`chat`: a channel id (`C0123456789`, from the channel's details). `thread`: a `thread_ts`
(`1700000000.000100`) to post in a thread.

## Templates

Formats `mrkdwn` (default; values escaped as `&amp;`, `&lt;`, `&gt;`) and `plain`. `blocks`
takes Block Kit JSON, an array; put placeholders inside JSON strings
(`"text": "*{{who}}* is at {{temp:.1}}"`). A value filled in there is escaped for mrkdwn first
(`&amp;`, `&lt;`, `&gt;`) and then for JSON, so it can be neither a mention (`<!channel>`) nor a
link (`<https://…|text>`); in a `plain_text` object Slack shows those entities as the characters.
`text` is the notification fallback. A `photo` is an image block; a `document` a link; a `location` an
OpenStreetMap link. `buttons` are links only (an actions block). `preview` turns unfurls on.

## Raw requests

`send_raw {method, params}` (config) fails closed: only these methods, by exact name, are
offered: `chat.postMessage`, `chat.update`, `chat.delete`, `chat.meMessage`,
`chat.getPermalink`, `chat.scheduleMessage`, `chat.deleteScheduledMessage`, `reactions.add`,
`reactions.remove`, `reactions.get`, `pins.add`, `pins.remove`, `pins.list`,
`conversations.info` (all need `channel`) and `auth.test`. Every `channel`, `channel_id`, `user`
and `users` in the params must be a recipient's channel; a missing `channel` refuses the
request, and so do `file` and `file_comment` (their channel cannot be checked).

## Send only

A Slack bot does not read messages yet: receiving needs Socket Mode or the Events API
(ADR 0039), so it has no chat users, no `/command` buttons and no `user:<name>` recipients.
`429` and `ratelimited` hold the bot for 30 s; `invalid_auth`, `token_revoked`, `missing_scope`
make it `failed` until Set Token.
