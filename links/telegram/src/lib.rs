//! `telegram`: Telegram bots (ADR 0039) as a portable link (ADR 0023), on the messenger core
//! (`wyrm-messenger`). This crate is the Telegram Bot API and what Telegram can do; bots,
//! recipients, templates, the queue, pairing and chat commands are the core's.
//!
//! - Requests: `POST <api>/bot<token>/<method>` with JSON (`sendMessage`, `sendPhoto`,
//!   `sendDocument`, `sendLocation`, `answerCallbackQuery`, `leaveChat`); markup HTML (default),
//!   MarkdownV2 or plain; forum topics, silent, protected, link previews, inline keyboards with
//!   links and `/command` buttons.
//! - Inbound: `getUpdates` polled (no webhook, no inbound port); messages, button presses, chats
//!   the bot was added to. Chat users pair by `/start <code>` in a private chat.
//! - `send_raw`: `send*`, `edit*`, `delete*`, `pin*`, `unpin*`, `forward*`, `copy*`, `stop*`,
//!   `setMessageReaction`, `getChat`, `getMe`, `getChatMemberCount`; never `getUpdates`, webhooks,
//!   `logOut`, `close`.
//!
//! Embedded as `Portable<TelegramLink>`, as a process (`--features process`) or as a WASM
//! component (`--features wasm`).

use serde_json::{json, Value as Json};
use wyrm_messenger::api::{parse_json, Body, Chat, Fail, Outgoing, Platform, RawMethod, Update};
use wyrm_messenger::model::Format;
use wyrm_messenger::{render, Messenger};

/// Telegram's limits on a message text and on a caption (characters).
pub const TG_TEXT_MAX: usize = 4096;
pub const TG_CAPTION_MAX: usize = 1024;

/// The link's app.
pub type TelegramLink = Messenger<Telegram>;

pub struct Telegram;

impl Chat for Telegram {
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    const PLATFORM: &'static Platform = &TELEGRAM;
}

pub const TELEGRAM: Platform = Platform {
    name: "telegram",
    display: "Telegram",
    default_api: "https://api.telegram.org",
    formats: &[Format::Html, Format::Markdown, Format::Plain],
    token_about: "The bot token from @BotFather (123456:ABC…).",
    token_hint: "token: 123456789:AA… from @BotFather",
    chat_about: "A chat id (-1001234567890), @channel, or user:<paired user>.",
    thread_about: "A forum topic id (message_thread_id).",
    raw_about: "A Bot API method: sendPoll, sendMediaGroup, editMessageText, pinChatMessage, …",
    identify: "getMe",
    inbound: true,
    command_buttons: true,
    blocks: false,
    // one message per chat per second
    per_chat_us: 1_000_000,
    bearer: false,
    check_token,
    check_chat,
    check_thread,
    path: |base, token, method| format!("{base}/bot{token}/{method}"),
    request: telegram,
    reply: telegram_reply,
    message_id: telegram_message_id,
    edit_unchanged: |m| m.contains("message is not modified"),
    edit_gone: |m| {
        m.contains("message to edit not found")
            || m.contains("message can't be edited")
            || m.contains("MESSAGE_ID_INVALID")
    },
    identity: |me| me["username"].as_str().unwrap_or("").to_owned(),
    raw_methods: RAW_METHODS,
    // every Bot API param that names a chat or an account
    raw_chat_params: &["chat_id", "from_chat_id", "user_id", "sender_chat_id"],
    // inline and business messages name no chat the link can check
    raw_refused_params: &["inline_message_id", "business_connection_id"],
    poll,
    updates,
};

/// `<bot id>:<secret>`.
fn check_token(t: &str) -> bool {
    t.split_once(':').is_some_and(|(id, rest)| {
        !id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()) && rest.len() >= 20
    })
}

fn check_chat(chat: &str) -> Result<(), String> {
    let digits = chat.strip_prefix('-').unwrap_or(chat);
    let ok = (!digits.is_empty()
        && digits.len() <= 20
        && digits.bytes().all(|b| b.is_ascii_digit()))
        || chat.strip_prefix('@').is_some_and(|u| {
            (5..=32).contains(&u.len()) && u.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
        });
    if ok {
        Ok(())
    } else {
        Err(format!(
            "chat {chat:?}: a chat id (-1001234567890), @channel or user:<paired user>"
        ))
    }
}

fn check_thread(t: &str) -> Result<(), String> {
    t.parse::<u64>()
        .map(|_| ())
        .map_err(|_| "thread: a forum topic id (a number)".into())
}

const CHAT: &[&str] = &["chat_id"];
const FROM: &[&str] = &["chat_id", "from_chat_id"];

/// What `send_raw` may call, by exact name (fail closed): messages in a known chat, never
/// what would take the updates or the bot away from the link (`getUpdates`, webhooks,
/// `logOut`, `close`, commands, the bot's profile).
const RAW_METHODS: &[RawMethod] = &[
    RawMethod::new("sendMessage", CHAT),
    RawMethod::new("sendPhoto", CHAT),
    RawMethod::new("sendAudio", CHAT),
    RawMethod::new("sendDocument", CHAT),
    RawMethod::new("sendVideo", CHAT),
    RawMethod::new("sendAnimation", CHAT),
    RawMethod::new("sendVoice", CHAT),
    RawMethod::new("sendVideoNote", CHAT),
    RawMethod::new("sendMediaGroup", CHAT),
    RawMethod::new("sendLocation", CHAT),
    RawMethod::new("sendVenue", CHAT),
    RawMethod::new("sendContact", CHAT),
    RawMethod::new("sendPoll", CHAT),
    RawMethod::new("sendDice", CHAT),
    RawMethod::new("sendSticker", CHAT),
    RawMethod::new("sendChatAction", CHAT),
    RawMethod::new("editMessageText", CHAT),
    RawMethod::new("editMessageCaption", CHAT),
    RawMethod::new("editMessageMedia", CHAT),
    RawMethod::new("editMessageLiveLocation", CHAT),
    RawMethod::new("stopMessageLiveLocation", CHAT),
    RawMethod::new("editMessageReplyMarkup", CHAT),
    RawMethod::new("stopPoll", CHAT),
    RawMethod::new("deleteMessage", CHAT),
    RawMethod::new("deleteMessages", CHAT),
    RawMethod::new("pinChatMessage", CHAT),
    RawMethod::new("unpinChatMessage", CHAT),
    RawMethod::new("unpinAllChatMessages", CHAT),
    RawMethod::new("forwardMessage", FROM),
    RawMethod::new("forwardMessages", FROM),
    RawMethod::new("copyMessage", FROM),
    RawMethod::new("copyMessages", FROM),
    RawMethod::new("setMessageReaction", CHAT),
    RawMethod::new("getChat", CHAT),
    RawMethod::new("getChatMemberCount", CHAT),
    RawMethod::new("getMe", &[]),
];

/// `getUpdates` after `offset`, without waiting (the link polls every `poll_s`).
fn poll(offset: i64, limit: u64) -> Option<(String, Json)> {
    Some((
        "getUpdates".into(),
        json!({
            "offset": offset,
            "timeout": 0,
            "limit": limit,
            "allowed_updates": ["message", "edited_message", "channel_post", "callback_query", "my_chat_member"],
        }),
    ))
}

fn tg_parse_mode(f: Format) -> Option<&'static str> {
    match f {
        Format::Html => Some("HTML"),
        Format::Markdown => Some("MarkdownV2"),
        Format::Plain | Format::Mrkdwn => None,
    }
}

fn tg_chat(chat: &str) -> Json {
    chat.parse::<i64>()
        .map(Json::from)
        .unwrap_or_else(|_| Json::String(chat.to_owned()))
}

/// `(method, body)` of a Telegram request.
pub fn telegram(m: &Outgoing) -> (String, Json) {
    if let Some(id) = m.edit.as_deref().filter(|_| m.editable()) {
        return telegram_edit(m, id);
    }
    let mut o = serde_json::Map::new();
    let mut put = |k: &str, v: Json| {
        o.insert(k.to_owned(), v);
    };
    let common = !matches!(m.body, Body::Raw { .. } | Body::Answer { .. });
    if common {
        put("chat_id", tg_chat(&m.chat));
    }
    let method = match &m.body {
        Body::Text { text, format } => {
            put("text", json!(render::cut(text, TG_TEXT_MAX)));
            if let Some(p) = tg_parse_mode(*format) {
                put("parse_mode", json!(p));
            }
            put("link_preview_options", json!({ "is_disabled": !m.preview }));
            "sendMessage"
        }
        Body::Photo {
            media,
            caption,
            format,
        }
        | Body::Document {
            media,
            caption,
            format,
        } => {
            let photo = matches!(m.body, Body::Photo { .. });
            put(if photo { "photo" } else { "document" }, json!(media));
            if !caption.is_empty() {
                put("caption", json!(render::cut(caption, TG_CAPTION_MAX)));
                if let Some(p) = tg_parse_mode(*format) {
                    put("parse_mode", json!(p));
                }
            }
            if photo {
                "sendPhoto"
            } else {
                "sendDocument"
            }
        }
        Body::Location { lat, lon } => {
            put("latitude", json!(lat));
            put("longitude", json!(lon));
            "sendLocation"
        }
        Body::Blocks { text, .. } => {
            put("text", json!(render::cut(text, TG_TEXT_MAX)));
            "sendMessage"
        }
        Body::Raw { method, params } => return (method.clone(), params.clone()),
        Body::Answer { id, text } => {
            put("callback_query_id", json!(id));
            if !text.is_empty() {
                put("text", json!(render::cut(text, 200)));
            }
            return ("answerCallbackQuery".into(), Json::Object(o));
        }
        Body::Leave => return ("leaveChat".into(), Json::Object(o)),
    };
    if let Some(t) = m.thread.as_deref().and_then(|t| t.parse::<u64>().ok()) {
        put("message_thread_id", json!(t));
    }
    if m.silent {
        put("disable_notification", json!(true));
    }
    if m.protect {
        put("protect_content", json!(true));
    }
    if !m.buttons.is_empty() {
        put("reply_markup", inline_keyboard(&m.buttons));
    }
    (method.into(), Json::Object(o))
}

/// The edit in place of message `id`: `editMessageText` for a text, `editMessageCaption` for a
/// photo's or a document's caption (the media stays). An edit takes no thread, silence or
/// protection: the message keeps those it was sent with.
fn telegram_edit(m: &Outgoing, id: &str) -> (String, Json) {
    let mut o = serde_json::Map::new();
    o.insert("chat_id".into(), tg_chat(&m.chat));
    o.insert(
        "message_id".into(),
        id.parse::<i64>().map_or_else(|_| json!(id), Json::from),
    );
    let method = match &m.body {
        Body::Photo {
            caption, format, ..
        }
        | Body::Document {
            caption, format, ..
        } => {
            o.insert(
                "caption".into(),
                json!(render::cut(caption, TG_CAPTION_MAX)),
            );
            if let Some(p) = tg_parse_mode(*format) {
                o.insert("parse_mode".into(), json!(p));
            }
            "editMessageCaption"
        }
        Body::Text { text, format } => {
            o.insert("text".into(), json!(render::cut(text, TG_TEXT_MAX)));
            if let Some(p) = tg_parse_mode(*format) {
                o.insert("parse_mode".into(), json!(p));
            }
            o.insert(
                "link_preview_options".into(),
                json!({ "is_disabled": !m.preview }),
            );
            "editMessageText"
        }
        Body::Blocks { text, .. } => {
            o.insert("text".into(), json!(render::cut(text, TG_TEXT_MAX)));
            "editMessageText"
        }
        // never asked: only what `Outgoing::editable` says
        _ => "editMessageText",
    };
    if !m.buttons.is_empty() {
        o.insert("reply_markup".into(), inline_keyboard(&m.buttons));
    }
    (method.into(), Json::Object(o))
}

fn inline_keyboard(buttons: &[Vec<wyrm_messenger::model::Button>]) -> Json {
    let rows: Vec<Json> = buttons
        .iter()
        .map(|row| {
            Json::Array(
                row.iter()
                    .map(|b| {
                        if b.is_url() {
                            json!({ "text": b.label, "url": b.target })
                        } else {
                            json!({ "text": b.label, "callback_data": b.target })
                        }
                    })
                    .collect(),
            )
        })
        .collect();
    json!({ "inline_keyboard": rows })
}

/// The `message_id` a send's result names.
fn telegram_message_id(result: &Json) -> Option<String> {
    result["message_id"].as_i64().map(|i| i.to_string())
}

/// A Telegram reply: `{ok: true, result}` or `{ok: false, error_code, description, parameters}`.
pub fn telegram_reply(status: u16, body: &[u8]) -> Result<Json, Fail> {
    let j = parse_json(body);
    if let Some(j) = &j {
        if j["ok"] == json!(true) {
            return Ok(j["result"].clone());
        }
    }
    let desc = j
        .as_ref()
        .and_then(|j| j["description"].as_str())
        .unwrap_or("no description")
        .chars()
        .take(200)
        .collect::<String>();
    let msg = format!("telegram {status}: {desc}");
    Err(match status {
        401 | 404 => Fail::Auth(msg),
        429 => {
            let s = j
                .as_ref()
                .and_then(|j| j["parameters"]["retry_after"].as_u64())
                .unwrap_or(5);
            Fail::Retry {
                after_ms: s.clamp(1, 3600) * 1000,
                msg,
            }
        }
        400 if desc.contains("can't parse entities") => Fail::Markup(msg),
        409 => Fail::Transient(format!(
            "{msg} (another client reads this bot's updates, or a webhook is set)"
        )),
        400..=499 => Fail::Rejected(msg),
        _ => Fail::Transient(msg),
    })
}

/// The `result` of `getUpdates`.
pub fn updates(result: &Json) -> Vec<Update> {
    let Json::Array(a) = result else {
        return Vec::new();
    };
    a.iter()
        .filter_map(|u| {
            let update_id = u["update_id"].as_i64()?;
            let chat_of = |c: &Json| -> Option<(i64, String)> {
                Some((
                    c["id"].as_i64()?,
                    c["type"].as_str().unwrap_or("").to_owned(),
                ))
            };
            if let Some(cb) = u.get("callback_query") {
                let msg_chat = chat_of(&cb["message"]["chat"]);
                return Some(Update::Callback {
                    update_id,
                    id: cb["id"].as_str().unwrap_or("").to_owned(),
                    chat_id: msg_chat.as_ref().map(|c| c.0),
                    chat_type: msg_chat.map(|c| c.1).unwrap_or_default(),
                    from_id: cb["from"]["id"].as_i64()?,
                    data: cb["data"].as_str().unwrap_or("").to_owned(),
                });
            }
            let msg = u
                .get("message")
                .or_else(|| u.get("channel_post"))
                .or_else(|| u.get("edited_message"));
            if let Some(m) = msg {
                if let (Some((chat_id, chat_type)), Some(text)) =
                    (chat_of(&m["chat"]), m["text"].as_str())
                {
                    return Some(Update::Message {
                        update_id,
                        chat_id,
                        chat_type,
                        from_id: m["from"]["id"].as_i64(),
                        from_is_bot: m["from"]["is_bot"].as_bool().unwrap_or(false),
                        text: text.to_owned(),
                    });
                }
                return Some(Update::Other {
                    update_id,
                    chat: chat_of(&m["chat"]),
                });
            }
            let chat = u.get("my_chat_member").and_then(|c| chat_of(&c["chat"]));
            Some(Update::Other { update_id, chat })
        })
        .collect()
}

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(TelegramLink);

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_messenger::model::Button;

    fn msg(body: Body) -> Outgoing {
        Outgoing {
            edit: None,
            slot: None,
            recipient: None,
            chat: "-100123".into(),
            thread: Some("7".into()),
            body,
            buttons: vec![vec![
                Button {
                    label: "Open".into(),
                    target: "https://x.example".into(),
                },
                Button {
                    label: "Ack".into(),
                    target: "/do wy/s/a ack".into(),
                },
            ]],
            silent: true,
            protect: true,
            preview: false,
            origin: "t".into(),
            attempts: 0,
        }
    }

    #[test]
    fn telegram_requests() {
        let (m, b) = telegram(&msg(Body::Text {
            text: "<b>hi</b>".into(),
            format: Format::Html,
        }));
        assert_eq!(m, "sendMessage");
        assert_eq!(b["chat_id"], json!(-100123));
        assert_eq!(b["parse_mode"], "HTML");
        assert_eq!(b["message_thread_id"], 7);
        assert_eq!(b["disable_notification"], true);
        assert_eq!(b["protect_content"], true);
        assert_eq!(b["link_preview_options"]["is_disabled"], true);
        assert_eq!(
            b["reply_markup"]["inline_keyboard"][0][0]["url"],
            "https://x.example"
        );
        assert_eq!(
            b["reply_markup"]["inline_keyboard"][0][1]["callback_data"],
            "/do wy/s/a ack"
        );
        let (m, b) = telegram(&msg(Body::Photo {
            media: "https://x/p.png".into(),
            caption: "c".into(),
            format: Format::Markdown,
        }));
        assert_eq!(
            (m.as_str(), &b["photo"], &b["parse_mode"]),
            ("sendPhoto", &json!("https://x/p.png"), &json!("MarkdownV2"))
        );
        let (m, b) = telegram(&msg(Body::Location {
            lat: 50.45,
            lon: 30.52,
        }));
        assert_eq!(
            (m.as_str(), b["latitude"].as_f64()),
            ("sendLocation", Some(50.45))
        );
        let mut o = msg(Body::Text {
            text: "x".repeat(5000),
            format: Format::Plain,
        });
        o.chat = "@plant_alerts".into();
        let (_, b) = telegram(&o);
        assert_eq!(b["chat_id"], "@plant_alerts");
        assert_eq!(b["text"].as_str().unwrap().chars().count(), TG_TEXT_MAX);
        assert!(b.get("parse_mode").is_none());
    }
    #[test]
    fn replies_are_sorted() {
        assert_eq!(
            telegram_reply(200, br#"{"ok":true,"result":{"id":1}}"#).unwrap()["id"],
            1
        );
        let r = |s, b: &[u8]| telegram_reply(s, b);
        assert!(matches!(
            r(401, br#"{"ok":false,"description":"Unauthorized"}"#),
            Err(Fail::Auth(_))
        ));
        assert!(matches!(
            r(404, br#"{"ok":false,"description":"Not Found"}"#),
            Err(Fail::Auth(_))
        ));
        assert_eq!(
            r(429, br#"{"ok":false,"description":"Too Many Requests","parameters":{"retry_after":12}}"#),
            Err(Fail::Retry { after_ms: 12_000, msg: "telegram 429: Too Many Requests".into() })
        );
        assert!(matches!(
            r(
                400,
                br#"{"ok":false,"description":"Bad Request: can't parse entities: x"}"#
            ),
            Err(Fail::Markup(_))
        ));
        assert!(matches!(
            r(
                403,
                br#"{"ok":false,"description":"Forbidden: bot was blocked by the user"}"#
            ),
            Err(Fail::Rejected(_))
        ));
        assert!(matches!(
            r(409, br#"{"ok":false,"description":"Conflict"}"#),
            Err(Fail::Transient(_))
        ));
        assert!(matches!(r(502, b"bad gateway"), Err(Fail::Transient(_))));
    }
    #[test]
    fn raw_methods_are_bounded() {
        assert!(TELEGRAM.raw_method_allowed("sendPoll").is_ok());
        assert!(TELEGRAM.raw_method_allowed("editMessageText").is_ok());
        assert!(TELEGRAM.raw_method_allowed("getUpdates").is_err());
        assert!(TELEGRAM.raw_method_allowed("setWebhook").is_err());
        assert!(TELEGRAM.raw_method_allowed("../x").is_err());
        // names a prefix list would have let through
        for m in [
            "deleteWebhook",
            "deleteMyCommands",
            "sendGift",
            "editChatInviteLink",
        ] {
            assert!(TELEGRAM.raw_method_allowed(m).is_err(), "{m}");
        }
    }
    #[test]
    fn raw_requests_name_every_chat_and_fail_closed() {
        let m = |n| TELEGRAM.raw_method_allowed(n).unwrap();
        let chats = |n, p: Json| TELEGRAM.raw_chats(m(n), &p);
        assert_eq!(
            chats(
                "forwardMessage",
                json!({"chat_id": 1, "from_chat_id": -5, "message_id": 2})
            ),
            Ok(vec!["1".to_owned(), "-5".to_owned()])
        );
        // a chat in a secondary field is named even where the method does not list it
        assert_eq!(
            chats(
                "sendMessage",
                json!({"chat_id": 1, "user_id": 9, "text": "x"})
            ),
            Ok(vec!["1".to_owned(), "9".to_owned()])
        );
        // the method's chat missing, a chat that cannot be checked, a chat of the wrong shape
        assert!(chats("sendPoll", json!({"question": "q"})).is_err());
        assert!(chats("forwardMessage", json!({"chat_id": 1, "message_id": 2})).is_err());
        assert!(chats(
            "editMessageText",
            json!({"inline_message_id": "x", "text": "y"})
        )
        .is_err());
        assert!(chats("sendMessage", json!({"chat_id": [1, 2]})).is_err());
        assert_eq!(chats("getMe", json!({})), Ok(vec![]));
    }
    #[test]
    fn updates_are_read() {
        let r = json!([
            {"update_id": 5, "message": {"chat": {"id": 42, "type": "private"}, "from": {"id": 42, "is_bot": false}, "text": "/start ABC"}},
            {"update_id": 6, "callback_query": {"id": "cb1", "from": {"id": 42}, "data": "/get x", "message": {"chat": {"id": 42, "type": "private"}}}},
            {"update_id": 7, "my_chat_member": {"chat": {"id": -100, "type": "supergroup"}}},
            {"update_id": 8, "message": {"chat": {"id": -100, "type": "group"}, "photo": []}}
        ]);
        let u = updates(&r);
        assert_eq!(u.len(), 4);
        assert!(
            matches!(&u[0], Update::Message { text, from_id: Some(42), .. } if text == "/start ABC")
        );
        assert!(matches!(&u[1], Update::Callback { data, from_id: 42, .. } if data == "/get x"));
        assert_eq!(
            u[2],
            Update::Other {
                update_id: 7,
                chat: Some((-100, "supergroup".into()))
            }
        );
        assert_eq!(u[3].id(), 8);
    }
}
