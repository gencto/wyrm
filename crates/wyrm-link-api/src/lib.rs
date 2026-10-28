//! The portable link API (ADR 0023): the [`App`] a link implements and the [`Host`] it acts through.
//!
//! One link source runs embedded in the broker, as a process and as a WASM component. The host calls
//! the app one event at a time. The app answers synchronously and acts through a `Host` handle.
//! This crate has no async and no I/O, and it builds for `wasm32-unknown-unknown`.

#![forbid(unsafe_code)]

pub mod buffer;
pub mod net;

use minicbor::{Decoder, Encoder};
use wyrm_core::ptok::Grant;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Sample, Status, Value};

/// Handle of a timer set with [`Host::set_timer`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TimerId(pub u64);

/// Handle of a subscription made with [`Host::subscribe`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct SubId(pub u64);

/// Handle of a request made with [`Host::set`] or [`Host::invoke`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ReqId(pub u64);

/// Handle of a TCP connection opened with [`Host::tcp_connect`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ConnId(pub u32);

/// An error with a WYRM status. It crosses the WASM boundary as CBOR `{"status": code, "msg": text}`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppError {
    pub status: Status,
    pub msg: String,
}

impl AppError {
    pub fn new(status: Status, msg: impl Into<String>) -> Self {
        Self {
            status,
            msg: msg.into(),
        }
    }

    pub fn to_cbor(&self) -> Vec<u8> {
        let mut e = Encoder::new(Vec::new());
        // Writing to a `Vec` does not fail.
        let _ = e
            .map(2)
            .and_then(|e| e.str("msg"))
            .and_then(|e| e.str(&self.msg))
            .and_then(|e| e.str("status"))
            .and_then(|e| e.u8(self.status.code()));
        e.into_writer()
    }

    /// Bytes that do not decode, or carry a status code we do not know, give `internal_error`.
    pub fn from_cbor(bytes: &[u8]) -> Self {
        Self::try_from_cbor(bytes)
            .unwrap_or_else(|| Self::new(Status::InternalError, "unreadable error from the app"))
    }

    fn try_from_cbor(bytes: &[u8]) -> Option<Self> {
        let mut d = Decoder::new(bytes);
        let (mut status, mut msg) = (None, None);
        for _ in 0..d.map().ok()?? {
            match d.str().ok()? {
                "status" => status = Status::try_from(d.u8().ok()?).ok(),
                "msg" => msg = Some(d.str().ok()?.to_owned()),
                _ => d.skip().ok()?,
            }
        }
        Some(Self::new(status?, msg?))
    }
}

impl core::fmt::Display for AppError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "{}: {}", self.status.name(), self.msg)
    }
}

impl std::error::Error for AppError {}

/// The verified caller of a `set` or `invoke`: its subject and its grants (key pattern, level).
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Who {
    pub subject: Option<String>,
    pub grants: Vec<(String, Perm)>,
}

impl Who {
    /// The caller holds at least `need` on `key`. The longest matching grant decides. A pattern
    /// `<prefix>/**` covers `<prefix>` and everything below it; any other pattern covers that key only.
    pub fn may(&self, key: &str, need: Perm) -> bool {
        self.grants
            .iter()
            .filter(|(k, _)| covers(k, key))
            .max_by_key(|(k, _)| k.len())
            .is_some_and(|(_, p)| *p >= need)
    }

    pub fn to_cbor(&self) -> Vec<u8> {
        let mut e = Encoder::new(Vec::new());
        let n = if self.subject.is_some() { 2 } else { 1 };
        // Writing to a `Vec` does not fail.
        let _ = (|| -> Result<(), minicbor::encode::Error<core::convert::Infallible>> {
            e.map(n)?.str("grants")?.array(self.grants.len() as u64)?;
            for (k, p) in &self.grants {
                e.encode(Grant {
                    k: k.clone(),
                    p: *p,
                })?;
            }
            if let Some(s) = &self.subject {
                e.str("sub")?.str(s)?;
            }
            Ok(())
        })();
        e.into_writer()
    }

    /// A grant with an unknown level is an error: the caller is refused, never widened.
    pub fn from_cbor(bytes: &[u8]) -> Result<Self, minicbor::decode::Error> {
        let mut d = Decoder::new(bytes);
        let mut who = Who::default();
        let len = d
            .map()?
            .ok_or_else(|| minicbor::decode::Error::message("indefinite map"))?;
        for _ in 0..len {
            match d.str()? {
                "sub" => who.subject = Some(d.str()?.to_owned()),
                "grants" => {
                    who.grants = d
                        .array_iter::<Grant>()?
                        .map(|g| g.map(|g| (g.k, g.p)))
                        .collect::<Result<_, _>>()?;
                }
                _ => d.skip()?,
            }
        }
        Ok(who)
    }
}

fn covers(pattern: &str, key: &str) -> bool {
    match pattern.strip_suffix("/**") {
        Some(prefix) => {
            key == prefix || key.strip_prefix(prefix).is_some_and(|r| r.starts_with('/'))
        }
        None => pattern == key,
    }
}

/// Log level of [`Host::log`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Level {
    Error,
    Warn,
    Info,
    Debug,
}

impl Level {
    pub const fn code(self) -> u8 {
        match self {
            Level::Error => 0,
            Level::Warn => 1,
            Level::Info => 2,
            Level::Debug => 3,
        }
    }

    /// An unknown code is `Info`.
    pub const fn from_code(code: u8) -> Self {
        match code {
            0 => Level::Error,
            1 => Level::Warn,
            3 => Level::Debug,
            _ => Level::Info,
        }
    }
}

/// A link. The host calls one method at a time; effects go through the [`Host`] and are applied
/// after the method returns (ADR 0023).
pub trait App: Sized {
    const NAME: &'static str;
    const VERSION: &'static str;

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError>;
    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        who: &Who,
    ) -> Result<(), AppError>;
    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        action: &str,
        args: Value,
        who: &Who,
    ) -> Result<Value, AppError>;
    fn on_timer(&mut self, _host: &mut dyn Host, _timer: TimerId) {}
    fn on_value(&mut self, _host: &mut dyn Host, _sub: SubId, _key: &str, _sample: Sample) {}
    fn on_reply(&mut self, _host: &mut dyn Host, _req: ReqId, _result: Result<Value, AppError>) {}
    fn stop(&mut self, _host: &mut dyn Host) {}
}

/// What a host offers to an [`App`].
pub trait Host {
    // tree (the app owns its subtree)
    fn declare_node(&mut self, path: &str, meta: NodeMeta);
    fn declare_action(&mut self, path: &str, name: &str, action: ActionMeta);
    fn remove_node(&mut self, path: &str);
    fn update(&mut self, path: &str, sample: Sample);
    // time
    /// Wall clock, UTC microseconds.
    fn now_us(&self) -> u64;
    /// One-shot timer on the monotonic clock.
    fn set_timer(&mut self, after_ms: u64) -> Result<TimerId, AppError>;
    fn cancel_timer(&mut self, t: TimerId);
    // storage of the link itself: it survives restarts and upgrades
    fn store_get(&self, key: &str) -> Option<Vec<u8>>;
    /// Durable when the event returns.
    fn store_put(&mut self, key: &str, value: &[u8]) -> Result<(), AppError>;
    fn store_delete(&mut self, key: &str);
    // other points, within the link's grants
    fn subscribe(&mut self, key: &str) -> Result<SubId, AppError>;
    fn unsubscribe(&mut self, sub: SubId);
    /// The reply comes through [`App::on_reply`].
    fn set(&mut self, key: &str, value: Value) -> Result<ReqId, AppError>;
    fn invoke(&mut self, key: &str, action: &str, args: Value) -> Result<ReqId, AppError>;
    // network, within the link's `net` allowlist
    fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError>;
    fn tcp_send(&mut self, c: ConnId, data: &[u8]) -> Result<(), AppError>;
    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError>;
    fn tcp_close(&mut self, c: ConnId);
    fn log(&mut self, level: Level, msg: &str);
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::{Perm, Status};

    #[test]
    fn app_error_cbor_roundtrip() {
        let e = AppError::new(Status::PermissionDenied, "no grant on wy/s/downstream/x");
        assert_eq!(AppError::from_cbor(&e.to_cbor()), e);
        assert_eq!(
            AppError::from_cbor(&[0xff, 0x00, 0x13]).status,
            Status::InternalError
        );
    }

    #[test]
    fn who_may_uses_longest_prefix() {
        let who = Who {
            subject: None,
            grants: vec![
                ("wy/s/downstream/**".into(), Perm::Read),
                ("wy/s/downstream/plc/**".into(), Perm::Write),
            ],
        };
        assert!(who.may("wy/s/downstream/plc/p1/~set", Perm::Write));
        assert!(!who.may("wy/s/downstream/x/~set", Perm::Write));
    }

    #[test]
    fn who_cbor_roundtrip() {
        let who = Who {
            subject: Some("user:ann".into()),
            grants: vec![("wy/s/**".into(), Perm::Config)],
        };
        assert_eq!(Who::from_cbor(&who.to_cbor()).unwrap(), who);
        let anon = Who::default();
        assert_eq!(Who::from_cbor(&anon.to_cbor()).unwrap(), anon);
        assert!(Who::from_cbor(&[0xff]).is_err());
    }

    #[test]
    fn level_codes() {
        for l in [Level::Error, Level::Warn, Level::Info, Level::Debug] {
            assert_eq!(Level::from_code(l.code()), l);
        }
        assert_eq!(Level::from_code(200), Level::Info);
    }
}
