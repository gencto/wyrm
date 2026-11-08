//! `slack`: Slack bots (ADR 0037) as a portable link (ADR 0023), on the messenger core
//! (`wyrm-messenger`). This crate is the Slack Web API and what Slack can do; bots, recipients,
//! templates and the queue are the core's.
//!
//! - Requests: `POST <api>/api/<method>` with `Authorization: Bearer xoxb-…` and JSON;
//!   `chat.postMessage` with mrkdwn (default) or plain text, Block Kit `blocks` from a template,
//!   images as image blocks, link buttons as an actions block, `thread_ts`, unfurls off unless
//!   `preview`.
//! - Send only for now: receiving needs Socket Mode or the Events API (ADR 0037), so a Slack bot
//!   has no chat users, no `/command` buttons and no `user:<name>` recipients.
//! - `send_raw`: `chat.*`, `reactions.*`, `pins.*`, `conversations.info`, `auth.test`.
//!
//! Embedded as `Portable<SlackLink>`, as a process (`--features process`) or as a WASM
//! component (`--features wasm`).

use serde_json::{json, Value as Json};
use wyrm_messenger::api::{parse_json, text_of, Body, Chat, Fail, Outgoing, Platform, Update};
use wyrm_messenger::model::Format;
use wyrm_messenger::{render, Messenger};

/// Slack's limit on `text`.
pub const SLACK_TEXT_MAX: usize = 40_000;

/// The link's app.
pub type SlackLink = Messenger<Slack>;

pub struct Slack;

impl Chat for Slack {
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    const PLATFORM: &'static Platform = &SLACK;
}

pub const SLACK: Platform = Platform {
    name: "slack",
    display: "Slack",
    default_api: "https://slack.com",
    formats: &[Format::Mrkdwn, Format::Plain],
    token_about: "The bot user OAuth token (xoxb-…), scope chat:write.",
    token_hint: "token: a bot token, xoxb-…",
    chat_about: "A channel id (C0123456789); invite the bot to the channel.",
    thread_about: "A thread_ts to reply in.",
    raw_about: "A Web API method: chat.update, reactions.add, pins.add, …",
    identify: "auth.test",
    inbound: false,
    command_buttons: false,
    blocks: true,
    // Slack paces per workspace (429 holds the bot), not per channel
    per_chat_us: 0,
    bearer: true,
    check_token: |t| t.starts_with("xox"),
    check_chat,
    check_thread,
    path: |base, _token, method| format!("{base}/api/{method}"),
    request: slack,
    reply: slack_reply,
    identity: |me| {
        format!(
            "{} ({})",
            me["user"].as_str().unwrap_or(""),
            me["team"].as_str().unwrap_or("")
        )
    },
    raw_method,
    raw_chat: |p| text_of(&p["channel"]),
    poll: |_, _| None,
    updates: |_| Vec::<Update>::new(),
};

fn check_chat(chat: &str) -> Result<(), String> {
    if (2..=32).contains(&chat.len())
        && chat
            .bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit())
    {
        Ok(())
    } else {
        Err(format!("chat {chat:?}: a channel id (C0123456789)"))
    }
}

fn check_thread(t: &str) -> Result<(), String> {
    let ok = t.split_once('.').is_some_and(|(a, b)| {
        !a.is_empty() && !b.is_empty() && a.bytes().chain(b.bytes()).all(|c| c.is_ascii_digit())
    });
    if ok {
        Ok(())
    } else {
        Err("thread: a thread_ts (1700000000.000100)".into())
    }
}

fn raw_method(method: &str) -> bool {
    ["chat.", "reactions.", "pins."]
        .iter()
        .any(|p| method.starts_with(p))
        || ["conversations.info", "auth.test"].contains(&method)
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
    o.insert("text".into(), json!(render::cut(&text, SLACK_TEXT_MAX)));
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
                    "text": { "type": if mrkdwn { "mrkdwn" } else { "plain_text" }, "text": render::cut(&text, 3000) },
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
    let Some(j) = parse_json(body) else {
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

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(SlackLink);

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_messenger::model::Button;

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
        assert!(slack_reply(200, br#"{"ok":true,"ts":"1.2"}"#).is_ok());
        assert!(matches!(
            slack_reply(200, br#"{"ok":false,"error":"invalid_auth"}"#),
            Err(Fail::Auth(_))
        ));
        assert!(matches!(
            slack_reply(200, br#"{"ok":false,"error":"channel_not_found"}"#),
            Err(Fail::Rejected(_))
        ));
        assert!(matches!(
            slack_reply(200, br#"{"ok":false,"error":"ratelimited"}"#),
            Err(Fail::Retry { .. })
        ));
        assert!(matches!(slack_reply(429, b""), Err(Fail::Retry { .. })));
        assert!(matches!(slack_reply(503, b""), Err(Fail::Transient(_))));
    }
    #[test]
    fn raw_methods_are_bounded() {
        assert!(SLACK.raw_method_allowed("chat.update").is_ok());
        assert!(SLACK.raw_method_allowed("users.list").is_err());
    }
}
