//! What the core knows of a chat platform: a message rendered for any of them ([`Outgoing`]),
//! what a failed call means for the bot ([`Fail`]), an inbound update ([`Update`]), and the
//! [`Platform`] a link fills in with its own API — paths, request bodies, reply classes, what it
//! can do. Telegram (`links/telegram`) and Slack (`links/slack`) are two such links; another
//! messenger is a crate with one more `Platform`. Pure: no I/O, no clock.

use serde_json::Value as Json;
use wyrm_core::Value;

use crate::model::{Button, Format};

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

/// One chat platform, as a link describes it (ADR 0037). Constant data and plain functions: the
/// core calls them, the link owns the API.
pub struct Platform {
    /// The link's name (`App::NAME`): `telegram`, `slack`.
    pub name: &'static str,
    pub display: &'static str,
    pub default_api: &'static str,
    /// The markups it takes; the first is the default.
    pub formats: &'static [Format],
    /// Set Token's help, and the error for a token of the wrong shape.
    pub token_about: &'static str,
    pub token_hint: &'static str,
    pub chat_about: &'static str,
    pub thread_about: &'static str,
    pub raw_about: &'static str,
    /// The call that proves the token and names the bot (`getMe`, `auth.test`).
    pub identify: &'static str,
    /// It reads updates: chat users pair with a code and give commands; `user:<name>` recipients.
    pub inbound: bool,
    /// Buttons may carry a `/command` (they come back as updates).
    pub command_buttons: bool,
    /// Templates may carry `blocks` (Slack Block Kit).
    pub blocks: bool,
    /// Gap between two messages to one chat (µs).
    pub per_chat_us: u64,
    /// The token sent as `Authorization: Bearer` (else it is in the path).
    pub bearer: bool,
    pub check_token: fn(&str) -> bool,
    pub check_chat: fn(&str) -> Result<(), String>,
    pub check_thread: fn(&str) -> Result<(), String>,
    /// The request path of `method` under the API's base path.
    pub path: fn(base: &str, token: &str, method: &str) -> String,
    /// `(method, body)` of a message.
    pub request: fn(&Outgoing) -> (String, Json),
    pub reply: fn(u16, &[u8]) -> Result<Json, Fail>,
    /// The bot's name from the identify call's result.
    pub identity: fn(&Json) -> String,
    /// A `send_raw` method it offers.
    pub raw_method: fn(&str) -> bool,
    /// The chat a raw request names.
    pub raw_chat: fn(&Json) -> Option<String>,
    /// `(method, body)` that reads updates after `offset`; `None` without inbound.
    pub poll: fn(offset: i64, limit: u64) -> Option<(String, Json)>,
    pub updates: fn(&Json) -> Vec<Update>,
}

impl Platform {
    pub fn name(&self) -> &'static str {
        self.name
    }

    pub fn display(&self) -> &'static str {
        self.display
    }

    pub fn default_api(&self) -> &'static str {
        self.default_api
    }

    pub fn formats(&self) -> &'static [Format] {
        self.formats
    }

    pub fn default_format(&self) -> Format {
        self.formats.first().copied().unwrap_or(Format::Plain)
    }

    pub fn secret_about(&self) -> &'static str {
        self.token_about
    }

    /// `send_raw`'s check: a plain name the platform offers.
    pub fn raw_method_allowed(&self, method: &str) -> Result<(), String> {
        let plain = !method.is_empty()
            && method.len() <= 64
            && method
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'_');
        if !plain {
            return Err(format!("method {method:?}: a plain method name"));
        }
        if (self.raw_method)(method) {
            Ok(())
        } else {
            Err(format!(
                "method {method}: not offered by send_raw (ADR 0037)"
            ))
        }
    }
}

impl core::fmt::Debug for Platform {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "Platform({})", self.name)
    }
}

impl PartialEq for Platform {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

/// A platform as a type, for `Messenger<C>`: what a link crate implements.
pub trait Chat: 'static {
    /// The link crate's version (`App::VERSION`).
    const VERSION: &'static str;
    const PLATFORM: &'static Platform;
}

/// The platform's `text` of a JSON string or number field.
pub fn text_of(v: &Json) -> Option<String> {
    match v {
        Json::String(s) => Some(s.clone()),
        Json::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

/// The reply body as JSON.
pub fn parse_json(body: &[u8]) -> Option<Json> {
    serde_json::from_slice(body).ok()
}
