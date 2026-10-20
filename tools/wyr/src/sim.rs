//! `wyr sim mock`: the raw-layer mock link (`links/mock`, `Mock`) in this
//! process — `points` numeric points on `depth` folder levels with
//! `fanout` folders each, `hz` updates per point per second.
//!
//! Two modes:
//! * against a broker (default): a client session to `--connect`, serving
//!   `wy/<site>/down/<link>/**` like an external link. The broker's ACL
//!   must let this session declare that queryable (a `dev` profile broker
//!   on loopback does; `prod` does not).
//! * standalone (`--listen <endpoint>`): a peer session listening on the
//!   endpoint, no broker; other `wyr` commands connect with
//!   `--connect <endpoint>`. The link answers `get ~val` itself.
//!
//! `set`/`invoke` need an admin key: the global `--key` (its public half)
//! and/or `--admin-key <hex>`.

use crate::{load_key, Error};
use clap::Subcommand;
use std::path::PathBuf;
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::{LinkConfig, VerifyingKey};

#[derive(Subcommand, Debug)]
pub enum SimCmd {
    /// Mock link: N points × F Hz on a folder tree.
    Mock {
        #[arg(long, default_value_t = 10)]
        points: usize,
        /// Updates per point per second (0 = publish once).
        #[arg(long, default_value_t = 1.0)]
        hz: f64,
        /// Folder levels above the points.
        #[arg(long, default_value_t = 1)]
        depth: usize,
        /// Folders per level.
        #[arg(long, default_value_t = 4)]
        fanout: usize,
        #[arg(long, default_value = "local")]
        site: String,
        #[arg(long, default_value = "mock")]
        link: String,
        /// Admin public key (32 bytes hex) trusted for set/invoke; repeatable.
        #[arg(long = "admin-key")]
        admin_keys: Vec<String>,
        /// Standalone: listen on this endpoint (e.g. `tcp/127.0.0.1:7450`)
        /// as a peer instead of connecting to a broker.
        #[arg(long)]
        listen: Option<String>,
    },
}

/// Zenoh config of a standalone peer listening on `endpoint`.
pub fn standalone_config(endpoint: &str) -> Result<zenoh::Config, Error> {
    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""peer""#)?;
    zc.insert_json5("listen/endpoints", &format!("[\"{endpoint}\"]"))?;
    zc.insert_json5("connect/endpoints", "[]")?;
    zc.insert_json5("scouting/multicast/enabled", "false")?;
    zc.insert_json5("scouting/gossip/enabled", "false")?;
    Ok(zc)
}

pub fn admin_keys(key: &Option<PathBuf>, hex_keys: &[String]) -> Result<Vec<VerifyingKey>, Error> {
    let mut out = Vec::new();
    if let Some(path) = key {
        out.push(load_key(path)?.verifying_key());
    }
    for k in hex_keys {
        let bytes: [u8; 32] = hex::decode(k)?
            .try_into()
            .map_err(|_| "admin key must be 32 bytes hex")?;
        out.push(VerifyingKey::from_bytes(&bytes)?);
    }
    Ok(out)
}

/// Run until Ctrl-C. `broker` is the client config when not standalone.
pub async fn run(
    cmd: SimCmd,
    broker: impl FnOnce() -> Result<zenoh::Config, Error>,
    key: &Option<PathBuf>,
) -> Result<(), Error> {
    let SimCmd::Mock {
        points,
        hz,
        depth,
        fanout,
        site,
        link,
        admin_keys: hex_keys,
        listen,
    } = cmd;
    let keys = admin_keys(key, &hex_keys)?;
    let zc = match &listen {
        Some(ep) => standalone_config(ep)?,
        None => broker()?,
    };
    let session = zenoh::open(zc).await?;
    let mut lcfg = LinkConfig::new(site.clone(), link.clone());
    lcfg.admin_keys = keys;
    if listen.is_some() {
        // No storage without a broker: the link answers `get ~val`.
        lcfg.answer_val = true;
    } else {
        // Router restart: re-publish `~meta` and last values.
        lcfg.republish_on = Some(format!("wy/{site}/sys/broker"));
    }
    if lcfg.admin_keys.is_empty() {
        eprintln!("note: no --key/--admin-key: every set/invoke will be denied");
    }
    let cfg = MockConfig {
        points,
        rate_hz: hz.max(0.0),
        depth,
        fanout,
        writable: true,
    };
    let handle = wyrm_link_sdk::spawn::<Mock>(session.clone(), lcfg, cfg).await?;
    let prefix = handle.ctx().key("", "");
    match &listen {
        Some(ep) => out!(
            "mock link at {prefix} ({points} points × {hz} Hz), standalone on {ep}; \
             try: wyr --connect {ep} tree {prefix}"
        ),
        None => out!("mock link at {prefix} ({points} points × {hz} Hz); Ctrl-C to stop"),
    }
    tokio::signal::ctrl_c().await?;
    handle.stop().await;
    let _ = session.close().await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_and_config() {
        let k = ed25519_dalek::SigningKey::from_bytes(&[3; 32]);
        let hexk = hex::encode(k.verifying_key().to_bytes());
        assert_eq!(admin_keys(&None, &[hexk]).unwrap(), vec![k.verifying_key()]);
        assert!(admin_keys(&None, &["abcd".into()]).is_err());
        assert!(standalone_config("tcp/127.0.0.1:7450").is_ok());
    }
}
