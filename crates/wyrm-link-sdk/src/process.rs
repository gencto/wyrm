//! Process mode (feature `process`): one connector per OS process,
//! supervised by `wyrm-admin`.
//!
//! The supervisor passes:
//!
//! | env | meaning |
//! |---|---|
//! | `WYRM_SITE`, `WYRM_LINK_ID` | identity (link id = certificate CN) |
//! | `WYRM_ENDPOINT` | router endpoint, e.g. `tls/127.0.0.1:7447` |
//! | `WYRM_CA`, `WYRM_CERT`, `WYRM_KEY` | mTLS files (required for `tls/` and `quic/`) |
//! | `WYRM_TOKEN_FILE` | link token (0600); deleted after reading if `WYRM_TOKEN_DELETE=1` |
//! | `WYRM_DATA_DIR` | optional private directory of the link ([`LinkConfig::data_dir`]) |
//!
//! Start-up: open the session → `hello` with the link token (retried with
//! backoff while the broker is away) → build `L::Config` from the returned
//! params → serve until SIGTERM/SIGINT.

use crate::error::{LinkError, Result};
use crate::link::Link;
use crate::params::FromParams;
use crate::runtime::{spawn, LinkConfig};
use crate::VerifyingKey;
use std::time::Duration;
use tracing::{info, warn};
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::status::StatusCode;
use wyrm_core::{Attachment, Status, StatusGroup, Value};
use zenoh::qos::{CongestionControl, Priority};
use zenoh::query::ConsolidationMode;
use zenoh::Session;
use zeroize::Zeroizing;

pub struct Env {
    pub site: String,
    pub link: String,
    pub endpoint: String,
    pub tls: Option<(String, String, String)>,
    pub data_dir: Option<std::path::PathBuf>,
    token: Zeroizing<Vec<u8>>,
}

fn var(name: &str) -> Result<String> {
    std::env::var(name).map_err(|_| LinkError::invalid_parameter(format!("env {name} is not set")))
}

impl Env {
    pub fn from_env() -> Result<Self> {
        let site = var("WYRM_SITE")?;
        let link = var("WYRM_LINK_ID")?;
        wyrm_core::keyspace::validate_segment(&site)?;
        wyrm_core::keyspace::validate_segment(&link)?;
        let endpoint = var("WYRM_ENDPOINT")?;
        let tls = match (var("WYRM_CA"), var("WYRM_CERT"), var("WYRM_KEY")) {
            (Ok(ca), Ok(cert), Ok(key)) => Some((ca, cert, key)),
            _ if endpoint.starts_with("tls/") || endpoint.starts_with("quic/") => {
                return Err(LinkError::invalid_parameter(
                    "WYRM_CA, WYRM_CERT and WYRM_KEY are required for tls/quic",
                ))
            }
            _ => None,
        };
        let path = var("WYRM_TOKEN_FILE")?;
        let text = Zeroizing::new(
            std::fs::read_to_string(&path)
                .map_err(|e| LinkError::invalid_parameter(format!("token file {path}: {e}")))?,
        );
        let token = Zeroizing::new(text.trim().as_bytes().to_vec());
        if std::env::var("WYRM_TOKEN_DELETE").as_deref() == Ok("1") {
            let _ = std::fs::remove_file(&path);
        }
        let data_dir = std::env::var_os("WYRM_DATA_DIR")
            .filter(|v| !v.is_empty())
            .map(std::path::PathBuf::from);
        Ok(Self {
            site,
            link,
            endpoint,
            tls,
            data_dir,
            token,
        })
    }

    pub fn zenoh_config(&self) -> Result<zenoh::Config> {
        let mut c = zenoh::Config::default();
        let set = |c: &mut zenoh::Config, k: &str, v: &str| {
            c.insert_json5(k, v)
                .map_err(|e| LinkError::invalid_parameter(format!("zenoh config {k}: {e}")))
        };
        set(&mut c, "mode", r#""client""#)?;
        set(
            &mut c,
            "connect/endpoints",
            &format!("[{:?}]", self.endpoint),
        )?;
        set(&mut c, "scouting/multicast/enabled", "false")?;
        if let Some((ca, cert, key)) = &self.tls {
            set(
                &mut c,
                "transport/link/tls",
                &format!(
                    "{{ root_ca_certificate: {ca:?}, connect_certificate: {cert:?}, connect_private_key: {key:?}, enable_mtls: true }}"
                ),
            )?;
        }
        Ok(c)
    }
}

/// What the admin answers to `hello`.
pub struct Hello {
    pub params: Value,
    pub admin_keys: Vec<VerifyingKey>,
    /// `limited_keys` `[[key, perm code, [scope, ...]], ...]` and
    /// `bound_keys` (the same plus a subject): keys trusted only up to a
    /// permission, only under their scopes, a bound one only for its subject.
    pub limited_keys: Vec<crate::auth::LimitedKey>,
    pub secrets: crate::SecretStore,
}

/// One trusted limited key from `hello`: `[key, cap, scopes]`, plus the
/// subject when `bound`.
fn limited_key(v: &Value, bound: bool) -> Result<crate::auth::LimitedKey> {
    let bad = |what: &str| LinkError::new(Status::InvalidMessage, format!("bad key {what}"));
    let Value::Array(kv) = v else {
        return Err(bad("entry"));
    };
    if kv.len() != if bound { 4 } else { 3 } {
        return Err(bad("entry"));
    }
    let cap = kv[1]
        .as_f64()
        .and_then(|c| u8::try_from(c as u64).ok())
        .and_then(|c| wyrm_core::Perm::try_from(c).ok())
        .ok_or_else(|| bad("cap"))?;
    let Value::Array(sc) = &kv[2] else {
        return Err(bad("scopes"));
    };
    let scopes = sc
        .iter()
        .map(|s| match s {
            Value::Str(s) => Ok(s.clone()),
            _ => Err(bad("scope")),
        })
        .collect::<Result<_>>()?;
    let subject = match kv.get(3) {
        None => None,
        Some(Value::Str(s)) => Some(s.clone()),
        Some(_) => return Err(bad("subject")),
    };
    Ok(crate::auth::LimitedKey {
        key: key_of(&kv[0])?,
        cap,
        scopes,
        subject,
    })
}

fn key_of(v: &Value) -> Result<VerifyingKey> {
    match v {
        Value::Bytes(b) => <[u8; 32]>::try_from(b.as_slice())
            .ok()
            .and_then(|b| VerifyingKey::from_bytes(&b).ok())
            .ok_or_else(|| LinkError::new(Status::InvalidMessage, "bad admin key")),
        _ => Err(LinkError::new(Status::InvalidMessage, "bad admin key")),
    }
}

fn parse_hello(v: Value) -> Result<Hello> {
    let Value::Map(mut m) = v else {
        return Err(LinkError::new(
            Status::InvalidMessage,
            "hello reply must be a map",
        ));
    };
    let params = m.remove("params").unwrap_or(Value::Map(Default::default()));
    let admin_keys = match m.remove("admin_keys") {
        Some(Value::Array(keys)) => keys.iter().map(key_of).collect::<Result<_>>()?,
        _ => Vec::new(),
    };
    // `[key, cap, scopes]` in `limited_keys`; keys bound to one subject
    // in `bound_keys` as `[key, cap, scopes, subject]`.
    let keys_of = |v: Option<Value>, bound: bool| -> Result<Vec<crate::auth::LimitedKey>> {
        match v {
            Some(Value::Array(entries)) => entries.iter().map(|e| limited_key(e, bound)).collect(),
            _ => Ok(Vec::new()),
        }
    };
    let mut limited_keys = keys_of(m.remove("limited_keys"), false)?;
    limited_keys.extend(keys_of(m.remove("bound_keys"), true)?);
    let secrets = match m.remove("secrets") {
        Some(Value::Map(s)) => s
            .into_iter()
            .filter_map(|(k, v)| match v {
                Value::Bytes(b) => Some((k, crate::Secret::new(b))),
                _ => None,
            })
            .collect(),
        _ => crate::SecretStore::default(),
    };
    Ok(Hello {
        params,
        admin_keys,
        limited_keys,
        secrets,
    })
}

/// One `hello` round trip. `Err` with `permission_denied` is final.
pub async fn hello(session: &Session, env: &Env) -> Result<Hello> {
    let key = format!("wy/{}/sys/links/{}/~act/hello", env.site, env.link);
    let mut args = std::collections::BTreeMap::new();
    args.insert("token".to_owned(), Value::Bytes(env.token.to_vec()));
    let payload = to_vec(&Value::Map(args)).map_err(|e| LinkError::internal(e.to_string()))?;
    let replies = session
        .get(&key)
        .payload(payload)
        .consolidation(ConsolidationMode::None)
        .priority(Priority::InteractiveHigh)
        .congestion_control(CongestionControl::Block)
        .express(true)
        .timeout(Duration::from_secs(5))
        .await?;
    let reply = replies
        .recv_async()
        .await
        .map_err(|_| LinkError::new(Status::Timeout, "no hello reply"))?;
    let sample = reply
        .result()
        .map_err(|_| LinkError::new(Status::InternalError, "hello reply error"))?;
    let att: Attachment = sample
        .attachment()
        .map(|a| from_slice(&a.to_bytes()))
        .transpose()
        .map_err(|_| LinkError::new(Status::InvalidMessage, "bad hello attachment"))?
        .unwrap_or_default();
    match att.status {
        Some(s) if s.group() == StatusGroup::Error => {
            let status = match s {
                StatusCode::Known(k) => k,
                _ => Status::InternalError,
            };
            return Err(LinkError::new(status, att.err.unwrap_or_default()));
        }
        None => {
            return Err(LinkError::new(
                Status::InvalidMessage,
                "hello reply without status",
            ))
        }
        _ => {}
    }
    let v: Value = from_slice(&sample.payload().to_bytes())
        .map_err(|_| LinkError::new(Status::InvalidMessage, "bad hello payload"))?;
    parse_hello(v)
}

/// Supervised links get `WYRM_PARENT_PID` (the broker's pid): when the
/// broker process is gone (crash, kill -9), the link exits too, so a new
/// broker never runs a second copy next to an orphan.
pub const PARENT_PID_ENV: &str = "WYRM_PARENT_PID";

async fn parent_gone() {
    #[cfg(unix)]
    if let Some(pid) = std::env::var(PARENT_PID_ENV)
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
    {
        loop {
            if std::os::unix::process::parent_id() != pid {
                warn!("supervising broker (pid {pid}) is gone: exiting");
                return;
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    }
    std::future::pending::<()>().await
}

async fn signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        if let Ok(mut term) = signal(SignalKind::terminate()) {
            tokio::select! {
                _ = term.recv() => {}
                _ = tokio::signal::ctrl_c() => {}
            }
            return;
        }
    }
    let _ = tokio::signal::ctrl_c().await;
}

/// The whole `main` of a link package binary: logs (`RUST_LOG`, default
/// `info,zenoh=warn`), the supervisor's limits before the runtime (some
/// reach only threads created later), then [`run`] on a multi-thread
/// runtime. Every package's `main.rs` is the same three lines:
///
/// ```ignore
/// fn main() -> std::process::ExitCode {
///     wyrm_link_sdk::process::main::<wyrm_link_modbus::Modbus>()
/// }
/// ```
pub fn main<L: Link>() -> std::process::ExitCode
where
    L::Config: FromParams,
{
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,zenoh=warn".into()),
        )
        .init();
    if let Err(e) = crate::limits::apply_from_env() {
        tracing::error!("link: {e}");
        return std::process::ExitCode::FAILURE;
    }
    let rt = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            tracing::error!("link: runtime: {e}");
            return std::process::ExitCode::FAILURE;
        }
    };
    match rt.block_on(run::<L>()) {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            tracing::error!("link: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}

/// Run `L` as a supervised process until SIGTERM/SIGINT.
pub async fn run<L: Link>() -> Result<()>
where
    L::Config: FromParams,
{
    // Before any network input: limits set by the supervisor (fail closed).
    // `main` applied them before the runtime (see `limits`); check here.
    if crate::limits::supervised() {
        crate::limits::Limits::from_env()?.apply_rlimits()?;
        #[cfg(target_os = "linux")]
        if !crate::limits::all_threads_no_new_privs().unwrap_or(false) {
            return Err(LinkError::internal(
                "no_new_privs is not set on every thread: call \
                 wyrm_link_sdk::limits::apply_from_env() in main before the runtime",
            ));
        }
    }
    // Also while waiting for the first `hello`: an orphan never lingers.
    tokio::select! {
        _ = parent_gone() => Ok(()),
        r = run_inner::<L>() => r,
    }
}

async fn run_inner<L: Link>() -> Result<()>
where
    L::Config: FromParams,
{
    let env = Env::from_env()?;
    let session = zenoh::open(env.zenoh_config()?).await?;
    let mut backoff = Duration::from_secs(1);
    let hello = loop {
        match hello(&session, &env).await {
            Ok(h) => break h,
            Err(e) if e.status == Status::PermissionDenied => {
                return Err(LinkError::new(
                    Status::PermissionDenied,
                    "hello refused: bad link token",
                ))
            }
            Err(e) => {
                warn!("hello failed ({e}); retry in {backoff:?}");
                tokio::time::sleep(backoff).await;
                backoff = (backoff * 2).min(Duration::from_secs(30));
            }
        }
    };
    let cfg = L::Config::from_params(&hello.params)?;
    let mut lcfg = LinkConfig::new(env.site.clone(), env.link.clone());
    lcfg.admin_keys = hello.admin_keys;
    lcfg.limited_keys = hello.limited_keys;
    lcfg.secrets = hello.secrets;
    lcfg.data_dir = env.data_dir.clone();
    let broker = format!("wy/{}/sys/broker", env.site);
    lcfg.republish_on = Some(broker.clone());
    // Watch before the link starts, so no broker restart is missed.
    let watch = session.liveliness().declare_subscriber(&broker).await?;
    let handle = spawn::<L>(session.clone(), lcfg, cfg).await?;
    info!(link = %env.link, driver = L::NAME, "link process up");
    // A broker that comes back may hand out another trust list (ACL rebuild,
    // agent key rotation). Fail closed: while the broker is away the link
    // trusts no key; when it is back, `hello` is retried until it succeeds,
    // and only then are the new keys used. Secrets and params still need a
    // restart of the link.
    let refresh = async {
        while let Ok(s) = watch.recv_async().await {
            match s.kind() {
                zenoh::sample::SampleKind::Delete => {
                    handle.set_trust(Vec::new(), Vec::new());
                    info!("broker gone: trusting no key until a new hello");
                }
                zenoh::sample::SampleKind::Put => {
                    let mut backoff = Duration::from_millis(500);
                    loop {
                        match self::hello(&session, &env).await {
                            Ok(h) => {
                                handle.set_trust(h.admin_keys, h.limited_keys);
                                info!("broker back: trust list refreshed");
                                break;
                            }
                            Err(e) if e.status == Status::PermissionDenied => {
                                return Err(LinkError::new(
                                    Status::PermissionDenied,
                                    "hello refused after broker restart",
                                ));
                            }
                            Err(e) => {
                                warn!("re-hello failed ({e}); retry in {backoff:?}");
                                tokio::time::sleep(backoff).await;
                                backoff = (backoff * 2).min(Duration::from_secs(30));
                            }
                        }
                    }
                }
            }
        }
        std::future::pending::<Result<()>>().await
    };
    let r = tokio::select! {
        _ = signal() => Ok(()),
        r = refresh => r,
    };
    info!("stopping");
    handle.stop().await;
    let _ = session.close().await;
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Bound keys arrive in their own field with their subject; a bound
    /// entry without one, or a free entry with one, is refused.
    #[test]
    fn hello_keeps_key_subjects() {
        let key = Value::Bytes(
            ed25519_dalek::SigningKey::from_bytes(&[7; 32])
                .verifying_key()
                .to_bytes()
                .to_vec(),
        );
        let entry = |subject: Option<&str>| {
            let mut e = vec![
                key.clone(),
                Value::UInt(wyrm_core::Perm::Write.code().into()),
                Value::Array(vec![Value::from("wy/s/downstream/mock")]),
            ];
            e.extend(subject.map(Value::from));
            Value::Array(e)
        };
        let reply = |free: Value, bound: Value| {
            Value::Map(
                [
                    ("limited_keys".to_owned(), Value::Array(vec![free])),
                    ("bound_keys".to_owned(), Value::Array(vec![bound])),
                ]
                .into(),
            )
        };
        let h = parse_hello(reply(entry(None), entry(Some("link:rec")))).unwrap();
        let subjects: Vec<_> = h.limited_keys.iter().map(|k| k.subject.clone()).collect();
        assert_eq!(subjects, [None, Some("link:rec".to_owned())]);
        assert!(parse_hello(reply(entry(None), entry(None))).is_err());
        assert!(parse_hello(reply(entry(Some("link:rec")), entry(Some("link:rec")))).is_err());
    }
}
