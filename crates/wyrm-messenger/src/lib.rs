//! `wyrm-messenger`: the core of the messenger links (ADR 0039) — Telegram (`links/telegram`),
//! Slack (`links/slack`) and whatever chat platform comes next. A link crate describes its
//! platform once ([`api::Platform`]: API paths, request bodies, reply classes, what it can do)
//! and runs `Messenger<its platform>` as a portable link (ADR 0023): embedded, as a process or as
//! a WASM component. Everything the platforms share lives here:
//!
//! - **bots**: `add_bot`, its token by ▸ Set Token (the link's sealed store; never a param, never
//!   shown), `status`, counters, a queue with the platform's pacing, back-off and hold on 429.
//! - **recipients** (`<bot>/recipients/<r>`): the only chats a bot writes to.
//! - **templates** (`<bot>/templates/<t>`): kind (text, photo, document, location), format (what
//!   the platform takes: HTML, MarkdownV2, mrkdwn, plain, blocks), text with `{{placeholders}}`
//!   filled from the send, from live values the template binds and from built-ins, escaped for
//!   the markup ([`render`]); buttons; each template gets a Send action whose parameters are its
//!   own variables.
//! - **ad hoc** `send` and `send_raw {method, params}` (config) for whatever else the platform
//!   offers, only to recipient chats.
//! - **chat users** (`<bot>/users/<u>`) on platforms that read updates: invited by an operator,
//!   paired with a one-time code (`/start <code>`), then `/get`, `/set`, `/do` within their own
//!   level and keys, the rights of who invited them and the link's grants ([`auth`]).
//!
//! Params: `site` (the host's site: relative keys in chat commands, `{{site}}`), `own` (the
//! link's own key: never written from a chat), `net` (the link's allowlist as text, so an Add
//! can refuse an API host it does not cover).

pub mod api;
pub mod auth;
pub mod model;
pub mod render;
mod store;
#[cfg(test)]
mod test_platforms;
#[cfg(feature = "testkit")]
pub mod testkit;
pub mod tree;

use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use std::marker::PhantomData;

use serde_json::{json, Value as Json};
use wyrm_core::{Perm, Quality, Sample, Status, Value};
use wyrm_history_sync::http::Client as HttpClient;
use wyrm_history_sync::sigv4;
use wyrm_link_api::{App, AppError, Host, Level, ReqId, Rights, SubId, TimerId, Who};

use api::{Body, Fail, Outgoing, Update};
pub use api::{Chat, Platform};
use model::{BotDef, Form, Kind, Map, MsgKind, Recipient, Template, User, UserStatus};

/// Messages sent in one event of a bot.
const SENDS_PER_TICK: usize = 4;
/// The queue is looked at again this soon while it holds messages.
const FLUSH_MS: u64 = 200;
const FIRST_BACKOFF_MS: u64 = 1_000;
const MAX_BACKOFF_MS: u64 = 60_000;
/// The start of `error` while reading updates fails and sending does not.
const UPDATES_FAILED: &str = "updates: ";
/// A message that failed this often on the network is dropped.
const MAX_ATTEMPTS: u32 = 5;
/// `/get` waits this long for the value.
const READ_WAIT_MS: u64 = 5_000;
const UPDATES_PER_POLL: u64 = 50;

fn invalid(msg: impl Into<String>) -> AppError {
    AppError::new(Status::InvalidParameter, msg)
}

fn denied(msg: impl Into<String>) -> AppError {
    AppError::new(Status::PermissionDenied, msg)
}

fn args_of(args: Value) -> Result<Map, AppError> {
    match args {
        Value::Map(m) => Ok(m),
        Value::Null => Ok(Map::new()),
        _ => Err(invalid("args: a map")),
    }
}

/// `YYYY-MM-DDTHH:MM:SSZ` of UTC microseconds.
pub fn rfc3339(us: u64) -> String {
    let d = sigv4::amz_date(us);
    format!(
        "{}-{}-{}T{}:{}:{}Z",
        &d[0..4],
        &d[4..6],
        &d[6..8],
        &d[9..11],
        &d[11..13],
        &d[13..15]
    )
}

/// The caller's rights (ADR 0029): whatever a definition does later, it does within them.
fn caller_rights(who: &Who, what: &str) -> Result<Rights, AppError> {
    Rights::of(who).ok_or_else(|| {
        denied(format!(
            "the caller's rights are unknown (its token carries no auth): {what} keeps its author's rights"
        ))
    })
}

/// A token as the platforms issue them: printable, no spaces, in the platform's shape.
fn check_token(kind: Kind, t: &str) -> Result<(), AppError> {
    let printable = !t.is_empty()
        && t.len() <= 256
        && t.bytes()
            .all(|b| b.is_ascii_graphic() && b != b'/' && b != b'?' && b != b'#');
    if printable && (kind.check_token)(t) {
        Ok(())
    } else {
        Err(invalid(kind.token_hint))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum State {
    NoToken,
    Checking,
    Ready,
    Waiting,
    Failed,
    Disabled,
}

impl State {
    fn name(self) -> &'static str {
        match self {
            State::NoToken => "no_token",
            State::Checking => "checking",
            State::Ready => "ready",
            State::Waiting => "waiting",
            State::Failed => "failed",
            State::Disabled => "disabled",
        }
    }
}

/// A command from a paired user, to run with the link's host.
struct Inbound {
    user: String,
    chat: String,
    cmd: auth::Command,
}

/// A `/get`, `/set` or `/do` waiting for the tree.
struct Pending {
    bot: String,
    chat: String,
    what: String,
    timer: Option<TimerId>,
}

struct Bot {
    def: BotDef,
    recipients: BTreeMap<String, Recipient>,
    templates: BTreeMap<String, (Template, Option<Rights>)>,
    users: BTreeMap<String, (User, Option<Rights>)>,
    state: State,
    error: String,
    username: String,
    http: Option<HttpClient>,
    queue: VecDeque<Outgoing>,
    sent: u64,
    failed: u64,
    dropped: u64,
    rejected: u64,
    last_sent: u64,
    hold_until: u64,
    backoff_ms: u64,
    next_poll: u64,
    /// Back-off of reading updates alone (ms): a failed `getUpdates` holds the reading, not
    /// the sending (DVPSM demo, 2026-11-13: a bot that sent fine showed `waiting`).
    poll_backoff_ms: u64,
    timer: Option<TimerId>,
    last_chat: HashMap<String, u64>,
    /// Wrong pairing codes per account: `(count, first)`.
    bad_codes: HashMap<i64, (u32, u64)>,
    /// When an unknown account last heard "not authorized".
    nagged: HashMap<i64, u64>,
    buckets: HashMap<String, auth::Bucket>,
    seen: HashMap<String, (u64, u64)>,
    shown: HashMap<String, Value>,
    /// The platform's id of the last message each recipient got (`last_message_id`).
    last_ids: BTreeMap<String, String>,
}

impl Bot {
    fn new(def: BotDef, has_token: bool) -> Self {
        let state = if !def.enabled {
            State::Disabled
        } else if has_token {
            State::Checking
        } else {
            State::NoToken
        };
        Self {
            def,
            recipients: BTreeMap::new(),
            templates: BTreeMap::new(),
            users: BTreeMap::new(),
            state,
            error: String::new(),
            username: String::new(),
            http: None,
            queue: VecDeque::new(),
            sent: 0,
            failed: 0,
            dropped: 0,
            rejected: 0,
            last_sent: 0,
            hold_until: 0,
            backoff_ms: 0,
            next_poll: 0,
            poll_backoff_ms: 0,
            timer: None,
            last_chat: HashMap::new(),
            bad_codes: HashMap::new(),
            nagged: HashMap::new(),
            buckets: HashMap::new(),
            seen: HashMap::new(),
            shown: HashMap::new(),
            last_ids: BTreeMap::new(),
        }
    }

    fn name(&self) -> &str {
        &self.def.name
    }

    fn put(&mut self, host: &mut dyn Host, path: String, v: Value, now: u64) {
        if self.shown.get(&path) != Some(&v) {
            self.shown.insert(path.clone(), v.clone());
            host.update(
                &path,
                Sample {
                    v,
                    q: Quality::Good,
                    t: now,
                },
            );
        }
    }

    fn show(&mut self, host: &mut dyn Host, now: u64) {
        let n = self.name().to_owned();
        let time = |t: u64| Value::Str(if t == 0 { String::new() } else { rfc3339(t) });
        let leaves = [
            ("status", Value::Str(self.state.name().into())),
            ("error", Value::Str(self.error.clone())),
            ("username", Value::Str(self.username.clone())),
            ("sent", Value::UInt(self.sent)),
            ("failed", Value::UInt(self.failed)),
            ("dropped", Value::UInt(self.dropped)),
            ("queued", Value::UInt(self.queue.len() as u64)),
            ("rejected", Value::UInt(self.rejected)),
            ("last_sent", time(self.last_sent)),
            ("enabled", Value::Bool(self.def.enabled)),
        ];
        for (l, v) in leaves {
            self.put(host, tree::leaf(&n, l), v, now);
        }
        let ids: Vec<(String, String)> = self
            .last_ids
            .iter()
            .filter(|(r, _)| self.recipients.contains_key(*r))
            .map(|(r, i)| (r.clone(), i.clone()))
            .collect();
        for (r, id) in ids {
            let p = tree::leaf(&tree::recipient_path(&n, &r), "last_message_id");
            self.put(host, p, Value::Str(id), now);
        }
    }

    fn show_user(&mut self, host: &mut dyn Host, uname: &str, now: u64) {
        let Some((u, _)) = self.users.get(uname) else {
            return;
        };
        let p = tree::user_path(self.name(), uname);
        let (last, count) = self.seen.get(uname).copied().unwrap_or((0, 0));
        let leaves = [
            ("status", Value::Str(u.status.name().into())),
            ("level", Value::Str(u.level.name().into())),
            ("select", Value::Str(u.select.join(", "))),
            (
                "chat_id",
                Value::Str(u.chat_id.map(|i| i.to_string()).unwrap_or_default()),
            ),
            (
                "paired",
                Value::Str(if u.paired_us == 0 {
                    String::new()
                } else {
                    rfc3339(u.paired_us)
                }),
            ),
            (
                "last_seen",
                Value::Str(if last == 0 {
                    String::new()
                } else {
                    rfc3339(last)
                }),
            ),
            ("commands", Value::UInt(count)),
        ];
        for (l, v) in leaves {
            self.put(host, tree::leaf(&p, l), v, now);
        }
    }

    fn close(&mut self, host: &mut dyn Host) {
        if let Some(mut h) = self.http.take() {
            h.close(host);
        }
    }

    /// Start over after an edit, a token or an enable.
    fn restart(&mut self, host: &mut dyn Host) {
        self.close(host);
        self.username.clear();
        self.error.clear();
        self.hold_until = 0;
        self.backoff_ms = 0;
        self.next_poll = 0;
        self.state = if !self.def.enabled {
            State::Disabled
        } else if store::secret(host, self.name()).is_some() {
            State::Checking
        } else {
            State::NoToken
        };
    }

    /// One API call, the token from the store.
    fn call(&mut self, host: &mut dyn Host, method: &str, body: &Json) -> Result<Json, Fail> {
        let token = store::secret(host, self.name())
            .ok_or_else(|| Fail::Auth("no token: Set token".into()))?;
        let ep = self.def.endpoint.clone();
        let http = self.http.get_or_insert_with(|| {
            HttpClient::new(
                ep.tls,
                ep.host.clone(),
                ep.port,
                self.def.ca_pem.clone(),
                self.def.timeout_ms,
            )
        });
        let kind = self.def.kind;
        let path = (kind.path)(&ep.base, &token, method);
        let bearer = format!("Bearer {token}");
        let mut headers = Vec::new();
        if kind.bearer {
            headers.push(("Authorization", bearer.as_str()));
        }
        headers.push(("Content-Type", "application/json; charset=utf-8"));
        let bytes = body.to_string().into_bytes();
        // the path may hold the token: errors are built from the reply only, never from it
        let r = http
            .request(host, "POST", &path, &headers, &bytes)
            .map_err(|e| Fail::Transient(e.message().to_owned()))?;
        (kind.reply)(r.status, &r.body)
    }

    /// The platform's identify call (`getMe`, `auth.test`): the token works, and whose bot it is.
    fn identify(&mut self, host: &mut dyn Host) -> Result<Json, Fail> {
        let kind = self.def.kind;
        let me = self.call(host, kind.identify, &json!({}))?;
        self.username = (kind.identity)(&me);
        Ok(me)
    }

    fn back_off(&mut self, now: u64, msg: String) {
        self.backoff_ms = (self.backoff_ms * 2).clamp(FIRST_BACKOFF_MS, MAX_BACKOFF_MS);
        self.hold_until = now + self.backoff_ms * 1000;
        self.state = State::Waiting;
        self.error = msg;
        self.http = None;
    }

    /// The common reaction to a failed call outside the queue; `true` when it may go on.
    fn failed_call(&mut self, host: &mut dyn Host, now: u64, f: Fail) {
        match f {
            Fail::Auth(m) => {
                self.close(host);
                self.state = State::Failed;
                self.error = m;
            }
            Fail::Retry { after_ms, msg } => {
                self.hold_until = now + after_ms * 1000;
                self.state = State::Waiting;
                self.error = msg;
            }
            Fail::Transient(m) => {
                self.close(host);
                self.back_off(now, m);
            }
            Fail::Rejected(m) | Fail::Markup(m) => self.error = m,
        }
    }

    fn enqueue(&mut self, m: Outgoing) {
        if self.queue.len() as u64 >= self.def.queue_max {
            self.queue.pop_front();
            self.dropped += 1;
        }
        self.queue.push_back(m);
    }

    fn flush(&mut self, host: &mut dyn Host, now: u64) {
        let mut n = 0;
        while n < SENDS_PER_TICK {
            let Some(front) = self.queue.front() else {
                break;
            };
            let counted = !matches!(front.body, Body::Answer { .. } | Body::Leave);
            if self.def.kind.per_chat_us > 0 && counted {
                if let Some(t) = self.last_chat.get(&front.chat) {
                    if now < t + self.def.kind.per_chat_us {
                        break;
                    }
                }
            }
            let (method, body) = (self.def.kind.request)(front);
            let editing = front.edit.is_some();
            n += 1;
            let result = match self.call(host, &method, &body) {
                // an edit that changed nothing is done; one whose message is gone goes anew
                Err(Fail::Rejected(msg)) if editing && (self.def.kind.edit_unchanged)(&msg) => {
                    Ok(Json::Null)
                }
                Err(Fail::Rejected(msg)) if editing && (self.def.kind.edit_gone)(&msg) => {
                    if let Some(f) = self.queue.front_mut() {
                        f.edit = None;
                    }
                    continue;
                }
                r => r,
            };
            match result {
                Ok(reply) => {
                    let m = self.queue.pop_front();
                    if let Some(m) = &m {
                        // the id of what went out (an unchanged edit keeps the one it had)
                        let id = (self.def.kind.message_id)(&reply).or_else(|| m.edit.clone());
                        if let Some(id) = id {
                            if let Some(slot) = &m.slot {
                                if let Err(e) = store::put(host, slot, &Value::Str(id.clone())) {
                                    host.log(Level::Warn, &format!("{slot}: {}", e.msg));
                                }
                            }
                            if let Some(r) = &m.recipient {
                                self.last_ids.insert(r.clone(), id);
                            }
                        }
                    }
                    if counted {
                        self.sent += 1;
                        self.last_sent = now;
                        if let Some(m) = m {
                            self.last_chat.insert(m.chat, now);
                        }
                    }
                    self.backoff_ms = 0;
                    if self.state == State::Waiting {
                        self.state = State::Ready;
                        self.error.clear();
                    }
                }
                Err(Fail::Markup(msg)) => {
                    let plain = self.queue.front().and_then(Outgoing::plain);
                    match plain {
                        Some(p) => {
                            host.log(
                                Level::Warn,
                                &format!("bot {}: {msg}; sent as plain text", self.def.name),
                            );
                            if let Some(f) = self.queue.front_mut() {
                                *f = p;
                            }
                        }
                        None => {
                            self.queue.pop_front();
                            self.failed += 1;
                            self.error = msg;
                        }
                    }
                }
                Err(Fail::Rejected(msg)) => {
                    let m = self.queue.pop_front();
                    if counted {
                        self.failed += 1;
                    }
                    let origin = m.map(|m| m.origin).unwrap_or_default();
                    host.log(
                        Level::Warn,
                        &format!("bot {}: {origin}: {msg}", self.def.name),
                    );
                    self.error = format!("{origin}: {msg}");
                }
                Err(Fail::Transient(msg)) => {
                    if let Some(f) = self.queue.front_mut() {
                        f.attempts += 1;
                        if f.attempts >= MAX_ATTEMPTS {
                            self.queue.pop_front();
                            self.failed += 1;
                        }
                    }
                    self.close(host);
                    self.back_off(now, msg);
                    break;
                }
                Err(f) => {
                    self.failed_call(host, now, f);
                    break;
                }
            }
        }
    }

    /// Read updates (platforms with inbound); commands of paired users come back to be run.
    fn poll(&mut self, host: &mut dyn Host, now: u64, site: Option<&str>) -> Vec<Inbound> {
        let kind = self.def.kind;
        if !kind.inbound || !self.def.commands || now < self.next_poll {
            return Vec::new();
        }
        self.next_poll = now + self.def.poll_s * 1_000_000;
        let offset = store::offset(host, self.name());
        let Some((method, body)) = (kind.poll)(offset, UPDATES_PER_POLL) else {
            return Vec::new();
        };
        let result = match self.call(host, &method, &body) {
            Ok(r) => {
                self.poll_backoff_ms = 0;
                if self.error.starts_with(UPDATES_FAILED) {
                    self.error.clear();
                }
                r
            }
            // a token the platform refuses ends the bot, sending included
            Err(f @ Fail::Auth(_)) => {
                self.failed_call(host, now, f);
                return Vec::new();
            }
            // anything else holds the reading of updates only: sending goes on, `status` says
            // what sending does and `error` what failed (`updates: …`)
            Err(Fail::Retry { after_ms, msg }) => {
                self.next_poll = self.next_poll.max(now + after_ms * 1000);
                self.error = format!("{UPDATES_FAILED}{msg}");
                return Vec::new();
            }
            Err(Fail::Transient(m) | Fail::Rejected(m) | Fail::Markup(m)) => {
                self.poll_backoff_ms =
                    (self.poll_backoff_ms * 2).clamp(FIRST_BACKOFF_MS, MAX_BACKOFF_MS);
                self.next_poll = self.next_poll.max(now + self.poll_backoff_ms * 1000);
                self.error = format!("{UPDATES_FAILED}{m}");
                return Vec::new();
            }
        };
        let mut out = Vec::new();
        let mut next = offset;
        for u in (kind.updates)(&result) {
            next = next.max(u.id() + 1);
            if let Some(i) = self.update(host, now, u, site) {
                out.push(i);
            }
        }
        if next != offset {
            store::put_offset(host, self.name(), next);
        }
        out
    }

    fn user_of(&self, account: i64) -> Option<&str> {
        self.users
            .iter()
            .find(|(_, (u, _))| u.chat_id == Some(account) && u.status == UserStatus::Active)
            .map(|(n, _)| n.as_str())
    }

    fn recipient_of(&self, chat: i64) -> Option<&Recipient> {
        let c = chat.to_string();
        self.recipients.values().find(|r| r.chat == c)
    }

    fn reply(&mut self, chat: &str, text: impl Into<String>) {
        self.enqueue(Outgoing::text(chat, text, "reply"));
    }

    fn reject(&mut self, host: &mut dyn Host, what: &str) {
        self.rejected += 1;
        host.log(
            Level::Warn,
            &format!("bot {}: rejected {what}", self.def.name),
        );
    }

    /// One update: pairing, rejection, or a command to run.
    fn update(
        &mut self,
        host: &mut dyn Host,
        now: u64,
        u: Update,
        _site: Option<&str>,
    ) -> Option<Inbound> {
        match u {
            Update::Other { chat, .. } => {
                // added to a chat that is no recipient: leave it
                if let Some((id, ty)) = chat {
                    if ty != "private" && self.recipient_of(id).is_none() && self.def.leave_unknown
                    {
                        self.reject(host, &format!("chat {id} ({ty}): no recipient, leaving it"));
                        let mut m = Outgoing::text(id.to_string(), "", "leave");
                        m.body = Body::Leave;
                        self.enqueue(m);
                    }
                }
                None
            }
            Update::Message {
                chat_id,
                chat_type,
                from_id,
                from_is_bot,
                text,
                ..
            } => {
                let from = from_id?;
                if from_is_bot {
                    return None;
                }
                let me = (!self.username.is_empty()).then(|| self.username.clone());
                let cmd = auth::parse_command(&text, me.as_deref());
                let chat = chat_id.to_string();
                if chat_type == "private" {
                    if let Some(user) = self.user_of(from).map(str::to_owned) {
                        let cmd = cmd?;
                        return Some(Inbound { user, chat, cmd });
                    }
                    match cmd {
                        Some(c) if c.name == "start" && !c.args.is_empty() => {
                            self.pair(host, now, from, &chat, &c.args);
                        }
                        _ => {
                            self.reject(host, &format!("account {from}: not paired"));
                            let last = self.nagged.get(&from).copied().unwrap_or(0);
                            if last == 0 || now >= last + auth::NAG_EVERY_US {
                                self.nagged.insert(from, now);
                                self.reply(&chat, "Not authorized. Ask the operator for an invite code, then send /start <code> here.");
                            }
                        }
                    }
                    return None;
                }
                // a group: a code posted here is exposed and void
                if let Some(c) = cmd
                    .as_ref()
                    .filter(|c| c.name == "start" && !c.args.is_empty())
                {
                    let h = auth::hash_code(&c.args);
                    let hit = self
                        .users
                        .iter()
                        .find(|(_, (u, _))| {
                            u.code_hash.as_deref().is_some_and(|x| auth::same(x, &h))
                        })
                        .map(|(n, _)| n.clone());
                    if let Some(n) = hit {
                        if let Some((u, _)) = self.users.get_mut(&n) {
                            u.code_hash = None;
                            let v = u.to_value();
                            let _ = store::put(host, &store::item('u', &self.def.name, &n), &v);
                        }
                        host.log(
                            Level::Warn,
                            &format!(
                                "bot {}: user {n}: pairing code sent in group {chat_id}, voided",
                                self.def.name
                            ),
                        );
                        if self.recipient_of(chat_id).is_some() {
                            self.reply(&chat, "That code was sent in a group and is void now. Ask for a new one and send it in a private chat.");
                        }
                    }
                    return None;
                }
                let Some(r) = self.recipient_of(chat_id) else {
                    self.reject(host, &format!("chat {chat_id} ({chat_type}): no recipient"));
                    if self.def.leave_unknown && chat_type != "channel" {
                        let mut m = Outgoing::text(chat.clone(), "", "leave");
                        m.body = Body::Leave;
                        self.enqueue(m);
                    }
                    return None;
                };
                if !r.commands {
                    return None;
                }
                let cmd = cmd?;
                match self.user_of(from).map(str::to_owned) {
                    Some(user) => Some(Inbound { user, chat, cmd }),
                    None => {
                        self.reject(
                            host,
                            &format!("account {from} in chat {chat_id}: not paired"),
                        );
                        None
                    }
                }
            }
            Update::Callback {
                id,
                chat_id,
                chat_type,
                from_id,
                data,
                ..
            } => {
                let mut ans = Outgoing::text(String::new(), "", "answer");
                let allowed_chat = match chat_id {
                    Some(c) if chat_type == "private" => c == from_id,
                    Some(c) => self.recipient_of(c).is_some_and(|r| r.commands),
                    None => false,
                };
                let user = self.user_of(from_id).map(str::to_owned);
                let (text, run) = match (user, allowed_chat) {
                    (Some(user), true) => match auth::parse_command(&data, None) {
                        Some(cmd) => (
                            "…".to_owned(),
                            Some(Inbound {
                                user,
                                chat: chat_id.map(|c| c.to_string()).unwrap_or_default(),
                                cmd,
                            }),
                        ),
                        None => ("Not a command".to_owned(), None),
                    },
                    _ => {
                        self.reject(host, &format!("button from account {from_id}"));
                        ("Not authorized".to_owned(), None)
                    }
                };
                ans.body = Body::Answer { id, text };
                self.enqueue(ans);
                run
            }
        }
    }

    /// `/start <code>` in a private chat.
    fn pair(&mut self, host: &mut dyn Host, now: u64, account: i64, chat: &str, code: &str) {
        let (bad, since) = self.bad_codes.get(&account).copied().unwrap_or((0, now));
        if bad >= auth::MAX_BAD_CODES && now < since + auth::LOCKOUT_US {
            self.reject(host, &format!("account {account}: pairing locked out"));
            return;
        }
        if bad >= auth::MAX_BAD_CODES {
            self.bad_codes.remove(&account);
        }
        let h = auth::hash_code(code);
        let hit = self
            .users
            .iter()
            .find(|(_, (u, _))| {
                u.status == UserStatus::Pending
                    && now < u.code_expires_us
                    && u.code_hash.as_deref().is_some_and(|x| auth::same(x, &h))
            })
            .map(|(n, _)| n.clone());
        let Some(name) = hit else {
            let e = self.bad_codes.entry(account).or_insert((0, now));
            e.0 += 1;
            let count = e.0;
            self.reject(
                host,
                &format!("account {account}: wrong or expired pairing code"),
            );
            if count <= auth::MAX_BAD_CODES {
                self.reply(chat, "This code is not valid or has expired.");
            }
            return;
        };
        if let Some(other) = self
            .users
            .iter()
            .find(|(n, (u, _))| **n != name && u.chat_id == Some(account))
            .map(|(n, _)| n.clone())
        {
            self.reply(chat, format!("This account is already paired as {other}."));
            return;
        }
        self.bad_codes.remove(&account);
        let bot = self.def.name.clone();
        let Some((u, _)) = self.users.get_mut(&name) else {
            return;
        };
        u.status = UserStatus::Active;
        u.chat_id = Some(account);
        u.code_hash = None;
        u.code_expires_us = 0;
        u.paired_us = now;
        let text = format!(
            "Paired as {name} ({}, keys: {}). Send /help.",
            u.level.name(),
            u.select.join(", ")
        );
        let v = u.to_value();
        if let Err(e) = store::put(host, &store::item('u', &bot, &name), &v) {
            host.log(Level::Error, &format!("bot {bot}: user {name}: {}", e.msg));
        }
        host.log(
            Level::Info,
            &format!("bot {bot}: user {name} paired with account {account}"),
        );
        self.show_user(host, &name, now);
        self.reply(chat, text);
    }

    fn next_delay_ms(&self, now: u64) -> Option<u64> {
        let until = |t: u64| t.saturating_sub(now) / 1000;
        match self.state {
            State::Disabled | State::Failed | State::NoToken => None,
            _ if now < self.hold_until => Some(until(self.hold_until).max(1)),
            State::Checking => Some(1),
            State::Ready | State::Waiting => {
                let mut d: Option<u64> = None;
                if !self.queue.is_empty() {
                    d = Some(FLUSH_MS);
                }
                if self.def.kind.inbound && self.def.commands {
                    let p = until(self.next_poll).max(1);
                    d = Some(d.map_or(p, |x| x.min(p)));
                }
                d
            }
        }
    }

    /// Recipient name → `(chat, thread, silent)`.
    fn resolve(&self, r: &str) -> Result<(String, Option<String>, bool), String> {
        let rec = self
            .recipients
            .get(r)
            .ok_or_else(|| format!("to: {r}: no such recipient"))?;
        let chat = match rec.user() {
            Some(u) => match self.users.get(u) {
                Some((user, _)) if user.status == UserStatus::Active => user
                    .chat_id
                    .map(|i| i.to_string())
                    .ok_or_else(|| format!("to: {r}: user {u} is not paired"))?,
                _ => return Err(format!("to: {r}: user {u} is not paired or disabled")),
            },
            None => rec.chat.clone(),
        };
        Ok((chat, rec.thread.clone(), rec.silent))
    }
}

/// A template with its placeholders filled in, for every recipient alike.
struct Rendered {
    body: Body,
    buttons: Vec<Vec<model::Button>>,
    silent: bool,
    protect: bool,
    preview: bool,
}

/// A messenger link on platform `C` (`Messenger<Telegram>`, `Messenger<Slack>`).
pub struct Messenger<C: Chat> {
    site: Option<String>,
    own: Option<String>,
    net: Option<String>,
    bots: BTreeMap<String, Bot>,
    timers: HashMap<u64, String>,
    /// Live values templates bind: key → subscription, and the latest sample.
    watches: BTreeMap<String, SubId>,
    watch_key: HashMap<u64, String>,
    latest: HashMap<String, Sample>,
    /// `/get` reads by subscription id, their timeouts by timer id.
    reads: HashMap<u64, Pending>,
    read_timers: HashMap<u64, u64>,
    /// `/set` and `/do` by request id.
    reqs: HashMap<u64, Pending>,
    stats_shown: BTreeMap<&'static str, u64>,
    removed: (u64, u64, u64),
    chat: PhantomData<C>,
}

struct Params {
    site: Option<String>,
    own: Option<String>,
    net: Option<String>,
}

fn params_of(config: Value) -> Result<Params, AppError> {
    let m = match config {
        Value::Map(m) => m,
        Value::Null => Map::new(),
        _ => return Err(invalid("params: a map")),
    };
    let f = Form(&m);
    f.reject_unknown(&["site", "own", "net"])
        .map_err(|e| invalid(format!("params.{e}")))?;
    Ok(Params {
        site: f.text("site").map_err(invalid)?,
        own: f.text("own").map_err(invalid)?,
        net: f.text("net").map_err(invalid)?,
    })
}

impl<C: Chat> Messenger<C> {
    fn bot(&self, name: &str) -> Result<&Bot, AppError> {
        self.bots
            .get(name)
            .ok_or_else(|| AppError::new(Status::NotFound, name))
    }

    fn bot_mut(&mut self, name: &str) -> Result<&mut Bot, AppError> {
        self.bots
            .get_mut(name)
            .ok_or_else(|| AppError::new(Status::NotFound, name))
    }

    fn put_bot_index(&self, host: &mut dyn Host) -> Result<(), AppError> {
        store::put_index(host, store::BOTS, self.bots.keys())
    }

    fn arm(&mut self, host: &mut dyn Host, name: &str) {
        let now = host.now_us();
        let Some(bot) = self.bots.get_mut(name) else {
            return;
        };
        if let Some(t) = bot.timer.take() {
            host.cancel_timer(t);
            self.timers.remove(&t.0);
        }
        if let Some(ms) = bot.next_delay_ms(now) {
            match host.set_timer(ms.max(1)) {
                Ok(t) => {
                    bot.timer = Some(t);
                    self.timers.insert(t.0, name.to_owned());
                }
                Err(e) => host.log(Level::Error, &format!("timer: {}", e.msg)),
            }
        }
    }

    fn show_stats(&mut self, host: &mut dyn Host, now: u64) {
        let sum = |f: fn(&Bot) -> u64| self.bots.values().map(f).sum::<u64>();
        let vals = [
            ("bots", self.bots.len() as u64),
            ("sent", sum(|b| b.sent) + self.removed.0),
            ("failed", sum(|b| b.failed) + self.removed.1),
            ("rejected", sum(|b| b.rejected) + self.removed.2),
        ];
        for (n, v) in vals {
            if self.stats_shown.get(n) != Some(&v) {
                self.stats_shown.insert(n, v);
                host.update(
                    &tree::stat(n),
                    Sample {
                        v: Value::UInt(v),
                        q: Quality::Good,
                        t: now,
                    },
                );
            }
        }
    }

    fn refresh(&mut self, host: &mut dyn Host, name: &str) {
        let now = host.now_us();
        if let Some(b) = self.bots.get_mut(name) {
            b.show(host, now);
        }
        self.arm(host, name);
        self.show_stats(host, now);
    }

    // ---------- declaring ----------

    fn declare_bot(host: &mut dyn Host, def: &BotDef) {
        let n = &def.name;
        host.declare_node(n, tree::bot_node(def.kind));
        for (l, ty, about) in tree::BOT_LEAVES {
            let meta = if l == "status" {
                tree::bot_status()
            } else {
                wyrm_core::NodeMeta::leaf(ty).attr("description", about)
            };
            host.declare_node(&tree::leaf(n, l), meta);
        }
        host.declare_node(&tree::leaf(n, "enabled"), tree::enabled_node());
        host.declare_node(&tree::leaf(n, "recipients"), wyrm_core::NodeMeta::folder());
        host.declare_node(&tree::leaf(n, "templates"), wyrm_core::NodeMeta::folder());
        if def.kind.inbound {
            host.declare_node(&tree::leaf(n, "users"), wyrm_core::NodeMeta::folder());
        }
        for (a, meta) in tree::bot_actions(def.kind) {
            host.declare_action(n, a, meta);
        }
    }

    fn declare_recipient(host: &mut dyn Host, kind: Kind, bot: &str, r: &Recipient) {
        let p = tree::recipient_path(bot, &r.name);
        host.declare_node(&p, tree::recipient_node(r));
        host.declare_node(
            &tree::leaf(&p, "last_message_id"),
            wyrm_core::NodeMeta::leaf(wyrm_core::TypeCode::String).attr(
                "description",
                "The platform's id of the last message this recipient got (message_id, ts)",
            ),
        );
        for (a, meta) in tree::recipient_actions(kind) {
            host.declare_action(&p, a, meta);
        }
    }

    fn declare_template(host: &mut dyn Host, kind: Kind, bot: &str, t: &Template) {
        let p = tree::template_path(bot, &t.name);
        host.declare_node(&p, tree::template_node(t));
        let vars = t.vars().unwrap_or_default();
        for (a, meta) in tree::template_actions(kind, &vars) {
            host.declare_action(&p, a, meta);
        }
    }

    fn declare_user(host: &mut dyn Host, bot: &str, u: &User) {
        let p = tree::user_path(bot, &u.name);
        host.declare_node(&p, tree::user_node(u));
        for (l, ty, about) in tree::USER_LEAVES {
            let meta = if l == "status" {
                tree::user_status()
            } else {
                wyrm_core::NodeMeta::leaf(ty).attr("description", about)
            };
            host.declare_node(&tree::leaf(&p, l), meta);
        }
        for (a, meta) in tree::user_actions() {
            host.declare_action(&p, a, meta);
        }
    }

    // ---------- template values ----------

    /// Subscribe the values templates bind (with their author's rights), drop the others.
    fn resync_watches(&mut self, host: &mut dyn Host) {
        let mut wanted = BTreeSet::new();
        for b in self.bots.values() {
            for (t, rights) in b.templates.values() {
                for (_, k) in &t.values {
                    if rights.as_ref().is_some_and(|r| r.may(k, Perm::Read)) {
                        wanted.insert(k.clone());
                    }
                }
            }
        }
        let gone: Vec<String> = self
            .watches
            .keys()
            .filter(|k| !wanted.contains(*k))
            .cloned()
            .collect();
        for k in gone {
            if let Some(id) = self.watches.remove(&k) {
                host.unsubscribe(id);
                self.watch_key.remove(&id.0);
            }
            self.latest.remove(&k);
        }
        for k in wanted {
            if self.watches.contains_key(&k) {
                continue;
            }
            match host.subscribe(&k) {
                Ok(id) => {
                    self.watches.insert(k.clone(), id);
                    self.watch_key.insert(id.0, k);
                }
                Err(e) => host.log(Level::Warn, &format!("subscribe {k}: {}", e.msg)),
            }
        }
    }

    // ---------- rendering ----------

    fn render(
        &self,
        host: &dyn Host,
        bot: &Bot,
        t: &Template,
        rights: Option<&Rights>,
        vars: &Map,
    ) -> Result<Rendered, AppError> {
        let now = host.now_us();
        let site = self.site.clone().unwrap_or_default();
        let lookup = |name: &str, m: &render::Modifier| -> Option<String> {
            use render::Modifier as M;
            match name {
                "site" => return Some(site.clone()),
                "bot" => return Some(bot.def.name.clone()),
                "now" => return Some(rfc3339(now)),
                _ => {}
            }
            if let Some((_, key)) = t.values.iter().find(|(a, _)| a == name) {
                let allowed = rights.is_some_and(|r| r.may(key, Perm::Read));
                let s = self.latest.get(key).filter(|_| allowed);
                return Some(match (s, m) {
                    (None, M::Quality) => "bad".into(),
                    (None, _) => "n/a".into(),
                    (Some(s), M::Quality) => s.q.name().into(),
                    (Some(s), M::Time) => rfc3339(s.t),
                    (Some(s), M::Decimals(d)) => render::value_text(&s.v, Some(*d)),
                    (Some(s), M::None) => render::value_text(&s.v, None),
                });
            }
            // a variable of the send that was not given shows as `n/a`, as a value with none
            // yet: the message says something is missing instead of leaving a gap
            let Some(v) = vars.get(name) else {
                return Some("n/a".into());
            };
            Some(match m {
                render::Modifier::Decimals(d) => render::value_text(v, Some(*d)),
                _ => render::value_text(v, None),
            })
        };
        let esc = t.format.escape();
        let r = |s: &str, how: render::Escape| render::render(s, how, &lookup).map_err(invalid);
        let text = r(&t.text, esc)?;
        let number = |s: &str, what: &str| -> Result<f64, AppError> {
            r(s, render::Escape::None)?
                .trim()
                .parse::<f64>()
                .ok()
                .filter(|x| x.is_finite())
                .ok_or_else(|| invalid(format!("{what}: not a number after filling in")))
        };
        let body = if !t.blocks.is_empty() {
            let blocks = r(&t.blocks, render::Escape::JsonMrkdwn)?;
            let blocks: Json = serde_json::from_str(&blocks)
                .map_err(|e| invalid(format!("blocks: not JSON after filling in: {e}")))?;
            // the notification text has no markup of its own
            let plain = r(&t.text, render::Escape::Mrkdwn)?;
            Body::Blocks {
                text: plain,
                blocks,
            }
        } else {
            match t.kind {
                MsgKind::Text => Body::Text {
                    text,
                    format: t.format,
                },
                MsgKind::Photo => Body::Photo {
                    media: r(&t.media, render::Escape::None)?,
                    caption: text,
                    format: t.format,
                },
                MsgKind::Document => Body::Document {
                    media: r(&t.media, render::Escape::None)?,
                    caption: text,
                    format: t.format,
                },
                MsgKind::Location => Body::Location {
                    lat: number(&t.lat, "lat")?,
                    lon: number(&t.lon, "lon")?,
                },
            }
        };
        let mut buttons = Vec::new();
        for row in &t.buttons {
            let mut out = Vec::new();
            for b in row {
                let target = r(&b.target, render::Escape::None)?;
                if !b.is_url() && target.len() > 64 {
                    return Err(invalid("buttons: a command over 64 bytes after filling in"));
                }
                out.push(model::Button {
                    label: r(&b.label, render::Escape::None)?,
                    target,
                });
            }
            buttons.push(out);
        }
        Ok(Rendered {
            body,
            buttons,
            silent: t.silent,
            protect: t.protect,
            preview: t.preview,
        })
    }

    /// Queue one rendered message to each recipient; `{queued, to}`.
    fn deliver(
        &mut self,
        host: &mut dyn Host,
        bot_name: &str,
        to: &[String],
        rendered: Rendered,
        origin: &str,
        update: Option<&str>,
    ) -> Result<Value, AppError> {
        if to.is_empty() {
            return Err(invalid("to: no recipients"));
        }
        if let Some(u) = update {
            let key = store::updates_key(bot_name);
            let mut names = store::index(host, &key);
            if !names.iter().any(|n| n == u) {
                if names.len() >= model::MAX_UPDATES {
                    return Err(AppError::new(
                        Status::ResourceExhausted,
                        format!(
                            "update: at most {} edited messages per bot",
                            model::MAX_UPDATES
                        ),
                    ));
                }
                names.push(u.to_owned());
                store::put_index(host, &key, names.iter())?;
            }
        }
        let editable = Outgoing {
            body: rendered.body.clone(),
            ..Outgoing::text("", "", origin)
        }
        .editable();
        let mut out = Vec::new();
        {
            let bot = self.bot(bot_name)?;
            if bot.state == State::Disabled {
                return Err(AppError::new(Status::NotSupported, "the bot is disabled"));
            }
            for r in to {
                let (chat, thread, silent) = bot.resolve(r).map_err(invalid)?;
                let (edit, slot) = match update {
                    Some(u) if editable => (
                        store::slot(host, bot_name, u, r),
                        Some(store::slot_key(bot_name, u, r)),
                    ),
                    _ => (None, None),
                };
                out.push(Outgoing {
                    chat,
                    thread,
                    body: rendered.body.clone(),
                    buttons: rendered.buttons.clone(),
                    silent: rendered.silent || silent,
                    protect: rendered.protect,
                    preview: rendered.preview,
                    origin: format!("{origin} → {r}"),
                    attempts: 0,
                    edit,
                    slot,
                    recipient: bot.recipients.contains_key(r).then(|| r.clone()),
                });
            }
        }
        let bot = self.bot_mut(bot_name)?;
        let n = out.len() as u64;
        for m in out {
            bot.enqueue(m);
        }
        self.refresh(host, bot_name);
        Ok(Value::Map(Map::from([
            ("queued".into(), Value::UInt(n)),
            (
                "to".into(),
                Value::Array(to.iter().cloned().map(Value::Str).collect()),
            ),
        ])))
    }

    /// `to` of a send: a list, or the default.
    fn to_of(m: &Map, default: &[String]) -> Result<Vec<String>, AppError> {
        let to = Form(m).list("to").map_err(invalid)?;
        Ok(if to.is_empty() { default.to_vec() } else { to })
    }

    fn send_template(
        &mut self,
        host: &mut dyn Host,
        bot: &str,
        name: &str,
        mut args: Map,
        preview: bool,
    ) -> Result<Value, AppError> {
        let b = self.bot(bot)?;
        let (t, rights) = b
            .templates
            .get(name)
            .ok_or_else(|| AppError::new(Status::NotFound, name))?;
        if rights.is_none() {
            return Err(denied("no author rights kept for this template: Edit it"));
        }
        let to = Self::to_of(&args, &t.to)?;
        args.remove("to");
        let update = match args.remove("update") {
            None | Some(Value::Null) => None,
            Some(Value::Str(u)) if u.trim().is_empty() => None,
            Some(Value::Str(u)) => {
                render::check_var(u.trim()).map_err(|e| invalid(format!("update: {e}")))?;
                Some(u.trim().to_owned())
            }
            Some(_) => return Err(invalid("update: a name")),
        };
        if let Some(Value::Map(v)) = args.remove("vars") {
            for (k, x) in v {
                args.entry(k).or_insert(x);
            }
        }
        let rendered = self.render(host, b, t, rights.as_ref(), &args)?;
        if preview {
            let chat = to
                .first()
                .and_then(|r| b.resolve(r).ok())
                .map(|(c, _, _)| c)
                .unwrap_or_else(|| "<chat>".into());
            let m = Outgoing {
                chat,
                thread: None,
                body: rendered.body,
                buttons: rendered.buttons,
                silent: rendered.silent,
                protect: rendered.protect,
                preview: rendered.preview,
                origin: name.into(),
                attempts: 0,
                edit: None,
                slot: None,
                recipient: None,
            };
            let (method, body) = (b.def.kind.request)(&m);
            return Ok(Value::Map(Map::from([
                ("method".into(), Value::Str(method)),
                ("body".into(), Value::Str(body.to_string())),
                (
                    "to".into(),
                    Value::Array(to.into_iter().map(Value::Str).collect()),
                ),
            ])));
        }
        let origin = format!("template {name}");
        self.deliver(host, bot, &to, rendered, &origin, update.as_deref())
    }

    /// Ad-hoc `send` of a bot or of one recipient: a template made on the spot, built-ins only.
    fn send_ad_hoc(
        &mut self,
        host: &mut dyn Host,
        bot: &str,
        mut args: Map,
        fixed_to: Option<&str>,
    ) -> Result<Value, AppError> {
        let kind = self.bot(bot)?.def.kind;
        let to = match fixed_to {
            Some(r) => vec![r.to_owned()],
            None => Self::to_of(&args, &[])?,
        };
        args.remove("to");
        if !args.contains_key("format") {
            let f = self.bot(bot)?.def.format;
            args.insert("format".into(), Value::Str(f.name().into()));
        }
        let allowed = ["kind", "format", "text", "media", "lat", "lon", "silent"];
        if let Some(k) = args.keys().find(|k| !allowed.contains(&k.as_str())) {
            return Err(invalid(format!("{k}: unknown")));
        }
        let t = Template::parse("send", kind, &args).map_err(invalid)?;
        if let Some(v) = t.vars().map_err(invalid)?.first() {
            return Err(invalid(format!(
                "{{{{{v}}}}}: a message sent ad hoc fills in only {{{{site}}}}, {{{{bot}}}}, {{{{now}}}}; use a template"
            )));
        }
        let b = self.bot(bot)?;
        let rendered = self.render(host, b, &t, None, &Map::new())?;
        self.deliver(host, bot, &to, rendered, "send", None)
    }

    fn send_raw(&mut self, host: &mut dyn Host, bot: &str, args: &Map) -> Result<Value, AppError> {
        let f = Form(args);
        let method = f.required("method").map_err(invalid)?;
        let b = self.bot_mut(bot)?;
        let kind = b.def.kind;
        let m = kind.raw_method_allowed(&method).map_err(invalid)?;
        let params: Json = match f.text("params").map_err(invalid)? {
            None => json!({}),
            Some(p) => {
                serde_json::from_str(&p).map_err(|e| invalid(format!("params: JSON: {e}")))?
            }
        };
        // fail closed: every chat the request names must be a recipient's or a paired user's
        for chat in kind.raw_chats(m, &params).map_err(invalid)? {
            let known = b.recipients.values().any(|r| r.chat == chat)
                || b.users.values().any(|(u, _)| {
                    u.status == UserStatus::Active
                        && u.chat_id.map(|i| i.to_string()) == Some(chat.clone())
                });
            if !known {
                return Err(denied(format!("{chat}: not a recipient's chat")));
            }
        }
        if !matches!(b.state, State::Ready | State::Waiting | State::Checking) {
            return Err(AppError::new(
                Status::NotSupported,
                format!("the bot is {}", b.state.name()),
            ));
        }
        let r = b.call(host, &method, &params);
        let now = host.now_us();
        let out = match r {
            Ok(j) => Ok(Value::Map(Map::from([
                ("ok".into(), Value::Bool(true)),
                ("result".into(), Value::Str(j.to_string())),
            ]))),
            Err(f) => {
                let msg = f.message().to_owned();
                b.failed_call(host, now, f);
                Err(AppError::new(Status::Disconnected, msg))
            }
        };
        self.refresh(host, bot);
        out
    }

    // ---------- chat commands ----------

    fn may(&self, bot: &Bot, user: &str, key: &str, need: Perm) -> Result<(), String> {
        let (u, rights) = bot.users.get(user).ok_or("no such user")?;
        if !u.may(key, need) {
            return Err(format!(
                "{key}: outside your keys or level ({}: {})",
                u.level.name(),
                u.select.join(", ")
            ));
        }
        let r = rights
            .as_ref()
            .ok_or("no operator rights kept for you: ask to Edit your user")?;
        if !r.may(key, need) {
            return Err(format!("{key}: outside the rights of who invited you"));
        }
        if need >= Perm::Write {
            if let Some(own) = &self.own {
                if key == own || key.starts_with(&format!("{own}/")) {
                    return Err("the messenger itself is not set from a chat".into());
                }
            }
        }
        Ok(())
    }

    fn help(level: Perm) -> String {
        let mut s = String::from(
            "/get <key> — the value of a point (downstream/plc/t1 or wy/<site>/…)\n/whoami — your name, level and keys",
        );
        if level >= Perm::Write {
            s.push_str("\n/set <key> <value> — write a point\n/do <key> <action> — run an action without arguments");
        }
        s
    }

    fn run(&mut self, host: &mut dyn Host, bot_name: &str, i: Inbound) {
        let now = host.now_us();
        let site = self.site.clone();
        let Some(bot) = self.bots.get_mut(bot_name) else {
            return;
        };
        let per_min = bot.def.rate_per_min;
        let bucket = bot
            .buckets
            .entry(i.user.clone())
            .or_insert_with(|| auth::Bucket::new(per_min, now));
        if !bucket.take(per_min, now) {
            bot.reply(&i.chat, "Too many commands: wait a minute.");
            return;
        }
        let e = bot.seen.entry(i.user.clone()).or_insert((0, 0));
        *e = (now, e.1 + 1);
        bot.show_user(host, &i.user, now);
        let Some(level) = bot.users.get(&i.user).map(|(u, _)| u.level) else {
            return;
        };
        host.log(
            Level::Info,
            &format!(
                "bot {bot_name}: user {} /{} {}",
                i.user,
                i.cmd.name,
                i.cmd.args.split_whitespace().next().unwrap_or("")
            ),
        );
        let reply = |s: &mut Self, text: String| {
            if let Some(b) = s.bots.get_mut(bot_name) {
                b.reply(&i.chat, text);
            }
        };
        match i.cmd.name.as_str() {
            "help" | "start" => reply(self, Self::help(level)),
            "whoami" => {
                let text = bot
                    .users
                    .get(&i.user)
                    .map(|(u, _)| {
                        format!(
                            "{} ({}), keys: {}",
                            u.name,
                            u.level.name(),
                            u.select.join(", ")
                        )
                    })
                    .unwrap_or_default();
                reply(self, text);
            }
            "get" => {
                let key = match auth::full_key(&i.cmd.args, site.as_deref()) {
                    Ok(k) => k,
                    Err(e) => return reply(self, format!("/get <key>: {e}")),
                };
                let bot = &self.bots[bot_name];
                if let Err(e) = self.may(bot, &i.user, &key, Perm::Read) {
                    return reply(self, e);
                }
                match host.subscribe(&key) {
                    Ok(id) => {
                        let timer = host.set_timer(READ_WAIT_MS).ok();
                        if let Some(t) = timer {
                            self.read_timers.insert(t.0, id.0);
                        }
                        self.reads.insert(
                            id.0,
                            Pending {
                                bot: bot_name.to_owned(),
                                chat: i.chat.clone(),
                                what: key,
                                timer,
                            },
                        );
                    }
                    Err(e) => reply(self, format!("{key}: {}", e.msg)),
                }
            }
            "set" | "do" => {
                let set = i.cmd.name == "set";
                let usage = if set {
                    "/set <key> <value>"
                } else {
                    "/do <key> <action>"
                };
                let Some((k, rest)) = i.cmd.args.split_once(char::is_whitespace) else {
                    return reply(self, usage.to_owned());
                };
                let key = match auth::full_key(k, site.as_deref()) {
                    Ok(k) => k,
                    Err(e) => return reply(self, format!("{usage}: {e}")),
                };
                let bot = &self.bots[bot_name];
                if let Err(e) = self.may(bot, &i.user, &key, Perm::Write) {
                    return reply(self, e);
                }
                let r = if set {
                    host.set(&key, auth::typed_value(rest))
                } else {
                    let action = rest.trim();
                    if action.is_empty()
                        || action.len() > 64
                        || !action
                            .bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b == b'_')
                    {
                        return reply(self, format!("{usage}: an action name"));
                    }
                    host.invoke(&key, action, Value::Null)
                };
                match r {
                    Ok(id) => {
                        let what = if set {
                            format!("{key} set")
                        } else {
                            format!("{key} ▸ {}", rest.trim())
                        };
                        self.reqs.insert(
                            id.0,
                            Pending {
                                bot: bot_name.to_owned(),
                                chat: i.chat.clone(),
                                what,
                                timer: None,
                            },
                        );
                    }
                    Err(e) => reply(self, format!("{key}: {}", e.msg)),
                }
            }
            _ => reply(self, "Unknown command: /help".to_owned()),
        }
    }

    fn tick(&mut self, host: &mut dyn Host, name: &str) {
        let now = host.now_us();
        let site = self.site.clone();
        let Some(bot) = self.bots.get_mut(name) else {
            return;
        };
        if now < bot.hold_until {
            self.refresh(host, name);
            return;
        }
        let mut inbound = Vec::new();
        match bot.state {
            State::Checking => match bot.identify(host) {
                Ok(_) => {
                    bot.state = State::Ready;
                    bot.error.clear();
                    bot.backoff_ms = 0;
                    host.log(
                        Level::Info,
                        &format!("bot {name}: ready as {}", bot.username),
                    );
                }
                Err(f) => {
                    bot.failed_call(host, now, f);
                    if bot.state != State::Failed {
                        if bot.hold_until <= now {
                            let e = bot.error.clone();
                            bot.back_off(now, e);
                        }
                        bot.state = State::Checking;
                    }
                }
            },
            State::Ready | State::Waiting => {
                bot.flush(host, now);
                if matches!(bot.state, State::Ready | State::Waiting) && now >= bot.hold_until {
                    inbound = bot.poll(host, now, site.as_deref());
                }
            }
            _ => {}
        }
        for i in inbound {
            self.run(host, name, i);
        }
        self.refresh(host, name);
    }

    // ---------- definitions ----------

    fn add_bot(&mut self, host: &mut dyn Host, def: BotDef) -> Result<(), AppError> {
        if self.bots.contains_key(&def.name) {
            return Err(invalid(format!("name: {} exists", def.name)));
        }
        if self.bots.len() >= model::MAX_BOTS {
            return Err(AppError::new(
                Status::ResourceExhausted,
                format!("at most {} bots", model::MAX_BOTS),
            ));
        }
        store::put(host, &store::bot(&def.name), &def.to_value())?;
        Self::declare_bot(host, &def);
        let name = def.name.clone();
        let has = store::secret(host, &name).is_some();
        self.bots.insert(name.clone(), Bot::new(def, has));
        self.put_bot_index(host)?;
        self.refresh(host, &name);
        Ok(())
    }

    fn load(&mut self, host: &mut dyn Host) {
        for name in store::index(host, store::BOTS) {
            let def = match store::get(host, &store::bot(&name))
                .map(|v| BotDef::from_value(&v, C::PLATFORM))
            {
                Some(Ok(d)) => d,
                Some(Err(e)) => {
                    host.log(Level::Error, &format!("bot {name}: {e}"));
                    continue;
                }
                None => continue,
            };
            let kind = def.kind;
            Self::declare_bot(host, &def);
            let has = store::secret(host, &name).is_some();
            let mut bot = Bot::new(def, has);
            for r in store::index(host, &store::coll('r', &name)) {
                match store::get(host, &store::item('r', &name, &r))
                    .map(|v| Recipient::from_value(&v, kind))
                {
                    Some(Ok(rec)) => {
                        Self::declare_recipient(host, kind, &name, &rec);
                        bot.recipients.insert(r, rec);
                    }
                    Some(Err(e)) => {
                        host.log(Level::Error, &format!("bot {name}: recipient {r}: {e}"))
                    }
                    None => {}
                }
            }
            for t in store::index(host, &store::coll('t', &name)) {
                match store::get(host, &store::item('t', &name, &t))
                    .map(|v| Template::from_value(&v, kind))
                {
                    Some(Ok(tpl)) => {
                        Self::declare_template(host, kind, &name, &tpl);
                        let rights = store::load_rights(host, 't', &name, &t);
                        if rights.is_none() {
                            host.log(
                                Level::Warn,
                                &format!(
                                    "bot {name}: template {t}: no author rights kept: Edit it"
                                ),
                            );
                        }
                        bot.templates.insert(t, (tpl, rights));
                    }
                    Some(Err(e)) => {
                        host.log(Level::Error, &format!("bot {name}: template {t}: {e}"))
                    }
                    None => {}
                }
            }
            for u in store::index(host, &store::coll('u', &name)) {
                match store::get(host, &store::item('u', &name, &u)).map(|v| User::from_value(&v)) {
                    Some(Ok(user)) => {
                        Self::declare_user(host, &name, &user);
                        let rights = store::load_rights(host, 'u', &name, &u);
                        bot.users.insert(u, (user, rights));
                    }
                    Some(Err(e)) => host.log(Level::Error, &format!("bot {name}: user {u}: {e}")),
                    None => {}
                }
            }
            let now = host.now_us();
            let users: Vec<String> = bot.users.keys().cloned().collect();
            for u in users {
                bot.show_user(host, &u, now);
            }
            self.bots.insert(name.clone(), bot);
            self.refresh(host, &name);
        }
        self.resync_watches(host);
    }

    fn put_coll(
        host: &mut dyn Host,
        c: char,
        bot: &str,
        names: impl Iterator<Item = String>,
    ) -> Result<(), AppError> {
        let v: Vec<String> = names.collect();
        store::put_index(host, &store::coll(c, bot), v.iter())
    }

    /// Merge an Edit's arguments over the stored form (`null` or empty text clears a field).
    fn merged(mut base: Map, args: &Map, keep: &[&str]) -> Map {
        for k in keep {
            base.remove(*k);
        }
        for (k, v) in args {
            match v {
                Value::Null => {
                    base.remove(k);
                }
                Value::Str(s) if s.is_empty() => {
                    base.remove(k);
                }
                v => {
                    base.insert(k.clone(), v.clone());
                }
            }
        }
        base
    }

    fn check_user_rights(rights: &Rights, level: Perm, select: &[String]) -> Result<(), AppError> {
        if let Some(k) = select.iter().find(|k| !rights.may(k, level)) {
            return Err(denied(format!(
                "select: {k} at {} is outside the caller's rights",
                level.name()
            )));
        }
        Ok(())
    }

    fn issue_code(host: &mut dyn Host, u: &mut User) -> Result<(String, u64), AppError> {
        let random = host.random_bytes(8).map_err(|e| {
            AppError::new(
                Status::NotSupported,
                format!("pairing codes need the host's random source: {}", e.msg),
            )
        })?;
        let code = auth::new_code(&random)
            .ok_or_else(|| AppError::new(Status::InternalError, "random source too short"))?;
        let exp = host.now_us() + auth::CODE_TTL_US;
        u.code_hash = Some(auth::hash_code(&code));
        u.code_expires_us = exp;
        Ok((code, exp))
    }

    fn code_reply(bot: &Bot, name: &str, code: &str, exp: u64) -> Value {
        let who = if bot.username.is_empty() {
            "the bot".to_owned()
        } else {
            format!("@{}", bot.username)
        };
        Value::Map(Map::from([
            ("user".into(), Value::Str(name.to_owned())),
            ("code".into(), Value::Str(code.to_owned())),
            ("expires".into(), Value::Str(rfc3339(exp))),
            (
                "how".into(),
                Value::Str(format!(
                    "Give the code to {name} only. They send /start {code} to {who} in a private chat before {}. It works once.",
                    rfc3339(exp)
                )),
            ),
        ]))
    }

    fn bot_invoke(
        &mut self,
        host: &mut dyn Host,
        bot: &str,
        action: &str,
        m: Map,
        who: &Who,
    ) -> Result<Value, AppError> {
        let kind = self.bot(bot)?.def.kind;
        let now = host.now_us();
        match action {
            "send" => self.send_ad_hoc(host, bot, m, None),
            "send_raw" => self.send_raw(host, bot, &m),
            "set_token" => {
                let token = Form(&m).required("token").map_err(invalid)?;
                let token = token.trim().to_owned();
                check_token(kind, &token)?;
                host.store_put(&store::secret_key(bot), token.as_bytes())?;
                let b = self.bot_mut(bot)?;
                b.restart(host);
                host.log(Level::Info, &format!("bot {bot}: token set"));
                self.refresh(host, bot);
                Ok(Value::Null)
            }
            "test_connection" => {
                let b = self.bot_mut(bot)?;
                let r = b.identify(host);
                let out = match r {
                    Ok(_) => {
                        if b.state != State::Disabled {
                            b.state = State::Ready;
                            b.error.clear();
                        }
                        Value::Map(Map::from([
                            ("ok".into(), Value::Bool(true)),
                            ("username".into(), Value::Str(b.username.clone())),
                        ]))
                    }
                    Err(f) => {
                        let msg = f.message().to_owned();
                        b.failed_call(host, now, f);
                        Value::Map(Map::from([
                            ("ok".into(), Value::Bool(false)),
                            ("error".into(), Value::Str(msg)),
                        ]))
                    }
                };
                self.refresh(host, bot);
                Ok(out)
            }
            "edit" => {
                let b = self.bot(bot)?;
                let fields = Self::merged(b.def.fields(), &m, &[]);
                let def =
                    BotDef::parse(bot, kind, &fields, self.net.as_deref()).map_err(invalid)?;
                let moved = def.endpoint != b.def.endpoint || def.ca_pem != b.def.ca_pem;
                store::put(host, &store::bot(bot), &def.to_value())?;
                if moved {
                    // a token never goes to a host it was not set for
                    host.store_delete(&store::secret_key(bot));
                    host.store_delete(&store::offset_key(bot));
                }
                let b = self.bot_mut(bot)?;
                b.def = def;
                b.restart(host);
                self.refresh(host, bot);
                Ok(Value::Null)
            }
            "remove" => {
                let mut b = self
                    .bots
                    .remove(bot)
                    .ok_or_else(|| AppError::new(Status::NotFound, bot))?;
                if let Some(t) = b.timer.take() {
                    host.cancel_timer(t);
                    self.timers.remove(&t.0);
                }
                b.close(host);
                self.removed.0 += b.sent;
                self.removed.1 += b.failed;
                self.removed.2 += b.rejected;
                host.remove_node(bot);
                store::delete_bot(host, bot);
                self.put_bot_index(host)?;
                self.resync_watches(host);
                self.show_stats(host, now);
                Ok(Value::Null)
            }
            "add_recipient" => {
                let name = Form(&m).required("name").map_err(invalid)?;
                let mut fields = m.clone();
                fields.remove("name");
                let r = Recipient::parse(name.trim(), kind, &fields).map_err(invalid)?;
                let b = self.bot(bot)?;
                if b.recipients.contains_key(&r.name) {
                    return Err(invalid(format!("name: {} exists", r.name)));
                }
                if b.recipients.len() >= model::MAX_RECIPIENTS {
                    return Err(AppError::new(
                        Status::ResourceExhausted,
                        "too many recipients",
                    ));
                }
                store::put(host, &store::item('r', bot, &r.name), &r.to_value())?;
                let names = b.recipients.keys().cloned().chain([r.name.clone()]);
                Self::put_coll(host, 'r', bot, names.collect::<Vec<_>>().into_iter())?;
                Self::declare_recipient(host, kind, bot, &r);
                self.bot_mut(bot)?.recipients.insert(r.name.clone(), r);
                Ok(Value::Null)
            }
            "add_template" => {
                let name = Form(&m).required("name").map_err(invalid)?;
                let mut fields = m.clone();
                fields.remove("name");
                let t = Template::parse(name.trim(), kind, &fields).map_err(invalid)?;
                let rights = caller_rights(who, "a template")?;
                if let Some((_, k)) = t.values.iter().find(|(_, k)| !rights.may(k, Perm::Read)) {
                    return Err(denied(format!(
                        "values: {k} is outside the caller's rights"
                    )));
                }
                let b = self.bot(bot)?;
                if b.templates.contains_key(&t.name) {
                    return Err(invalid(format!("name: {} exists", t.name)));
                }
                if b.templates.len() >= model::MAX_TEMPLATES {
                    return Err(AppError::new(
                        Status::ResourceExhausted,
                        "too many templates",
                    ));
                }
                store::put(host, &store::item('t', bot, &t.name), &t.to_value())?;
                store::put_rights(host, 't', bot, &t.name, &rights)?;
                let names = b.templates.keys().cloned().chain([t.name.clone()]);
                Self::put_coll(host, 't', bot, names.collect::<Vec<_>>().into_iter())?;
                Self::declare_template(host, kind, bot, &t);
                self.bot_mut(bot)?
                    .templates
                    .insert(t.name.clone(), (t, Some(rights)));
                self.resync_watches(host);
                Ok(Value::Null)
            }
            "invite_user" if kind.inbound => {
                let name = Form(&m)
                    .required("name")
                    .map_err(invalid)?
                    .trim()
                    .to_owned();
                model::check_name(&name, "name").map_err(invalid)?;
                let mut fields = m.clone();
                fields.remove("name");
                let (level, select) =
                    User::parse_rights(&fields, self.site.as_deref()).map_err(invalid)?;
                let rights = caller_rights(who, "a chat user")?;
                Self::check_user_rights(&rights, level, &select)?;
                let b = self.bot(bot)?;
                if b.users.contains_key(&name) {
                    return Err(invalid(format!("name: {name} exists")));
                }
                if b.users.len() >= model::MAX_USERS {
                    return Err(AppError::new(Status::ResourceExhausted, "too many users"));
                }
                let mut u = User {
                    name: name.clone(),
                    level,
                    select,
                    status: UserStatus::Pending,
                    chat_id: None,
                    code_hash: None,
                    code_expires_us: 0,
                    paired_us: 0,
                };
                let (code, exp) = Self::issue_code(host, &mut u)?;
                store::put(host, &store::item('u', bot, &name), &u.to_value())?;
                store::put_rights(host, 'u', bot, &name, &rights)?;
                let names = b.users.keys().cloned().chain([name.clone()]);
                Self::put_coll(host, 'u', bot, names.collect::<Vec<_>>().into_iter())?;
                Self::declare_user(host, bot, &u);
                host.log(
                    Level::Info,
                    &format!(
                        "bot {bot}: user {name} invited by {}",
                        who.subject.as_deref().unwrap_or("?")
                    ),
                );
                let b = self.bot_mut(bot)?;
                b.users.insert(name.clone(), (u, Some(rights)));
                b.show_user(host, &name, now);
                Ok(Self::code_reply(b, &name, &code, exp))
            }
            _ => Err(AppError::new(Status::NotSupported, action.to_owned())),
        }
    }

    fn child_invoke(
        &mut self,
        host: &mut dyn Host,
        bot: &str,
        (coll, name): (&str, &str),
        action: &str,
        m: Map,
        who: &Who,
    ) -> Result<Value, AppError> {
        let kind = self.bot(bot)?.def.kind;
        let now = host.now_us();
        match (coll, action) {
            ("recipients", "send") => {
                if !self.bot(bot)?.recipients.contains_key(name) {
                    return Err(AppError::new(Status::NotFound, name.to_owned()));
                }
                self.send_ad_hoc(host, bot, m, Some(name))
            }
            ("recipients", "edit") => {
                let b = self.bot(bot)?;
                let r = b
                    .recipients
                    .get(name)
                    .ok_or_else(|| AppError::new(Status::NotFound, name.to_owned()))?;
                let Value::Map(base) = r.to_value() else {
                    unreachable!()
                };
                let fields = Self::merged(base, &m, &["name"]);
                let r = Recipient::parse(name, kind, &fields).map_err(invalid)?;
                store::put(host, &store::item('r', bot, name), &r.to_value())?;
                Self::declare_recipient(host, kind, bot, &r);
                self.bot_mut(bot)?.recipients.insert(name.to_owned(), r);
                Ok(Value::Null)
            }
            ("recipients", "remove") => {
                let b = self.bot_mut(bot)?;
                b.recipients
                    .remove(name)
                    .ok_or_else(|| AppError::new(Status::NotFound, name.to_owned()))?;
                b.last_ids.remove(name);
                b.shown
                    .retain(|k, _| !k.starts_with(&tree::recipient_path(bot, name)));
                let names: Vec<String> = b.recipients.keys().cloned().collect();
                store::delete_item(host, 'r', bot, name);
                store::delete_slots_of(host, bot, name);
                Self::put_coll(host, 'r', bot, names.into_iter())?;
                host.remove_node(&tree::recipient_path(bot, name));
                Ok(Value::Null)
            }
            ("templates", "send") => self.send_template(host, bot, name, m, false),
            ("templates", "preview") => self.send_template(host, bot, name, m, true),
            ("templates", "edit") => {
                let b = self.bot(bot)?;
                let (t, _) = b
                    .templates
                    .get(name)
                    .ok_or_else(|| AppError::new(Status::NotFound, name.to_owned()))?;
                let Value::Map(base) = t.to_value() else {
                    unreachable!()
                };
                let fields = Self::merged(base, &m, &["name"]);
                let t = Template::parse(name, kind, &fields).map_err(invalid)?;
                let rights = caller_rights(who, "a template")?;
                if let Some((_, k)) = t.values.iter().find(|(_, k)| !rights.may(k, Perm::Read)) {
                    return Err(denied(format!(
                        "values: {k} is outside the caller's rights"
                    )));
                }
                store::put(host, &store::item('t', bot, name), &t.to_value())?;
                store::put_rights(host, 't', bot, name, &rights)?;
                // the Send form follows the template's variables
                host.remove_node(&tree::template_path(bot, name));
                Self::declare_template(host, kind, bot, &t);
                self.bot_mut(bot)?
                    .templates
                    .insert(name.to_owned(), (t, Some(rights)));
                self.resync_watches(host);
                Ok(Value::Null)
            }
            ("templates", "remove") => {
                let b = self.bot_mut(bot)?;
                b.templates
                    .remove(name)
                    .ok_or_else(|| AppError::new(Status::NotFound, name.to_owned()))?;
                let names: Vec<String> = b.templates.keys().cloned().collect();
                store::delete_item(host, 't', bot, name);
                Self::put_coll(host, 't', bot, names.into_iter())?;
                host.remove_node(&tree::template_path(bot, name));
                self.resync_watches(host);
                Ok(Value::Null)
            }
            ("users", _) if kind.inbound => {
                let (mut u, old_rights) = self
                    .bot(bot)?
                    .users
                    .get(name)
                    .cloned()
                    .ok_or_else(|| AppError::new(Status::NotFound, name.to_owned()))?;
                let mut rights = old_rights;
                let mut out = Value::Null;
                match action {
                    "remove" => {
                        let b = self.bot_mut(bot)?;
                        b.users.remove(name);
                        b.buckets.remove(name);
                        b.seen.remove(name);
                        let names: Vec<String> = b.users.keys().cloned().collect();
                        store::delete_item(host, 'u', bot, name);
                        Self::put_coll(host, 'u', bot, names.into_iter())?;
                        host.remove_node(&tree::user_path(bot, name));
                        host.log(
                            Level::Info,
                            &format!(
                                "bot {bot}: user {name} removed by {}",
                                who.subject.as_deref().unwrap_or("?")
                            ),
                        );
                        return Ok(Value::Null);
                    }
                    "edit" => {
                        let mut base = Map::new();
                        base.insert("level".into(), Value::Str(u.level.name().into()));
                        base.insert("select".into(), Value::Str(u.select.join("\n")));
                        let fields = Self::merged(base, &m, &[]);
                        let (level, select) =
                            User::parse_rights(&fields, self.site.as_deref()).map_err(invalid)?;
                        let r = caller_rights(who, "a chat user")?;
                        Self::check_user_rights(&r, level, &select)?;
                        u.level = level;
                        u.select = select;
                        rights = Some(r);
                    }
                    "new_code" => {
                        // re-pairing moves the user's rights to another account: only someone
                        // who holds them may do it
                        let r = caller_rights(who, "a chat user")?;
                        Self::check_user_rights(&r, u.level, &u.select)?;
                        u.status = UserStatus::Pending;
                        u.chat_id = None;
                        u.paired_us = 0;
                        let (code, exp) = Self::issue_code(host, &mut u)?;
                        rights = Some(r);
                        out = Self::code_reply(self.bot(bot)?, name, &code, exp);
                    }
                    "enable" => {
                        // enabling hands the user's rights back to the paired account: only
                        // someone who holds them may do it (as New Pairing Code and Edit); the
                        // rights kept with the user stay the inviter's, so they never widen
                        let r = caller_rights(who, "a chat user")?;
                        Self::check_user_rights(&r, u.level, &u.select)?;
                        if u.chat_id.is_none() {
                            return Err(invalid("not paired: New pairing code"));
                        }
                        u.status = UserStatus::Active;
                    }
                    "disable" => u.status = UserStatus::Disabled,
                    _ => return Err(AppError::new(Status::NotSupported, action.to_owned())),
                }
                store::put(host, &store::item('u', bot, name), &u.to_value())?;
                if let Some(r) = &rights {
                    store::put_rights(host, 'u', bot, name, r)?;
                }
                host.log(
                    Level::Info,
                    &format!(
                        "bot {bot}: user {name} {action} by {}",
                        who.subject.as_deref().unwrap_or("?")
                    ),
                );
                let b = self.bot_mut(bot)?;
                b.users.insert(name.to_owned(), (u, rights));
                b.show_user(host, name, now);
                Ok(out)
            }
            _ => Err(AppError::new(Status::NotSupported, action.to_owned())),
        }
    }
}

impl<C: Chat> App for Messenger<C> {
    const NAME: &'static str = C::PLATFORM.name;
    const VERSION: &'static str = C::VERSION;

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        let Params { site, own, net } = params_of(config)?;
        let (name, a) = tree::add_bot(C::PLATFORM);
        host.declare_action("", &name, a);
        host.declare_node(tree::STATS, wyrm_core::NodeMeta::folder());
        for n in tree::STAT_NAMES {
            host.declare_node(
                &tree::stat(n),
                wyrm_core::NodeMeta::leaf(wyrm_core::TypeCode::Number),
            );
        }
        let mut app = Messenger {
            site,
            own,
            net,
            bots: BTreeMap::new(),
            timers: HashMap::new(),
            watches: BTreeMap::new(),
            watch_key: HashMap::new(),
            latest: HashMap::new(),
            reads: HashMap::new(),
            read_timers: HashMap::new(),
            reqs: HashMap::new(),
            stats_shown: BTreeMap::new(),
            removed: (0, 0, 0),
            chat: PhantomData,
        };
        app.load(host);
        let now = host.now_us();
        app.show_stats(host, now);
        Ok(app)
    }

    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        let Some(name) = path.strip_suffix("/enabled").filter(|n| !n.contains('/')) else {
            return Err(AppError::new(Status::NotSupported, path.to_owned()));
        };
        let Value::Bool(on) = value else {
            return Err(invalid("enabled: true or false"));
        };
        let b = self.bot_mut(name)?;
        b.def.enabled = on;
        let v = b.def.to_value();
        store::put(host, &store::bot(name), &v)?;
        let b = self.bot_mut(name)?;
        b.restart(host);
        self.refresh(host, name);
        Ok(())
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        action: &str,
        args: Value,
        who: &Who,
    ) -> Result<Value, AppError> {
        let m = args_of(args)?;
        let segs: Vec<&str> = if path.is_empty() {
            Vec::new()
        } else {
            path.split('/').collect()
        };
        match segs.as_slice() {
            [] => {
                if action != "add_bot" {
                    return Err(AppError::new(Status::NotSupported, action.to_owned()));
                }
                let kind = C::PLATFORM;
                let name = Form(&m).required("name").map_err(invalid)?;
                let mut fields = m.clone();
                fields.remove("name");
                let def = BotDef::parse(name.trim(), kind, &fields, self.net.as_deref())
                    .map_err(invalid)?;
                self.add_bot(host, def)?;
                Ok(Value::Null)
            }
            [bot] => self.bot_invoke(host, bot, action, m, who),
            [bot, coll, name] => self.child_invoke(host, bot, (coll, name), action, m, who),
            _ => Err(AppError::new(Status::NotSupported, path.to_owned())),
        }
    }

    fn on_timer(&mut self, host: &mut dyn Host, timer: TimerId) {
        if let Some(name) = self.timers.remove(&timer.0) {
            if let Some(b) = self.bots.get_mut(&name) {
                b.timer = None;
            }
            self.tick(host, &name);
            return;
        }
        if let Some(sub) = self.read_timers.remove(&timer.0) {
            if let Some(p) = self.reads.remove(&sub) {
                host.unsubscribe(SubId(sub));
                let name = p.bot.clone();
                if let Some(b) = self.bots.get_mut(&p.bot) {
                    b.reply(
                        &p.chat,
                        format!("{}: no value within {} s", p.what, READ_WAIT_MS / 1000),
                    );
                }
                self.arm(host, &name);
            }
        }
    }

    fn on_value(&mut self, host: &mut dyn Host, sub: SubId, key: &str, sample: Sample) {
        if let Some(k) = self.watch_key.get(&sub.0) {
            if k == key {
                self.latest.insert(key.to_owned(), sample);
            }
            return;
        }
        if let Some(p) = self.reads.remove(&sub.0) {
            host.unsubscribe(sub);
            if let Some(t) = p.timer {
                host.cancel_timer(t);
                self.read_timers.remove(&t.0);
            }
            let text = format!(
                "{} = {} ({}, {})",
                p.what,
                render::value_text(&sample.v, None),
                sample.q.name(),
                rfc3339(sample.t)
            );
            let name = p.bot.clone();
            if let Some(b) = self.bots.get_mut(&p.bot) {
                b.reply(&p.chat, text);
            }
            self.arm(host, &name);
        }
    }

    fn on_reply(&mut self, host: &mut dyn Host, req: ReqId, result: Result<Value, AppError>) {
        let Some(p) = self.reqs.remove(&req.0) else {
            return;
        };
        let text = match result {
            Ok(Value::Null) => format!("{}: done", p.what),
            Ok(v) => format!(
                "{}: {}",
                p.what,
                render::cut(&render::value_text(&v, None), 500)
            ),
            Err(e) => format!("{}: {}", p.what, e),
        };
        let name = p.bot.clone();
        if let Some(b) = self.bots.get_mut(&p.bot) {
            b.reply(&p.chat, text);
        }
        self.arm(host, &name);
    }

    fn stop(&mut self, host: &mut dyn Host) {
        for b in self.bots.values_mut() {
            b.close(host);
        }
    }
}
