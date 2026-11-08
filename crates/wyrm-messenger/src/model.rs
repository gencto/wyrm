//! The definitions the messenger keeps (ADR 0037): bots, recipients, templates and chat users.
//! Each is parsed from an Add or Edit form (a map of action arguments), kept in the store as the
//! canonical form (CBOR of a map) and parsed again on load.

use std::collections::BTreeMap;
use std::net::IpAddr;

use wyrm_core::{Perm, Value};
use wyrm_link_api::net::NetPolicy;

use crate::api::Platform;
use crate::render;

pub type Map = BTreeMap<String, Value>;

pub const MAX_BOTS: usize = 8;
pub const MAX_RECIPIENTS: usize = 64;
pub const MAX_TEMPLATES: usize = 64;
pub const MAX_USERS: usize = 100;
pub const MAX_VALUES: usize = 16;
pub const MAX_SELECT: usize = 16;
pub const MAX_TEMPLATE_TEXT: usize = 4096;
pub const MAX_BLOCKS: usize = 16 << 10;

/// The chat platform of a bot: the link's [`Platform`] (one per link).
pub type Kind = &'static Platform;

/// How a message's text is marked up.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Plain,
    /// Telegram `parse_mode: HTML`.
    Html,
    /// Telegram `parse_mode: MarkdownV2`.
    Markdown,
    /// Slack mrkdwn.
    Mrkdwn,
}

impl Format {
    pub fn name(self) -> &'static str {
        match self {
            Format::Plain => "plain",
            Format::Html => "html",
            Format::Markdown => "markdown",
            Format::Mrkdwn => "mrkdwn",
        }
    }

    pub fn from_name(s: &str) -> Option<Self> {
        [
            Format::Plain,
            Format::Html,
            Format::Markdown,
            Format::Mrkdwn,
        ]
        .into_iter()
        .find(|f| f.name() == s)
    }

    pub fn escape(self) -> render::Escape {
        match self {
            Format::Plain => render::Escape::None,
            Format::Html => render::Escape::Html,
            Format::Markdown => render::Escape::MarkdownV2,
            Format::Mrkdwn => render::Escape::Mrkdwn,
        }
    }
}

/// What a message carries.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MsgKind {
    Text,
    Photo,
    Document,
    Location,
}

impl MsgKind {
    pub const ALL: [MsgKind; 4] = [
        MsgKind::Text,
        MsgKind::Photo,
        MsgKind::Document,
        MsgKind::Location,
    ];

    pub fn name(self) -> &'static str {
        match self {
            MsgKind::Text => "text",
            MsgKind::Photo => "photo",
            MsgKind::Document => "document",
            MsgKind::Location => "location",
        }
    }

    pub fn from_name(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|k| k.name() == s)
    }
}

/// The arguments of a form, read with types and bounds.
pub struct Form<'a>(pub &'a Map);

impl Form<'_> {
    /// Text, `None` when absent, null or empty.
    pub fn text(&self, k: &str) -> Result<Option<String>, String> {
        match self.0.get(k) {
            None | Some(Value::Null) => Ok(None),
            Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
            Some(Value::Str(s)) => Ok(Some(s.clone())),
            Some(Value::Int(i)) => Ok(Some(i.to_string())),
            Some(Value::UInt(u)) => Ok(Some(u.to_string())),
            Some(_) => Err(format!("{k}: text")),
        }
    }

    pub fn required(&self, k: &str) -> Result<String, String> {
        self.text(k)?.ok_or_else(|| format!("{k}: required"))
    }

    pub fn uint(&self, k: &str, default: u64, lo: u64, hi: u64) -> Result<u64, String> {
        let v = match self.0.get(k) {
            None | Some(Value::Null) => return Ok(default),
            Some(Value::UInt(u)) => *u,
            Some(Value::Int(i)) if *i >= 0 => *i as u64,
            Some(Value::Float(f)) if f.fract() == 0.0 && *f >= 0.0 && *f < 1e15 => *f as u64,
            Some(Value::Str(s)) if s.trim().is_empty() => return Ok(default),
            Some(Value::Str(s)) => s
                .trim()
                .parse::<u64>()
                .map_err(|_| format!("{k}: a whole number"))?,
            Some(_) => return Err(format!("{k}: a whole number")),
        };
        if v < lo || v > hi {
            return Err(format!("{k}: {lo}…{hi}"));
        }
        Ok(v)
    }

    pub fn flag(&self, k: &str, default: bool) -> Result<bool, String> {
        match self.0.get(k) {
            None | Some(Value::Null) => Ok(default),
            Some(Value::Bool(b)) => Ok(*b),
            Some(Value::Str(s)) => match s.trim() {
                "" => Ok(default),
                "true" => Ok(true),
                "false" => Ok(false),
                _ => Err(format!("{k}: true or false")),
            },
            Some(_) => Err(format!("{k}: true or false")),
        }
    }

    /// A list given as an array of text or as text with one item per line or comma.
    pub fn list(&self, k: &str) -> Result<Vec<String>, String> {
        let raw: Vec<String> = match self.0.get(k) {
            None | Some(Value::Null) => Vec::new(),
            Some(Value::Str(s)) => s
                .split(['\n', ','])
                .map(|x| x.trim().to_owned())
                .filter(|x| !x.is_empty())
                .collect(),
            Some(Value::Array(a)) => a
                .iter()
                .map(|v| match v {
                    Value::Str(s) => Ok(s.trim().to_owned()),
                    _ => Err(format!("{k}: a list of text")),
                })
                .collect::<Result<_, _>>()?,
            Some(_) => return Err(format!("{k}: a list of text")),
        };
        Ok(raw)
    }

    /// Lines of text (empty ones dropped), for buttons and value bindings.
    pub fn lines(&self, k: &str) -> Result<Vec<String>, String> {
        match self.0.get(k) {
            None | Some(Value::Null) => Ok(Vec::new()),
            Some(Value::Str(s)) => Ok(s
                .lines()
                .map(|l| l.trim().to_owned())
                .filter(|l| !l.is_empty())
                .collect()),
            Some(Value::Array(a)) => a
                .iter()
                .map(|v| match v {
                    Value::Str(s) => Ok(s.trim().to_owned()),
                    _ => Err(format!("{k}: lines of text")),
                })
                .collect(),
            Some(_) => Err(format!("{k}: lines of text")),
        }
    }

    pub fn reject_unknown(&self, known: &[&str]) -> Result<(), String> {
        match self.0.keys().find(|k| !known.contains(&k.as_str())) {
            Some(k) => Err(format!("{k}: unknown")),
            None => Ok(()),
        }
    }
}

/// A node name: one lowercase segment.
pub fn check_name(n: &str, what: &str) -> Result<(), String> {
    let ok = !n.is_empty()
        && n.len() <= 48
        && n.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-')
        && n.as_bytes()[0].is_ascii_alphanumeric();
    if ok {
        Ok(())
    } else {
        Err(format!(
            "{what} {n:?}: 1–48 of a-z, 0-9, _ and -, starting with a letter or a digit"
        ))
    }
}

/// A full node key, `wy/<site>/<section>[/…]`, no wildcards.
pub fn check_key(k: &str) -> Result<(), String> {
    let rest = k
        .strip_prefix("wy/")
        .ok_or_else(|| format!("{k}: a full key, wy/<site>/…"))?;
    let segs: Vec<&str> = rest.split('/').collect();
    if segs.len() < 2 {
        return Err(format!("{k}: at least wy/<site>/<section>"));
    }
    if segs
        .iter()
        .any(|s| s.is_empty() || s.contains(['*', '$', '~', '?', '#']) || *s == "." || *s == "..")
    {
        return Err(format!("{k}: a plain node key"));
    }
    if k.len() > 512 {
        return Err("a key over 512 bytes".into());
    }
    Ok(())
}

/// Where a bot's API is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub tls: bool,
    pub host: String,
    pub port: u16,
    /// Path prefix (no trailing slash).
    pub base: String,
}

pub fn loopback(host: &str) -> bool {
    host == "localhost" || host.parse::<IpAddr>().is_ok_and(|ip| ip.is_loopback())
}

pub fn parse_api(url: &str) -> Result<Endpoint, String> {
    let (tls, host, port, base) =
        wyrm_history_sync::http::parse_url(url).map_err(|e| format!("api_url: {e}"))?;
    if !tls && !loopback(&host) {
        return Err(
            "api_url: https only (http only to loopback, for a local Bot API server)".into(),
        );
    }
    Ok(Endpoint {
        tls,
        host: host.to_ascii_lowercase(),
        port,
        base,
    })
}

/// The endpoint is in the link's `net` allowlist (text, ADR 0012 syntax).
pub fn check_net(net: &str, ep: &Endpoint) -> Result<(), String> {
    let policy = NetPolicy::parse(net).map_err(|e| format!("net: {e}"))?;
    let ok = match ep.host.parse::<IpAddr>() {
        Ok(ip) => policy.allows(ip, ep.port),
        Err(_) if ep.host == "localhost" => {
            policy.allows(IpAddr::V4(std::net::Ipv4Addr::LOCALHOST), ep.port)
        }
        Err(_) => policy.allows_named(
            &ep.host,
            IpAddr::V4(std::net::Ipv4Addr::new(198, 51, 100, 1)),
            ep.port,
        ),
    };
    if ok {
        Ok(())
    } else {
        Err(format!(
            "{}:{} is not in the link's net allowlist: add `{}:{}` to the link's net",
            ep.host, ep.port, ep.host, ep.port
        ))
    }
}

// ---------- bot ----------

#[derive(Debug, Clone, PartialEq)]
pub struct BotDef {
    pub name: String,
    pub kind: Kind,
    pub enabled: bool,
    pub api_url: String,
    pub endpoint: Endpoint,
    pub ca_pem: Option<String>,
    pub timeout_ms: u32,
    pub format: Format,
    /// Telegram: read updates and answer paired users' commands.
    pub commands: bool,
    pub poll_s: u64,
    /// Telegram: leave a group or channel the bot was added to that is no recipient.
    pub leave_unknown: bool,
    /// Commands per minute per chat user.
    pub rate_per_min: u64,
    pub queue_max: u64,
}

pub const BOT_FIELDS: [&str; 10] = [
    "enabled",
    "api_url",
    "ca_pem",
    "timeout_ms",
    "format",
    "commands",
    "poll_s",
    "leave_unknown",
    "rate_per_min",
    "queue_max",
];

impl BotDef {
    pub fn parse(name: &str, kind: Kind, m: &Map, net: Option<&str>) -> Result<Self, String> {
        check_name(name, "name")?;
        let f = Form(m);
        f.reject_unknown(&BOT_FIELDS)?;
        let api_url = f
            .text("api_url")?
            .unwrap_or_else(|| kind.default_api().to_owned());
        let endpoint = parse_api(&api_url)?;
        if let Some(net) = net {
            check_net(net, &endpoint)?;
        }
        let format = match f.text("format")? {
            None => kind.default_format(),
            Some(s) => Format::from_name(&s)
                .filter(|x| kind.formats().contains(x))
                .ok_or_else(|| {
                    let names: Vec<&str> = kind.formats().iter().map(|x| x.name()).collect();
                    format!("format: one of {}", names.join(", "))
                })?,
        };
        let commands = f.flag("commands", kind.inbound)?;
        if commands && !kind.inbound {
            return Err(format!(
                "commands: {} bots only send (ADR 0037)",
                kind.display
            ));
        }
        Ok(Self {
            name: name.to_owned(),
            kind,
            enabled: f.flag("enabled", true)?,
            api_url,
            endpoint,
            ca_pem: f.text("ca_pem")?,
            timeout_ms: f.uint("timeout_ms", 3000, 500, 8000)? as u32,
            format,
            commands,
            poll_s: f.uint("poll_s", 3, 1, 300)?,
            leave_unknown: f.flag("leave_unknown", true)?,
            rate_per_min: f.uint("rate_per_min", 20, 1, 600)?,
            queue_max: f.uint("queue_max", 500, 1, 5000)?,
        })
    }

    pub fn to_value(&self) -> Value {
        let mut m = Map::new();
        m.insert("name".into(), Value::Str(self.name.clone()));
        m.insert("kind".into(), Value::Str(self.kind.name.into()));
        m.insert("enabled".into(), Value::Bool(self.enabled));
        m.insert("api_url".into(), Value::Str(self.api_url.clone()));
        if let Some(c) = &self.ca_pem {
            m.insert("ca_pem".into(), Value::Str(c.clone()));
        }
        m.insert("timeout_ms".into(), Value::UInt(self.timeout_ms.into()));
        m.insert("format".into(), Value::Str(self.format.name().into()));
        m.insert("commands".into(), Value::Bool(self.commands));
        m.insert("poll_s".into(), Value::UInt(self.poll_s));
        m.insert("leave_unknown".into(), Value::Bool(self.leave_unknown));
        m.insert("rate_per_min".into(), Value::UInt(self.rate_per_min));
        m.insert("queue_max".into(), Value::UInt(self.queue_max));
        Value::Map(m)
    }

    /// The editable fields (what an Edit form starts from).
    pub fn fields(&self) -> Map {
        let Value::Map(mut m) = self.to_value() else {
            return Map::new();
        };
        m.remove("name");
        m.remove("kind");
        m
    }

    pub fn from_value(v: &Value, kind: Kind) -> Result<Self, String> {
        let Value::Map(m) = v else {
            return Err("bot: not a map".into());
        };
        let f = Form(m);
        let name = f.required("name")?;
        if f.required("kind")? != kind.name {
            return Err(format!("bot: not a {} bot", kind.display));
        }
        let mut rest = m.clone();
        rest.remove("name");
        rest.remove("kind");
        Self::parse(&name, kind, &rest, None)
    }
}

// ---------- recipient ----------

#[derive(Debug, Clone, PartialEq)]
pub struct Recipient {
    pub name: String,
    /// Telegram: a chat id (`-100…`), `@channel` or `user:<paired user>`; Slack: a channel id.
    pub chat: String,
    /// Telegram forum topic (`message_thread_id`) or Slack `thread_ts`.
    pub thread: Option<String>,
    /// Telegram groups: paired users may give commands here.
    pub commands: bool,
    pub silent: bool,
}

pub const RECIPIENT_FIELDS: [&str; 4] = ["chat", "thread", "commands", "silent"];

impl Recipient {
    pub fn parse(name: &str, kind: Kind, m: &Map) -> Result<Self, String> {
        check_name(name, "name")?;
        let f = Form(m);
        f.reject_unknown(&RECIPIENT_FIELDS)?;
        let chat = f.required("chat")?.trim().to_owned();
        check_chat(kind, &chat)?;
        let thread = f.text("thread")?.map(|t| t.trim().to_owned());
        if let Some(t) = &thread {
            (kind.check_thread)(t)?;
        }
        let commands = f.flag("commands", false)?;
        if commands && !kind.inbound {
            return Err(format!(
                "commands: {} bots only send (ADR 0037)",
                kind.display
            ));
        }
        Ok(Self {
            name: name.to_owned(),
            chat,
            thread,
            commands,
            silent: f.flag("silent", false)?,
        })
    }

    pub fn to_value(&self) -> Value {
        let mut m = Map::new();
        m.insert("name".into(), Value::Str(self.name.clone()));
        m.insert("chat".into(), Value::Str(self.chat.clone()));
        if let Some(t) = &self.thread {
            m.insert("thread".into(), Value::Str(t.clone()));
        }
        m.insert("commands".into(), Value::Bool(self.commands));
        m.insert("silent".into(), Value::Bool(self.silent));
        Value::Map(m)
    }

    pub fn from_value(v: &Value, kind: Kind) -> Result<Self, String> {
        let Value::Map(m) = v else {
            return Err("recipient: not a map".into());
        };
        let name = Form(m).required("name")?;
        let mut rest = m.clone();
        rest.remove("name");
        Self::parse(&name, kind, &rest)
    }

    /// The paired user a `user:<name>` recipient names.
    pub fn user(&self) -> Option<&str> {
        self.chat.strip_prefix("user:")
    }
}

pub fn check_chat(kind: Kind, chat: &str) -> Result<(), String> {
    if let Some(u) = chat.strip_prefix("user:") {
        if !kind.inbound {
            return Err(format!(
                "chat: user:<name> is for paired users; {} bots have none",
                kind.display
            ));
        }
        return check_name(u, "chat user");
    }
    (kind.check_chat)(chat)
}

// ---------- template ----------

/// One inline button: its label and where it goes (`https://…` or a `/command`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Button {
    pub label: String,
    pub target: String,
}

impl Button {
    pub fn is_url(&self) -> bool {
        self.target.starts_with("https://") || self.target.starts_with("http://")
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Template {
    pub name: String,
    pub kind: MsgKind,
    pub format: Format,
    /// The text (the caption of a photo or document).
    pub text: String,
    /// Photo or document: an `https://` URL or a Telegram `file_id`.
    pub media: String,
    pub lat: String,
    pub lon: String,
    /// Rows of buttons.
    pub buttons: Vec<Vec<Button>>,
    /// Slack: Block Kit JSON (an array of blocks), placeholders as JSON string content.
    pub blocks: String,
    /// Recipients when a send names none.
    pub to: Vec<String>,
    pub silent: bool,
    pub protect: bool,
    pub preview: bool,
    /// `alias → full key`: live values the text may name.
    pub values: Vec<(String, String)>,
}

pub const TEMPLATE_FIELDS: [&str; 13] = [
    "kind", "format", "text", "media", "lat", "lon", "buttons", "blocks", "to", "silent",
    "protect", "preview", "values",
];

impl Template {
    pub fn parse(name: &str, kind: Kind, m: &Map) -> Result<Self, String> {
        check_name(name, "name")?;
        let f = Form(m);
        f.reject_unknown(&TEMPLATE_FIELDS)?;
        let msg = match f.text("kind")? {
            None => MsgKind::Text,
            Some(s) => MsgKind::from_name(&s).ok_or("kind: text, photo, document or location")?,
        };
        let format = match f.text("format")? {
            None => kind.default_format(),
            Some(s) => Format::from_name(&s)
                .filter(|x| kind.formats().contains(x))
                .ok_or("format: not for this bot's platform")?,
        };
        let text = f.text("text")?.unwrap_or_default();
        if text.len() > MAX_TEMPLATE_TEXT {
            return Err(format!("text: at most {MAX_TEMPLATE_TEXT} bytes"));
        }
        let media = f.text("media")?.unwrap_or_default();
        let lat = f.text("lat")?.unwrap_or_default();
        let lon = f.text("lon")?.unwrap_or_default();
        let blocks = f.text("blocks")?.unwrap_or_default();
        match msg {
            MsgKind::Text if text.is_empty() && blocks.is_empty() => {
                return Err("text: required".into())
            }
            MsgKind::Photo | MsgKind::Document if media.is_empty() => {
                return Err("media: a URL or a file_id".into())
            }
            MsgKind::Location if lat.is_empty() || lon.is_empty() => {
                return Err("lat, lon: required for a location".into())
            }
            _ => {}
        }
        if !blocks.is_empty() {
            if !kind.blocks {
                return Err(format!("blocks: not for {}", kind.display));
            }
            if blocks.len() > MAX_BLOCKS {
                return Err(format!("blocks: at most {MAX_BLOCKS} bytes"));
            }
            // placeholders render to JSON string content: the template must be JSON already
            let probe = render::render(&blocks, render::Escape::Json, &|_, _| Some(String::new()))
                .map_err(|e| format!("blocks: {e}"))?;
            match serde_json::from_str::<serde_json::Value>(&probe) {
                Ok(serde_json::Value::Array(_)) => {}
                _ => return Err("blocks: a JSON array of Block Kit blocks".into()),
            }
        }
        let mut buttons = Vec::new();
        for line in f.lines("buttons")? {
            let mut row = Vec::new();
            for b in line.split(";;") {
                let (label, target) = b.split_once('|').ok_or_else(|| {
                    format!("buttons: {b:?}: Label | https://… or Label | /command")
                })?;
                let (label, target) = (label.trim(), target.trim());
                let button = Button {
                    label: label.to_owned(),
                    target: target.to_owned(),
                };
                if label.is_empty() || label.len() > 64 {
                    return Err("buttons: a label of 1–64 bytes".into());
                }
                if button.is_url() {
                } else if target.starts_with('/') {
                    if !kind.command_buttons {
                        return Err(format!("buttons: {} buttons are links only", kind.display));
                    }
                    if target.len() > 64 {
                        return Err("buttons: a command of at most 64 bytes".into());
                    }
                } else {
                    return Err(format!("buttons: {target:?}: https://… or /command"));
                }
                row.push(button);
            }
            if row.len() > 8 {
                return Err("buttons: at most 8 per row".into());
            }
            buttons.push(row);
        }
        if buttons.len() > 10 {
            return Err("buttons: at most 10 rows".into());
        }
        let mut values = Vec::new();
        for line in f.lines("values")? {
            let (alias, key) = line
                .split_once('=')
                .ok_or_else(|| format!("values: {line:?}: alias = wy/<site>/…"))?;
            let (alias, key) = (alias.trim(), key.trim());
            render::check_var(alias).map_err(|e| format!("values: {e}"))?;
            if render::BUILTINS.contains(&alias) {
                return Err(format!("values: {alias} is a built-in"));
            }
            check_key(key).map_err(|e| format!("values: {e}"))?;
            if values.iter().any(|(a, _): &(String, String)| a == alias) {
                return Err(format!("values: {alias} twice"));
            }
            values.push((alias.to_owned(), key.to_owned()));
        }
        if values.len() > MAX_VALUES {
            return Err(format!("values: at most {MAX_VALUES}"));
        }
        let to = f.list("to")?;
        for r in &to {
            check_name(r, "to")?;
        }
        let t = Self {
            name: name.to_owned(),
            kind: msg,
            format,
            text,
            media,
            lat,
            lon,
            buttons,
            blocks,
            to,
            silent: f.flag("silent", false)?,
            protect: f.flag("protect", false)?,
            preview: f.flag("preview", false)?,
            values,
        };
        // every placeholder parses
        t.vars()?;
        Ok(t)
    }

    /// Every text a placeholder may be in.
    pub fn parts(&self) -> Vec<&str> {
        let mut out = vec![
            self.text.as_str(),
            self.media.as_str(),
            self.lat.as_str(),
            self.lon.as_str(),
            self.blocks.as_str(),
        ];
        for row in &self.buttons {
            for b in row {
                out.push(&b.label);
                out.push(&b.target);
            }
        }
        out
    }

    /// The variables a send passes: the placeholders that are neither values nor built-ins.
    pub fn vars(&self) -> Result<Vec<String>, String> {
        let mut out: Vec<String> = Vec::new();
        for p in self.parts() {
            for (name, _) in render::placeholders(p)? {
                if render::BUILTINS.contains(&name.as_str())
                    || self.values.iter().any(|(a, _)| *a == name)
                    || out.contains(&name)
                {
                    continue;
                }
                out.push(name);
            }
        }
        Ok(out)
    }

    pub fn to_value(&self) -> Value {
        let mut m = Map::new();
        let s = |v: &str| Value::Str(v.to_owned());
        m.insert("name".into(), s(&self.name));
        m.insert("kind".into(), s(self.kind.name()));
        m.insert("format".into(), s(self.format.name()));
        for (k, v) in [
            ("text", &self.text),
            ("media", &self.media),
            ("lat", &self.lat),
            ("lon", &self.lon),
            ("blocks", &self.blocks),
        ] {
            if !v.is_empty() {
                m.insert(k.into(), s(v));
            }
        }
        if !self.buttons.is_empty() {
            let lines: Vec<String> = self
                .buttons
                .iter()
                .map(|row| {
                    row.iter()
                        .map(|b| format!("{} | {}", b.label, b.target))
                        .collect::<Vec<_>>()
                        .join(" ;; ")
                })
                .collect();
            m.insert("buttons".into(), s(&lines.join("\n")));
        }
        if !self.to.is_empty() {
            m.insert("to".into(), s(&self.to.join(", ")));
        }
        if !self.values.is_empty() {
            let lines: Vec<String> = self
                .values
                .iter()
                .map(|(a, k)| format!("{a} = {k}"))
                .collect();
            m.insert("values".into(), s(&lines.join("\n")));
        }
        m.insert("silent".into(), Value::Bool(self.silent));
        m.insert("protect".into(), Value::Bool(self.protect));
        m.insert("preview".into(), Value::Bool(self.preview));
        Value::Map(m)
    }

    pub fn from_value(v: &Value, kind: Kind) -> Result<Self, String> {
        let Value::Map(m) = v else {
            return Err("template: not a map".into());
        };
        let name = Form(m).required("name")?;
        let mut rest = m.clone();
        rest.remove("name");
        Self::parse(&name, kind, &rest)
    }
}

// ---------- chat user ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UserStatus {
    /// Invited: waits for `/start <code>` from its account.
    Pending,
    Active,
    Disabled,
}

impl UserStatus {
    pub fn name(self) -> &'static str {
        match self {
            UserStatus::Pending => "pending",
            UserStatus::Active => "active",
            UserStatus::Disabled => "disabled",
        }
    }

    pub fn from_name(s: &str) -> Option<Self> {
        [
            UserStatus::Pending,
            UserStatus::Active,
            UserStatus::Disabled,
        ]
        .into_iter()
        .find(|x| x.name() == s)
    }
}

/// A chat account allowed to talk to a bot.
#[derive(Debug, Clone, PartialEq)]
pub struct User {
    pub name: String,
    /// `read` (/get) or `write` (/get, /set, /do).
    pub level: Perm,
    /// Key prefixes the user's commands may name.
    pub select: Vec<String>,
    pub status: UserStatus,
    /// The Telegram user id it is paired with (never a username: those change hands).
    pub chat_id: Option<i64>,
    /// SHA-256 (hex) of the pending pairing code.
    pub code_hash: Option<String>,
    pub code_expires_us: u64,
    pub paired_us: u64,
}

pub const USER_FIELDS: [&str; 2] = ["level", "select"];

impl User {
    /// The level and selection of an Invite or Edit form.
    pub fn parse_rights(m: &Map, site: Option<&str>) -> Result<(Perm, Vec<String>), String> {
        let f = Form(m);
        f.reject_unknown(&USER_FIELDS)?;
        let level = match f.text("level")?.as_deref() {
            None | Some("read") => Perm::Read,
            Some("write") => Perm::Write,
            Some(_) => return Err("level: read or write".into()),
        };
        let mut select = f.list("select")?;
        if select.is_empty() {
            let site = site.ok_or("select: required (full keys)")?;
            select = vec![format!("wy/{site}/downstream")];
        }
        for k in &select {
            check_key(k).map_err(|e| format!("select: {e}"))?;
        }
        if select.len() > MAX_SELECT {
            return Err(format!("select: at most {MAX_SELECT} keys"));
        }
        Ok((level, select))
    }

    pub fn to_value(&self) -> Value {
        let mut m = Map::new();
        m.insert("name".into(), Value::Str(self.name.clone()));
        m.insert("level".into(), Value::Str(self.level.name().into()));
        m.insert(
            "select".into(),
            Value::Array(self.select.iter().cloned().map(Value::Str).collect()),
        );
        m.insert("status".into(), Value::Str(self.status.name().into()));
        if let Some(id) = self.chat_id {
            m.insert("chat_id".into(), Value::Int(id));
        }
        if let Some(h) = &self.code_hash {
            m.insert("code_hash".into(), Value::Str(h.clone()));
        }
        m.insert("code_expires_us".into(), Value::UInt(self.code_expires_us));
        m.insert("paired_us".into(), Value::UInt(self.paired_us));
        Value::Map(m)
    }

    pub fn from_value(v: &Value) -> Result<Self, String> {
        let Value::Map(m) = v else {
            return Err("user: not a map".into());
        };
        let f = Form(m);
        let name = f.required("name")?;
        check_name(&name, "name")?;
        let level = match f.required("level")?.as_str() {
            "read" => Perm::Read,
            "write" => Perm::Write,
            _ => return Err("user: bad level".into()),
        };
        let select = f.list("select")?;
        let status = UserStatus::from_name(&f.required("status")?).ok_or("user: bad status")?;
        let chat_id = match m.get("chat_id") {
            Some(Value::Int(i)) => Some(*i),
            Some(Value::UInt(u)) => i64::try_from(*u).ok(),
            _ => None,
        };
        Ok(Self {
            name,
            level,
            select,
            status,
            chat_id,
            code_hash: f.text("code_hash")?,
            code_expires_us: f.uint("code_expires_us", 0, 0, u64::MAX)?,
            paired_us: f.uint("paired_us", 0, 0, u64::MAX)?,
        })
    }

    /// The user's own selection lets it name `key` at `need`.
    pub fn may(&self, key: &str, need: Perm) -> bool {
        self.status == UserStatus::Active
            && self.level >= need
            && self
                .select
                .iter()
                .any(|p| key == p || key.starts_with(&format!("{p}/")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_platforms::{CHATTY, QUIET};

    fn m(pairs: &[(&str, &str)]) -> Map {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), Value::Str((*v).to_owned())))
            .collect()
    }

    #[test]
    fn bot_defaults_and_bounds() {
        let b = BotDef::parse("ops", &CHATTY, &Map::new(), Some("api.chatty.example:443")).unwrap();
        assert_eq!(b.endpoint.host, "api.chatty.example");
        assert_eq!(b.format, Format::Html);
        assert!(b.commands);
        let e = BotDef::parse("ops", &CHATTY, &Map::new(), Some("quiet.example:443"));
        assert!(e.unwrap_err().contains("not in the link's net"));
        let e = BotDef::parse("ops", &QUIET, &m(&[("format", "html")]), None);
        assert!(e.is_err());
        let e = BotDef::parse(
            "ops",
            &CHATTY,
            &m(&[("api_url", "http://example.com")]),
            None,
        );
        assert!(e.unwrap_err().contains("https only"));
        assert!(BotDef::parse("Ops", &CHATTY, &Map::new(), None).is_err());
        let b2 = BotDef::from_value(&b.to_value(), &CHATTY).unwrap();
        assert_eq!(b, b2);
    }

    #[test]
    fn recipients_by_platform() {
        assert!(Recipient::parse("g", &CHATTY, &m(&[("chat", "-1001234567890")])).is_ok());
        assert!(Recipient::parse("g", &CHATTY, &m(&[("chat", "@plant_alerts")])).is_ok());
        assert!(Recipient::parse("g", &CHATTY, &m(&[("chat", "user:ann")])).is_ok());
        assert!(Recipient::parse("g", &CHATTY, &m(&[("chat", "ann")])).is_err());
        assert!(Recipient::parse("g", &QUIET, &m(&[("chat", "C0123ABC")])).is_ok());
        assert!(Recipient::parse("g", &QUIET, &m(&[("chat", "user:ann")])).is_err());
        assert!(Recipient::parse(
            "g",
            &QUIET,
            &m(&[("chat", "C0123ABC"), ("thread", "1700000000.000100")])
        )
        .is_ok());
        assert!(
            Recipient::parse("g", &CHATTY, &m(&[("chat", "-100123"), ("thread", "x")])).is_err()
        );
    }

    #[test]
    fn templates_validate_their_parts() {
        let t = Template::parse(
            "high",
            &CHATTY,
            &m(&[
                ("text", "<b>{{name}}</b>: {{temp:.1}} °C at {{now}}"),
                ("values", "temp = wy/s/downstream/plc/t1"),
                (
                    "buttons",
                    "Open | https://x.example/{{name}} ;; Ack | /do wy/s/downstream/alarm/a ack",
                ),
                ("to", "ops, night"),
            ]),
        )
        .unwrap();
        assert_eq!(t.vars().unwrap(), vec!["name".to_owned()]);
        assert_eq!(t.buttons[0].len(), 2);
        assert_eq!(t.to, vec!["ops", "night"]);
        assert_eq!(Template::from_value(&t.to_value(), &CHATTY).unwrap(), t);
        assert!(Template::parse("x", &CHATTY, &m(&[("kind", "photo")])).is_err());
        assert!(Template::parse("x", &CHATTY, &m(&[("text", "{{oops")])).is_err());
        assert!(Template::parse(
            "x",
            &QUIET,
            &m(&[("text", "a"), ("buttons", "Ack | /do x")])
        )
        .is_err());
        assert!(Template::parse(
            "x",
            &QUIET,
            &m(&[(
                "blocks",
                r#"[{"type":"section","text":{"type":"mrkdwn","text":"{{a}}"}}]"#
            )])
        )
        .is_ok());
        assert!(Template::parse("x", &QUIET, &m(&[("blocks", "{nope")])).is_err());
        assert!(Template::parse(
            "x",
            &CHATTY,
            &m(&[("text", "a"), ("values", "now = wy/s/x")])
        )
        .is_err());
    }

    #[test]
    fn user_rights_need_active_status_level_and_selection() {
        let (level, select) = User::parse_rights(
            &m(&[("level", "write"), ("select", "wy/s/downstream/plc")]),
            Some("s"),
        )
        .unwrap();
        let mut u = User {
            name: "ann".into(),
            level,
            select,
            status: UserStatus::Pending,
            chat_id: None,
            code_hash: None,
            code_expires_us: 0,
            paired_us: 0,
        };
        assert!(!u.may("wy/s/downstream/plc/t1", Perm::Read));
        u.status = UserStatus::Active;
        assert!(u.may("wy/s/downstream/plc/t1", Perm::Write));
        assert!(!u.may("wy/s/downstream/plc2/t1", Perm::Read));
        u.level = Perm::Read;
        assert!(!u.may("wy/s/downstream/plc/t1", Perm::Write));
        assert_eq!(User::from_value(&u.to_value()).unwrap(), u);
        let (_, d) = User::parse_rights(&Map::new(), Some("s")).unwrap();
        assert_eq!(d, vec!["wy/s/downstream"]);
    }
}
