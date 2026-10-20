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
        Ok(Self {
            site,
            link,
            endpoint,
            tls,
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
    /// `[[key, perm code, [scope, ...]], ...]`: keys trusted only up to a
    /// permission and only under their scopes.
    pub limited_keys: Vec<crate::auth::LimitedKey>,
    pub secrets: crate::SecretStore,
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
    let limited_keys = match m.remove("limited_keys") {
        Some(Value::Array(pairs)) => pairs
            .iter()
            .map(|p| match p {
                Value::Array(kv) if kv.len() == 3 => {
                    let cap = kv[1]
                        .as_f64()
                        .and_then(|c| u8::try_from(c as u64).ok())
                        .and_then(|c| wyrm_core::Perm::try_from(c).ok())
                        .ok_or_else(|| LinkError::new(Status::InvalidMessage, "bad key cap"))?;
                    let Value::Array(sc) = &kv[2] else {
                        return Err(LinkError::new(Status::InvalidMessage, "bad key scopes"));
                    };
                    let scopes = sc
                        .iter()
                        .map(|s| match s {
                            Value::Str(s) => Ok(s.clone()),
                            _ => Err(LinkError::new(Status::InvalidMessage, "bad key scope")),
                        })
                        .collect::<Result<_>>()?;
                    Ok(crate::auth::LimitedKey {
                        key: key_of(&kv[0])?,
                        cap,
                        scopes,
                    })
                }
                _ => Err(LinkError::new(Status::InvalidMessage, "bad limited key")),
            })
            .collect::<Result<_>>()?,
        _ => Vec::new(),
    };
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

/// Run `L` as a supervised process until SIGTERM/SIGINT.
pub async fn run<L: Link>() -> Result<()>
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
    let broker = format!("wy/{}/sys/broker", env.site);
    // Watch before the link starts, so no broker restart is missed.
    let watch = session.liveliness().declare_subscriber(&broker).await?;
    let handle = spawn::<L>(session.clone(), lcfg, cfg).await?;
    info!(link = %env.link, driver = L::NAME, "link process up");
    // A broker that comes back may hand out another trust list (ACL rebuild,
    // agent key rotation): exit so the supervisor restarts us with a fresh
    // `hello` instead of verifying tokens against stale keys.
    let restarted = async {
        let mut gone = false;
        while let Ok(s) = watch.recv_async().await {
            match s.kind() {
                zenoh::sample::SampleKind::Delete => gone = true,
                zenoh::sample::SampleKind::Put if gone => return,
                zenoh::sample::SampleKind::Put => {}
            }
        }
        std::future::pending::<()>().await
    };
    let r = tokio::select! {
        _ = signal() => {
            info!("stopping");
            Ok(())
        }
        _ = restarted => {
            info!("broker restarted: exiting for a fresh hello");
            Err(LinkError::new(Status::Disconnected, "broker restarted; restart for a fresh hello"))
        }
    };
    handle.stop().await;
    let _ = session.close().await;
    r
}
