//! Two small platforms for the core's own unit tests: `CHATTY` reads updates and takes command
//! buttons (as Telegram does), `QUIET` only sends and takes blocks (as Slack does).

use serde_json::{json, Value as Json};

use crate::api::{Fail, Outgoing, Platform, Update};
use crate::model::Format;

fn numeric_or_at(c: &str) -> Result<(), String> {
    let d = c.strip_prefix('-').unwrap_or(c);
    if (!d.is_empty() && d.bytes().all(|b| b.is_ascii_digit())) || c.starts_with('@') {
        Ok(())
    } else {
        Err(format!("chat {c:?}: a number or @name"))
    }
}

fn upper(c: &str) -> Result<(), String> {
    if !c.is_empty()
        && c.bytes()
            .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit())
    {
        Ok(())
    } else {
        Err(format!("chat {c:?}: a channel id"))
    }
}

fn number(t: &str) -> Result<(), String> {
    t.parse::<u64>()
        .map(|_| ())
        .map_err(|_| "thread: a number".into())
}

fn request(_m: &Outgoing) -> (String, Json) {
    ("send".into(), json!({}))
}

fn reply(_s: u16, _b: &[u8]) -> Result<Json, Fail> {
    Ok(json!({}))
}

pub const CHATTY: Platform = Platform {
    name: "chatty",
    display: "Chatty",
    default_api: "https://api.chatty.example",
    formats: &[Format::Html, Format::Markdown, Format::Plain],
    token_about: "",
    token_hint: "token",
    chat_about: "",
    thread_about: "",
    raw_about: "",
    identify: "me",
    inbound: true,
    command_buttons: true,
    blocks: false,
    per_chat_us: 0,
    bearer: false,
    check_token: |_| true,
    check_chat: numeric_or_at,
    check_thread: number,
    path: |b, _, m| format!("{b}/{m}"),
    request,
    reply,
    identity: |_| String::new(),
    raw_method: |_| true,
    raw_chat: |_| None,
    poll: |_, _| None,
    updates: |_| Vec::<Update>::new(),
};

pub const QUIET: Platform = Platform {
    name: "quiet",
    display: "Quiet",
    default_api: "https://quiet.example",
    formats: &[Format::Mrkdwn, Format::Plain],
    inbound: false,
    command_buttons: false,
    blocks: true,
    check_chat: upper,
    check_thread: |_| Ok(()),
    ..CHATTY
};
