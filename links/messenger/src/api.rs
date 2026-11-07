//! The wire of the two platforms: Telegram Bot API (`POST <api>/bot<token>/<method>`, JSON) and
//! Slack Web API (`POST <api>/api/<method>`, `Authorization: Bearer xoxb-…`, JSON). Requests are
//! built from an [`Outgoing`] message and replies sorted into what the bot does next ([`Fail`]).
//! Pure: no I/O, no clock.

use serde_json::{json, Value as Json};
use wyrm_core::Value;

use crate::model::{Button, Format, Kind};

/// Telegram's limits on a message text and on a caption (characters).
pub const TG_TEXT_MAX: usize = 4096;
pub const TG_CAPTION_MAX: usize = 1024;
/// Slack's limit on `text`.
pub const SLACK_TEXT_MAX: usize = 40_000;

/// A tree value as JSON (bytes as hex).
pub fn json_value(v: &Value) -> Json {
    match v {
        Value::Null => Json::Null,
        Value::Bool(b) => Json::Bool(*b),
        Value::Int(i) => Json::from(*i),
        Value::UInt(u) => Json::from(*u),
        Value::Float(f) => serde_json::Number::from_f64(*f)
            .map(Json::Number)
            .unwrap_or(Json::Null),
        Value::Str(s) => Json::String(s.clone()),
        Value::Bytes(b) => Json::String(b.iter().map(|x| format!("{x:02x}")).collect()),
        Value::Array(a) => Json::Array(a.iter().map(json_value).collect()),
        Value::Map(m) => Json::Object(m.iter().map(|(k, v)| (k.clone(), json_value(v))).collect()),
    }
}

/// What a message carries, rendered.
#[derive(Debug, Clone, PartialEq)]
pub enum Body {
    Text {
        text: String,
        format: Format,
    },
    Photo {
        media: String,
        caption: String,
        format: Format,
    },
    Document {
        media: String,
        caption: String,
        format: Format,
    },
    Location {
        lat: f64,
        lon: f64,
    },
    /// Slack Block Kit; `text` is the notification fallback.
    Blocks {
        text: String,
        blocks: Json,
    },
    /// `send_raw`: a method and its parameters as given.
    Raw {
        method: String,
        params: Json,
    },
    /// Telegram: answer a button press (`answerCallbackQuery`).
    Answer {
        id: String,
        text: String,
    },
    /// Telegram: leave a chat that is no recipient (`leaveChat`).
    Leave,
}

/// One message waiting in a bot's queue.
#[derive(Debug, Clone, PartialEq)]
pub struct Outgoing {
    /// The platform's chat id (resolved: never `user:<name>`).
    pub chat: String,
    pub thread: Option<String>,
    pub body: Body,
    pub buttons: Vec<Vec<Button>>,
    pub silent: bool,
    pub protect: bool,
    pub preview: bool,
    /// Who it is for in errors: a recipient or template name, `reply`, `raw`.
    pub origin: String,
    pub attempts: u32,
}

impl Outgoing {
    pub fn text(chat: impl Into<String>, text: impl Into<String>, origin: &str) -> Self {
        Self {
            chat: chat.into(),
            thread: None,
            body: Body::Text {
                text: text.into(),
                format: Format::Plain,
            },
            buttons: Vec::new(),
            silent: false,
            protect: false,
            preview: false,
            origin: origin.to_owned(),
            attempts: 0,
        }
    }

    /// The same message without markup (after the platform could not parse it).
    pub fn plain(&self) -> Option<Self> {
        let mut m = self.clone();
        match &mut m.body {
            Body::Text { format, .. }
            | Body::Photo { format, .. }
            | Body::Document { format, .. }
                if *format != Format::Plain =>
            {
                *format = Format::Plain;
                Some(m)
            }
            _ => None,
        }
    }
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
            put("text", json!(crate::render::cut(text, TG_TEXT_MAX)));
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
                put(
                    "caption",
                    json!(crate::render::cut(caption, TG_CAPTION_MAX)),
                );
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
            put("text", json!(crate::render::cut(text, TG_TEXT_MAX)));
            "sendMessage"
        }
        Body::Raw { method, params } => return (method.clone(), params.clone()),
        Body::Answer { id, text } => {
            put("callback_query_id", json!(id));
            if !text.is_empty() {
                put("text", json!(crate::render::cut(text, 200)));
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
        let rows: Vec<Json> = m
            .buttons
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
        put("reply_markup", json!({ "inline_keyboard": rows }));
    }
    (method.into(), Json::Object(o))
}

/// `(method, body)` of a Slack request.
pub fn slack(m: &Outgoing) -> (String, Json) {
    let mut o = serde_json::Map::new();
    o.insert("channel".into(), json!(m.chat));
    let mut blocks: Vec<Json> = Vec::new();
    let (text, mrkdwn) = match &m.body {
        Body::Raw { method, params } => return (method.clone(), params.clone()),
        Body::Text { text, format } => (text.clone(), *format == Format::Mrkdwn),
        Body::Blocks { text, blocks: b } => {
            if let Json::Array(a) = b {
                blocks.extend(a.iter().cloned());
            }
            (text.clone(), true)
        }
        Body::Photo {
            media,
            caption,
            format,
        } => {
            blocks.push(json!({
                "type": "image",
                "image_url": media,
                "alt_text": if caption.is_empty() { "image" } else { caption.as_str() },
            }));
            (
                if caption.is_empty() { media.clone() } else { caption.clone() },
                *format == Format::Mrkdwn,
            )
        }
        Body::Document {
            media,
            caption,
            format,
        } => (
            if caption.is_empty() {
                format!("<{media}>")
            } else {
                format!("{caption}\n<{media}>")
            },
            *format == Format::Mrkdwn,
        ),
        Body::Location { lat, lon } => (
            format!("<https://www.openstreetmap.org/?mlat={lat}&mlon={lon}#map=16/{lat}/{lon}|{lat}, {lon}>"),
            true,
        ),
        Body::Answer { .. } | Body::Leave => return ("auth.test".into(), json!({})),
    };
    o.insert(
        "text".into(),
        json!(crate::render::cut(&text, SLACK_TEXT_MAX)),
    );
    o.insert("mrkdwn".into(), json!(mrkdwn));
    if !m.buttons.is_empty() {
        let elements: Vec<Json> = m
            .buttons
            .iter()
            .flatten()
            .filter(|b| b.is_url())
            .map(|b| {
                json!({
                    "type": "button",
                    "text": { "type": "plain_text", "text": b.label },
                    "url": b.target,
                })
            })
            .collect();
        if !elements.is_empty() {
            if blocks.is_empty() {
                blocks.push(json!({
                    "type": "section",
                    "text": { "type": if mrkdwn { "mrkdwn" } else { "plain_text" }, "text": crate::render::cut(&text, 3000) },
                }));
            }
            blocks.push(json!({ "type": "actions", "elements": elements }));
        }
    }
    if !blocks.is_empty() {
        o.insert("blocks".into(), Json::Array(blocks));
    }
    if let Some(t) = &m.thread {
        o.insert("thread_ts".into(), json!(t));
    }
    o.insert("unfurl_links".into(), json!(m.preview));
    o.insert("unfurl_media".into(), json!(m.preview));
    ("chat.postMessage".into(), Json::Object(o))
}

pub fn request(kind: Kind, m: &Outgoing) -> (String, Json) {
    match kind {
        Kind::Telegram => telegram(m),
        Kind::Slack => slack(m),
    }
}

/// Why a request did not go through, and what the bot does about it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Fail {
    /// The token is refused: the bot stops until Set Token.
    Auth(String),
    /// Too many requests: hold the whole bot this long, keep the message.
    Retry { after_ms: u64, msg: String },
    /// The platform or the network failed: back off, keep the message.
    Transient(String),
    /// This message is refused (bad chat, blocked by the user, too long): drop it.
    Rejected(String),
    /// The markup did not parse: send it once more without.
    Markup(String),
}

impl Fail {
    pub fn message(&self) -> &str {
        match self {
            Fail::Auth(m) | Fail::Transient(m) | Fail::Rejected(m) | Fail::Markup(m) => m,
            Fail::Retry { msg, .. } => msg,
        }
    }
}

fn parse(body: &[u8]) -> Option<Json> {
    serde_json::from_slice(body).ok()
}

/// A Telegram reply: `{ok: true, result}` or `{ok: false, error_code, description, parameters}`.
pub fn telegram_reply(status: u16, body: &[u8]) -> Result<Json, Fail> {
    let j = parse(body);
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

/// A Slack reply: HTTP 200 with `{ok: true, …}` or `{ok: false, error}`.
pub fn slack_reply(status: u16, body: &[u8]) -> Result<Json, Fail> {
    if status == 429 {
        return Err(Fail::Retry {
            after_ms: 30_000,
            msg: "slack 429: rate limited".into(),
        });
    }
    if status >= 500 || status == 0 {
        return Err(Fail::Transient(format!("slack {status}")));
    }
    let Some(j) = parse(body) else {
        return Err(Fail::Transient(format!("slack {status}: not JSON")));
    };
    if j["ok"] == json!(true) {
        return Ok(j);
    }
    let err = j["error"].as_str().unwrap_or("unknown_error").to_owned();
    let msg = format!("slack: {err}");
    Err(match err.as_str() {
        "invalid_auth" | "not_authed" | "token_revoked" | "token_expired" | "account_inactive"
        | "missing_scope" => Fail::Auth(msg),
        "ratelimited" => Fail::Retry {
            after_ms: 30_000,
            msg,
        },
        "internal_error" | "fatal_error" | "service_unavailable" | "request_timeout" => {
            Fail::Transient(msg)
        }
        _ => Fail::Rejected(msg),
    })
}

pub fn reply(kind: Kind, status: u16, body: &[u8]) -> Result<Json, Fail> {
    match kind {
        Kind::Telegram => telegram_reply(status, body),
        Kind::Slack => slack_reply(status, body),
    }
}

/// `send_raw` methods: what a bot may call with free parameters. Reading updates, webhooks and
/// logging out are never offered: they would take the bot's inbound channel away from the link.
pub fn raw_method_allowed(kind: Kind, method: &str) -> Result<(), String> {
    let plain = !method.is_empty()
        && method.len() <= 64
        && method
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'_');
    if !plain {
        return Err(format!("method {method:?}: a plain method name"));
    }
    let ok = match kind {
        Kind::Telegram => {
            const DENIED: [&str; 6] = [
                "getUpdates",
                "setWebhook",
                "deleteWebhook",
                "logOut",
                "close",
                "setMyCommands",
            ];
            const PREFIXES: [&str; 9] = [
                "send",
                "edit",
                "delete",
                "pin",
                "unpin",
                "forward",
                "copy",
                "stop",
                "setMessageReaction",
            ];
            !DENIED.contains(&method)
                && (PREFIXES.iter().any(|p| method.starts_with(p))
                    || ["getChat", "getMe", "getChatMemberCount"].contains(&method))
        }
        Kind::Slack => {
            ["chat.", "reactions.", "pins."]
                .iter()
                .any(|p| method.starts_with(p))
                || ["conversations.info", "auth.test"].contains(&method)
        }
    };
    if ok {
        Ok(())
    } else {
        Err(format!(
            "method {method}: not offered by send_raw (ADR 0037)"
        ))
    }
}

/// The chat a raw request goes to (`chat_id` / `channel`), as text.
pub fn raw_chat(kind: Kind, params: &Json) -> Option<String> {
    let v = match kind {
        Kind::Telegram => &params["chat_id"],
        Kind::Slack => &params["channel"],
    };
    match v {
        Json::String(s) => Some(s.clone()),
        Json::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

/// One update of `getUpdates` the bot acts on.
#[derive(Debug, Clone, PartialEq)]
pub enum Update {
    Message {
        update_id: i64,
        chat_id: i64,
        chat_type: String,
        from_id: Option<i64>,
        from_is_bot: bool,
        text: String,
    },
    Callback {
        update_id: i64,
        id: String,
        chat_id: Option<i64>,
        chat_type: String,
        from_id: i64,
        data: String,
    },
    /// The bot was added to a chat, or another update kind: only its id matters.
    Other {
        update_id: i64,
        chat: Option<(i64, String)>,
    },
}

impl Update {
    pub fn id(&self) -> i64 {
        match self {
            Update::Message { update_id, .. }
            | Update::Callback { update_id, .. }
            | Update::Other { update_id, .. } => *update_id,
        }
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(body: Body) -> Outgoing {
        Outgoing {
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
    fn slack_requests() {
        let mut o = msg(Body::Text {
            text: "*hi*".into(),
            format: Format::Mrkdwn,
        });
        o.chat = "C0123".into();
        o.thread = Some("1700000000.000100".into());
        let (m, b) = slack(&o);
        assert_eq!(m, "chat.postMessage");
        assert_eq!(b["channel"], "C0123");
        assert_eq!(b["mrkdwn"], true);
        assert_eq!(b["thread_ts"], "1700000000.000100");
        // link buttons become an actions block; command buttons are not for Slack
        assert_eq!(b["blocks"][1]["elements"].as_array().unwrap().len(), 1);
        assert_eq!(b["unfurl_links"], false);
    }

    #[test]
    fn replies_are_sorted() {
        assert_eq!(
            telegram_reply(200, br#"{"ok":true,"result":{"id":1}}"#).unwrap()["id"],
            1
        );
        assert!(matches!(
            telegram_reply(
                401,
                br#"{"ok":false,"error_code":401,"description":"Unauthorized"}"#
            ),
            Err(Fail::Auth(_))
        ));
        assert_eq!(
            telegram_reply(429, br#"{"ok":false,"description":"Too Many Requests","parameters":{"retry_after":12}}"#),
            Err(Fail::Retry { after_ms: 12_000, msg: "telegram 429: Too Many Requests".into() })
        );
        assert!(matches!(
            telegram_reply(
                400,
                br#"{"ok":false,"description":"Bad Request: can't parse entities: x"}"#
            ),
            Err(Fail::Markup(_))
        ));
        assert!(matches!(
            telegram_reply(
                403,
                br#"{"ok":false,"description":"Forbidden: bot was blocked by the user"}"#
            ),
            Err(Fail::Rejected(_))
        ));
        assert!(matches!(
            telegram_reply(502, b"bad gateway"),
            Err(Fail::Transient(_))
        ));
        assert!(slack_reply(200, br#"{"ok":true,"ts":"1.2"}"#).is_ok());
        assert!(matches!(
            slack_reply(200, br#"{"ok":false,"error":"invalid_auth"}"#),
            Err(Fail::Auth(_))
        ));
        assert!(matches!(
            slack_reply(200, br#"{"ok":false,"error":"channel_not_found"}"#),
            Err(Fail::Rejected(_))
        ));
        assert!(matches!(slack_reply(429, b""), Err(Fail::Retry { .. })));
    }

    #[test]
    fn raw_methods_are_bounded() {
        assert!(raw_method_allowed(Kind::Telegram, "sendPoll").is_ok());
        assert!(raw_method_allowed(Kind::Telegram, "editMessageText").is_ok());
        assert!(raw_method_allowed(Kind::Telegram, "getUpdates").is_err());
        assert!(raw_method_allowed(Kind::Telegram, "setWebhook").is_err());
        assert!(raw_method_allowed(Kind::Telegram, "../x").is_err());
        assert!(raw_method_allowed(Kind::Slack, "chat.update").is_ok());
        assert!(raw_method_allowed(Kind::Slack, "users.list").is_err());
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
