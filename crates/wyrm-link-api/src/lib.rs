//! The portable link API (ADR 0023): the [`App`] a link implements and the [`Host`] it acts through.
//!
//! One link source runs embedded in the broker, as a process and as a WASM component. The host calls
//! the app one event at a time. The app answers synchronously and acts through a `Host` handle.
//! This crate has no async and no I/O, and it builds for `wasm32-unknown-unknown`.

#![forbid(unsafe_code)]

pub mod buffer;
pub mod net;
mod rights;

pub use rights::Rights;

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
    /// The caller's whole grant set on this site (spec 04 `auth`), capped by the responder as its
    /// effective level: what an app acting for the caller may check the keys it names against.
    /// It never authorizes the call itself. `None`: the caller's rights are unknown.
    pub authority: Option<Vec<(String, Perm)>>,
}

impl Who {
    /// The caller holds at least `need` on `key`: the first grant that intersects `key` decides,
    /// as at the responder and the gateway (spec 04, `wyrm_core::ptok::level_on`).
    pub fn may(&self, key: &str, need: Perm) -> bool {
        level(&self.grants, key) >= need
    }

    /// The caller's own rights (its `authority`) give at least `need` on `key`; `false` when they
    /// are unknown. The first intersecting grant decides, as in [`Who::may`]: a grant shadowed by
    /// an earlier one is dead here as at the gateway (review DQL-2).
    pub fn may_for(&self, key: &str, need: Perm) -> bool {
        self.authority
            .as_ref()
            .is_some_and(|a| level(a, key) >= need)
    }

    pub fn to_cbor(&self) -> Vec<u8> {
        let mut e = Encoder::new(Vec::new());
        let n = 1 + u64::from(self.subject.is_some()) + u64::from(self.authority.is_some());
        // Writing to a `Vec` does not fail.
        let _ = (|| -> Result<(), minicbor::encode::Error<core::convert::Infallible>> {
            e.map(n)?.str("grants")?.array(self.grants.len() as u64)?;
            for (k, p) in &self.grants {
                e.encode(Grant {
                    k: k.clone(),
                    p: *p,
                })?;
            }
            if let Some(a) = &self.authority {
                e.str("auth")?.array(a.len() as u64)?;
                for (k, p) in a {
                    e.encode(Grant {
                        k: k.clone(),
                        p: *p,
                    })?;
                }
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
                "auth" => {
                    who.authority = Some(
                        d.array_iter::<Grant>()?
                            .map(|g| g.map(|g| (g.k, g.p)))
                            .collect::<Result<_, _>>()?,
                    );
                }
                _ => d.skip()?,
            }
        }
        Ok(who)
    }
}

fn level(grants: &[(String, Perm)], key: &str) -> Perm {
    wyrm_core::ptok::level_on(grants.iter().map(|(k, p)| (k.as_str(), *p)), key)
}

/// One change of a list made with [`Host::list`] (ADR 0023, amended by ADR 0025): the children of
/// one node, each a name and its own `~meta` summary.
#[derive(Debug, Clone, PartialEq)]
pub enum ListChange {
    /// The whole snapshot: first, and again after the owner reconnects or the queue overflowed.
    Refreshed(Vec<(String, NodeMeta)>),
    Added(String, NodeMeta),
    Changed(String, NodeMeta),
    Removed(String),
    /// The node's owner (its link) is gone; its children are gone with it.
    Disconnected,
}

impl ListChange {
    const REFRESHED: u8 = 0;
    const ADDED: u8 = 1;
    const CHANGED: u8 = 2;
    const REMOVED: u8 = 3;
    const DISCONNECTED: u8 = 4;

    /// CBOR `[kind, ...]`: `[0, [[name, meta]...]]`, `[1|2, name, meta]`, `[3, name]`, `[4]`.
    pub fn to_cbor(&self) -> Vec<u8> {
        let mut e = Encoder::new(Vec::new());
        // Writing to a `Vec` does not fail.
        let _ = (|| -> Result<(), minicbor::encode::Error<core::convert::Infallible>> {
            match self {
                ListChange::Refreshed(children) => {
                    e.array(2)?
                        .u8(Self::REFRESHED)?
                        .array(children.len() as u64)?;
                    for (n, m) in children {
                        e.array(2)?.str(n)?.encode(m)?;
                    }
                }
                ListChange::Added(n, m) => {
                    e.array(3)?.u8(Self::ADDED)?.str(n)?.encode(m)?;
                }
                ListChange::Changed(n, m) => {
                    e.array(3)?.u8(Self::CHANGED)?.str(n)?.encode(m)?;
                }
                ListChange::Removed(n) => {
                    e.array(2)?.u8(Self::REMOVED)?.str(n)?;
                }
                ListChange::Disconnected => {
                    e.array(1)?.u8(Self::DISCONNECTED)?;
                }
            }
            Ok(())
        })();
        e.into_writer()
    }

    pub fn from_cbor(bytes: &[u8]) -> Result<Self, minicbor::decode::Error> {
        let mut d = Decoder::new(bytes);
        d.array()?;
        let child = |d: &mut Decoder<'_>| -> Result<(String, NodeMeta), minicbor::decode::Error> {
            Ok((d.str()?.to_owned(), d.decode()?))
        };
        Ok(match d.u8()? {
            Self::REFRESHED => {
                let n = d
                    .array()?
                    .ok_or_else(|| minicbor::decode::Error::message("indefinite array"))?;
                let mut out = Vec::new();
                for _ in 0..n {
                    d.array()?;
                    out.push(child(&mut d)?);
                }
                ListChange::Refreshed(out)
            }
            Self::ADDED => {
                let (n, m) = child(&mut d)?;
                ListChange::Added(n, m)
            }
            Self::CHANGED => {
                let (n, m) = child(&mut d)?;
                ListChange::Changed(n, m)
            }
            Self::REMOVED => ListChange::Removed(d.str()?.to_owned()),
            Self::DISCONNECTED => ListChange::Disconnected,
            k => {
                return Err(minicbor::decode::Error::message(format!(
                    "unknown list change {k}"
                )))
            }
        })
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
    /// A change of a list made with [`Host::list`] (`key`: the listed node).
    fn on_list(&mut self, _host: &mut dyn Host, _sub: SubId, _key: &str, _change: ListChange) {}
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
    /// Values of `key`, or of every node under `<prefix>` when `key` is `<prefix>/**` (one
    /// subscription for a subtree); each sample comes with its node key.
    fn subscribe(&mut self, key: &str) -> Result<SubId, AppError>;
    /// Ends a subscription or a list.
    fn unsubscribe(&mut self, sub: SubId);
    /// The children of `key`, reactive: [`App::on_list`] gets a [`ListChange::Refreshed`] first,
    /// then the changes (ADR 0025). Each child comes with its `view=list` summary, or with its
    /// whole `~meta` (`attr`, `actions`, …) when `full` (one more request per child). A host
    /// without lists answers `not_supported`.
    fn list(&mut self, _key: &str, _full: bool) -> Result<SubId, AppError> {
        Err(AppError::new(
            Status::NotSupported,
            "this host has no list (wyrm:app@0.1.0)",
        ))
    }
    /// The reply comes through [`App::on_reply`].
    fn set(&mut self, key: &str, value: Value) -> Result<ReqId, AppError>;
    fn invoke(&mut self, key: &str, action: &str, args: Value) -> Result<ReqId, AppError>;
    // network, within the link's `net` allowlist; `addr` is an IP literal, or a host name the
    // list names (resolved by the host, ordinary addresses only: ADR 0026)
    fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError>;
    fn tcp_send(&mut self, c: ConnId, data: &[u8]) -> Result<(), AppError>;
    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError>;
    fn tcp_close(&mut self, c: ConnId);
    /// TLS over TCP to `host:port` (a DNS name or an IP literal), within the
    /// `net` allowlist (ADR 0026): the host resolves the name, checks each
    /// address ([`net::NetPolicy::allows_named`]), and verifies the server's
    /// certificate for `host` against the system roots, or only against
    /// `ca_pem` when given. The connection then takes `tcp_send`, `tcp_recv`
    /// and `tcp_close` as a plain one; the keys stay in the host.
    fn tls_connect(
        &mut self,
        host: &str,
        port: u16,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<ConnId, AppError> {
        let _ = (host, port, timeout_ms, ca_pem);
        Err(AppError::new(
            Status::NotSupported,
            "tls_connect: this host has no TLS",
        ))
    }
    /// Start TLS on an open plain connection (`SSLRequest` of PostgreSQL and MySQL), verifying
    /// the server's certificate for `host` as [`tls_connect`](Self::tls_connect) does; the
    /// connection keeps its id. On an error the connection is closed.
    fn tls_upgrade(
        &mut self,
        c: ConnId,
        host: &str,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<(), AppError> {
        let _ = (c, host, timeout_ms, ca_pem);
        Err(AppError::new(
            Status::NotSupported,
            "tls_upgrade: this host has no TLS",
        ))
    }
    /// `n` bytes from the host's random source (the OS), at most [`MAX_RANDOM_BYTES`]; more is
    /// `invalid_parameter` (ADR 0030). A host without one answers `not_supported`.
    fn random_bytes(&mut self, n: u32) -> Result<Vec<u8>, AppError> {
        let _ = n;
        Err(AppError::new(
            Status::NotSupported,
            "random_bytes: this host has no random source",
        ))
    }
    fn log(&mut self, level: Level, msg: &str);
}

/// Largest [`Host::random_bytes`] request.
pub const MAX_RANDOM_BYTES: u32 = 1024;

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::{NodeMeta, Perm, Status};

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
    fn who_may_takes_the_first_intersecting_grant() {
        let mut who = Who {
            subject: None,
            grants: vec![
                ("wy/s/downstream/plc/**".into(), Perm::Write),
                ("wy/s/downstream/**".into(), Perm::Read),
            ],
            authority: None,
        };
        assert!(who.may("wy/s/downstream/plc/p1/~set", Perm::Write));
        assert!(!who.may("wy/s/downstream/x/~set", Perm::Write));
        // the wider grant first shadows the narrower one, as at the gateway
        who.grants.reverse();
        assert!(!who.may("wy/s/downstream/plc/p1/~set", Perm::Write));
        assert!(who.may("wy/s/downstream/plc/p1/~set", Perm::Read));
    }

    #[test]
    fn who_cbor_roundtrip() {
        let who = Who {
            subject: Some("user:ann".into()),
            grants: vec![("wy/s/**".into(), Perm::Config)],
            authority: None,
        };
        assert_eq!(Who::from_cbor(&who.to_cbor()).unwrap(), who);
        let anon = Who::default();
        assert_eq!(Who::from_cbor(&anon.to_cbor()).unwrap(), anon);
        assert!(Who::from_cbor(&[0xff]).is_err());
    }

    #[test]
    fn who_authority_travels_and_decides_may_for() {
        let who = Who {
            subject: Some("user:op".into()),
            grants: vec![("wy/s/downstream/dql/~act/run".into(), Perm::Write)],
            authority: Some(vec![
                ("wy/s/downstream/plc1/**".into(), Perm::Write),
                ("wy/s/downstream/**".into(), Perm::List),
            ]),
        };
        let bytes = who.to_cbor();
        assert_eq!(Who::from_cbor(&bytes).unwrap(), who);
        assert!(who.may_for("wy/s/downstream/plc1/t", Perm::Write));
        assert!(!who.may_for("wy/s/downstream/plc2/t", Perm::Read));
        assert!(!Who::default().may_for("wy/s/downstream/plc1/t", Perm::List));
        // a decoder from before `auth` (WIT 0.1.0 guests) skips the key it does not know
        let mut d = minicbor::Decoder::new(&bytes);
        let n = d.map().unwrap().unwrap();
        let mut sub = None;
        for _ in 0..n {
            match d.str().unwrap() {
                "sub" => sub = Some(d.str().unwrap().to_owned()),
                _ => d.skip().unwrap(),
            }
        }
        assert_eq!(sub.as_deref(), Some("user:op"));
    }

    #[test]
    fn list_change_cbor_roundtrip() {
        let meta = NodeMeta {
            display: Some("Fan".into()),
            ..NodeMeta::default()
        };
        for c in [
            ListChange::Refreshed(vec![
                ("a".into(), meta.clone()),
                ("b".into(), NodeMeta::default()),
            ]),
            ListChange::Refreshed(Vec::new()),
            ListChange::Added("a".into(), meta.clone()),
            ListChange::Changed("a".into(), meta),
            ListChange::Removed("a".into()),
            ListChange::Disconnected,
        ] {
            assert_eq!(ListChange::from_cbor(&c.to_cbor()).unwrap(), c);
        }
        assert!(ListChange::from_cbor(&[0x81, 0x09]).is_err());
    }

    #[test]
    fn level_codes() {
        for l in [Level::Error, Level::Warn, Level::Info, Level::Debug] {
            assert_eq!(Level::from_code(l.code()), l);
        }
        assert_eq!(Level::from_code(200), Level::Info);
    }
}
