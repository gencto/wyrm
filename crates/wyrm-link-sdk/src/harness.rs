//! `TestHarness`: run a driver on an in-memory Zenoh session (peer mode, no
//! listeners, no scouting) and talk to it over the real wire format.
//! Feature `harness`; never enable in production builds.

use crate::ctx::LinkCtx;
use crate::link::Link;
use crate::runtime::{self, LinkConfig, LinkHandle};
use ed25519_dalek::{Signer, SigningKey};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::keyspace::{self, SUFFIX_META};
use wyrm_core::ptok::{Grant, PtokClaims, PTOK_VERSION};
use wyrm_core::{Attachment, NodeMeta, Perm, SetRequest, Value};
use zenoh::query::ConsolidationMode;
use zenoh::Session;

pub const SITE: &str = "test";

/// Fixed test signing key. Trusted only by harness-started links.
pub const TEST_KEY_SEED: [u8; 32] = [7; 32];

/// Zenoh config for an isolated in-process session.
pub fn isolated_config() -> zenoh::Config {
    let mut c = zenoh::Config::default();
    for (k, v) in [
        ("mode", r#""peer""#),
        ("listen/endpoints", "[]"),
        ("connect/endpoints", "[]"),
        ("scouting/multicast/enabled", "false"),
        ("scouting/gossip/enabled", "false"),
    ] {
        c.insert_json5(k, v).expect("static zenoh config");
    }
    c
}

/// One reply as seen by a requester.
#[derive(Debug, Clone)]
pub struct Reply {
    pub key: String,
    pub att: Attachment,
    pub payload: Vec<u8>,
}

impl Reply {
    pub fn value(&self) -> Option<Value> {
        if self.payload.is_empty() {
            None
        } else {
            from_slice(&self.payload).ok()
        }
    }
}

pub struct TestHarness<L: Link> {
    session: Session,
    handle: Option<LinkHandle<L>>,
    key: SigningKey,
    jti: AtomicU64,
}

impl<L: Link> TestHarness<L> {
    /// Start `L` as link `L::NAME` on site [`SITE`].
    pub async fn start(cfg: L::Config) -> Self {
        Self::start_with(cfg, |_| {}).await
    }

    /// Like [`start`](Self::start), with a hook to adjust the [`LinkConfig`].
    pub async fn start_with(cfg: L::Config, tune: impl FnOnce(&mut LinkConfig)) -> Self {
        let session = zenoh::open(isolated_config())
            .await
            .expect("open in-memory zenoh session");
        let key = SigningKey::from_bytes(&TEST_KEY_SEED);
        let mut lcfg = LinkConfig::new(SITE, L::NAME);
        lcfg.admin_keys = vec![key.verifying_key()];
        tune(&mut lcfg);
        let handle = runtime::spawn::<L>(session.clone(), lcfg, cfg)
            .await
            .expect("link start");
        Self {
            session,
            handle: Some(handle),
            key,
            jti: AtomicU64::new(1),
        }
    }

    pub fn ctx(&self) -> &LinkCtx {
        self.handle.as_ref().expect("running").ctx()
    }

    pub fn session(&self) -> &Session {
        &self.session
    }

    pub fn key(&self, path: &str, suffix: &str) -> String {
        self.ctx().key(path, suffix)
    }

    /// Sign arbitrary claims with the test key.
    pub fn sign(&self, claims: &PtokClaims) -> Vec<u8> {
        let mut tok = vec![PTOK_VERSION];
        tok.extend(to_vec(claims).expect("encode claims"));
        let sig = self.key.sign(&tok);
        tok.extend(sig.to_bytes());
        tok
    }

    /// Valid claims (site, 5 min expiry, fresh `jti`, `max = config`).
    pub fn claims(&self, grants: &[(&str, Perm)]) -> PtokClaims {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let mut jti = [0u8; 16];
        jti[..8].copy_from_slice(&self.jti.fetch_add(1, Ordering::Relaxed).to_be_bytes());
        PtokClaims {
            sub: "user:test".into(),
            roles: vec!["test".into()],
            grants: grants
                .iter()
                .map(|(k, p)| Grant {
                    k: (*k).to_owned(),
                    p: *p,
                })
                .collect(),
            max: Perm::Config,
            iat: now,
            exp: now + 300,
            jti,
            site: SITE.into(),
        }
    }

    /// Fresh single-use token with `grants`.
    pub fn mint_ptok(&self, grants: &[(&str, Perm)]) -> Vec<u8> {
        self.sign(&self.claims(grants))
    }

    /// Fresh token granting `p` on the whole link.
    pub fn ptok(&self, p: Perm) -> Vec<u8> {
        let k = self.key("**", "");
        self.mint_ptok(&[(&k, p)])
    }

    /// Raw `get` with `ConsolidationMode::None` (keeps every stream reply).
    pub async fn query(
        &self,
        selector: &str,
        payload: Option<Vec<u8>>,
        att: Attachment,
    ) -> Vec<Reply> {
        let mut get = self
            .session
            .get(selector)
            .consolidation(ConsolidationMode::None)
            .timeout(Duration::from_secs(10))
            .attachment(to_vec(&att).expect("encode attachment"));
        if let Some(p) = payload {
            get = get.payload(p);
        }
        let replies = get.await.expect("get");
        let mut out = Vec::new();
        while let Ok(r) = replies.recv_async().await {
            let Ok(s) = r.result() else { continue };
            out.push(Reply {
                key: s.key_expr().as_str().to_owned(),
                att: s
                    .attachment()
                    .and_then(|a| from_slice(&a.to_bytes()).ok())
                    .unwrap_or_default(),
                payload: s.payload().to_bytes().to_vec(),
            });
        }
        out
    }

    async fn one(&self, selector: &str, payload: Option<Vec<u8>>, att: Attachment) -> Reply {
        let mut r = self.query(selector, payload, att).await;
        assert_eq!(r.len(), 1, "expected exactly one reply to {selector}");
        r.remove(0)
    }

    pub async fn meta(&self, path: &str) -> (Attachment, Option<NodeMeta>) {
        let r = self
            .one(&self.key(path, SUFFIX_META), None, Attachment::default())
            .await;
        let m = (!r.payload.is_empty()).then(|| from_slice(&r.payload).expect("decode ~meta"));
        (r.att, m)
    }

    pub async fn list(&self, path: &str) -> (Attachment, Vec<NodeMeta>) {
        let sel = format!("{}?view=list", self.key(path, SUFFIX_META));
        let r = self.one(&sel, None, Attachment::default()).await;
        let l = if r.payload.is_empty() {
            Vec::new()
        } else {
            from_slice(&r.payload).expect("decode list")
        };
        (r.att, l)
    }

    /// `view=keys` with extra selector params (`"match=type:1&depth=2"`),
    /// expanded back to plain relative paths.
    pub async fn keys(&self, path: &str, params: &str) -> (Attachment, Vec<String>) {
        let mut sel = format!("{}?view=keys", self.key(path, SUFFIX_META));
        if !params.is_empty() {
            sel.push('&');
            sel.push_str(params);
        }
        let r = self.one(&sel, None, Attachment::default()).await;
        let k: Vec<String> = if r.payload.is_empty() {
            Vec::new()
        } else {
            from_slice(&r.payload).expect("decode keys")
        };
        (r.att, keyspace::expand_keys(k))
    }

    pub async fn set(&self, path: &str, v: impl Into<Value>, ptok: Option<Vec<u8>>) -> Attachment {
        let payload = to_vec(&SetRequest { v: v.into() }).expect("encode set");
        let att = Attachment {
            ptok,
            ..Default::default()
        };
        self.one(&self.key(path, "~set"), Some(payload), att)
            .await
            .att
    }

    pub async fn invoke(
        &self,
        path: &str,
        action: &str,
        args: Value,
        ptok: Option<Vec<u8>>,
    ) -> Vec<Reply> {
        let att = Attachment {
            ptok,
            ..Default::default()
        };
        let payload = to_vec(&args).expect("encode args");
        self.query(
            &self.key(path, &format!("~act/{action}")),
            Some(payload),
            att,
        )
        .await
    }

    pub async fn stop(mut self) {
        if let Some(h) = self.handle.take() {
            h.stop().await;
        }
        let _ = self.session.close().await;
    }
}
