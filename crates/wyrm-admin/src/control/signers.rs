//! Requests from upstream sites (ADR 0018): the keys this broker signs
//! requests with, published for the sites below it, and the keys of each
//! upstream site, followed and trusted at the levels this broker allows.
//!
//! Keys travel in two sets, `{write: {<site>: [hex…]}, config: {…}}`: a
//! broker passes on to `config` only its own keys and those of upstream
//! sites it allows `config`, so a site below never trusts at `config` a key
//! that some hop on the way does not.

use super::*;
use crate::registry::{check_signers, MAX_SIGNER_KEYS, MAX_SIGNER_SITES};

/// How often each upstream site is asked for its keys.
const FOLLOW_EVERY: Duration = Duration::from_secs(10);

/// Signing site → keys (hex).
type KeySet = BTreeMap<String, Vec<String>>;

/// What one upstream site publishes.
#[derive(Debug, Default, PartialEq)]
struct Signers {
    write: KeySet,
    config: KeySet,
}

fn parse_key(h: &str) -> Option<VerifyingKey> {
    let raw: [u8; 32] = hex::decode(h).ok()?.try_into().ok()?;
    VerifyingKey::from_bytes(&raw).ok()
}

impl Control {
    /// Our admin keys and gateway key, and those `learned` from our
    /// upstream sites (never under our own site's name). Cut to what a
    /// downstream accepts.
    fn key_set<'a>(&self, learned: impl Iterator<Item = &'a KeySet>) -> KeySet {
        let mut all: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        all.entry(self.cfg.site.clone()).or_default().extend(
            self.cfg
                .admin_keys
                .iter()
                .chain(&self.cfg.control_keys)
                .map(|k| hex::encode(k.to_bytes())),
        );
        for (site, keys) in learned.flatten() {
            if *site != self.cfg.site {
                all.entry(site.clone())
                    .or_default()
                    .extend(keys.iter().cloned());
            }
        }
        all.into_iter()
            .filter(|(_, k)| !k.is_empty())
            .take(MAX_SIGNER_SITES)
            .map(|(s, k)| (s, k.into_iter().take(MAX_SIGNER_KEYS).collect()))
            .collect()
    }

    /// The keys requests to sites below this broker may be signed with:
    /// for `write`, ours and all our upstream sites publish; for `config`,
    /// ours and the `config` keys of upstream sites we allow `config`.
    fn signing_keys(&self) -> Signers {
        let peers = self.peers();
        let reg = self.registry();
        let up = |map: &BTreeMap<String, KeySet>, config_only: bool| -> Vec<KeySet> {
            peers
                .upstream
                .iter()
                .filter(|u| !config_only || peers.config_from.contains(u))
                .filter_map(|u| map.get(u).cloned())
                .collect()
        };
        Signers {
            write: self.key_set(up(&reg.signers, false).iter()),
            config: self.key_set(up(&reg.config_signers, true).iter()),
        }
    }

    /// Upstream keys trusted on our `section`: the `config` keys of upstream
    /// sites with `allow_config` at `config` on every section (as the group
    /// of a DSA upstream connection); the `write` keys of all upstream sites
    /// at `write`, except on `sys`. Never admin keys: each is capped and
    /// scoped to `wy/<site>/<section>`.
    pub fn upstream_trust(&self, section: &str) -> Vec<wyrm_link_sdk::LimitedKey> {
        let peers = self.peers();
        let scope = format!("wy/{}/{section}", self.cfg.site);
        let reg = self.registry();
        let keys = |map: &BTreeMap<String, BTreeMap<String, Vec<String>>>, config: bool| {
            peers
                .upstream
                .iter()
                .filter(|u| !config || peers.config_from.contains(u))
                .filter_map(|u| map.get(u))
                .flat_map(|m| m.values().flatten().cloned())
                .collect::<BTreeSet<String>>()
        };
        let config = keys(&reg.config_signers, true);
        let write = if section == "sys" {
            BTreeSet::new()
        } else {
            &keys(&reg.signers, false) - &config
        };
        let limited = |set: BTreeSet<String>, cap: Perm| {
            set.into_iter()
                .filter_map(|h| parse_key(&h))
                .map(|key| wyrm_link_sdk::LimitedKey {
                    key,
                    cap,
                    scopes: vec![scope.clone()],
                    subject: None,
                })
                .collect::<Vec<_>>()
        };
        let mut out = limited(config, Perm::Config);
        out.extend(limited(write, Perm::Write));
        out
    }
}

fn set_value(set: KeySet) -> Value {
    Value::Map(
        set.into_iter()
            .map(|(s, ks)| (s, Value::Array(ks.into_iter().map(Value::Str).collect())))
            .collect(),
    )
}

fn keys_value(ctl: &Control) -> Value {
    let s = ctl.signing_keys();
    Value::Map(BTreeMap::from([
        ("write".to_owned(), set_value(s.write)),
        ("config".to_owned(), set_value(s.config)),
    ]))
}

/// Answer `wy/<site>/sys/signing_keys/~val` for the sites below: a
/// queryable on that one key, which the ACL lets through to them (the
/// router's `~val` storage and the admin's `sys/**` do not cross).
pub(super) async fn serve_signing_keys(ctl: Arc<Control>, session: Session) {
    let key = acl::signing_keys_key(&ctl.cfg.site);
    let q = match session.declare_queryable(&key).complete(true).await {
        Ok(q) => q,
        Err(e) => {
            warn!("signing keys queryable: {e}");
            return;
        }
    };
    while let Ok(query) = q.recv_async().await {
        let sample = wyrm_core::Sample {
            v: keys_value(&ctl),
            q: Quality::Good,
            t: now_us(),
        };
        match wyrm_core::codec::to_vec(&sample) {
            Ok(bytes) => {
                if let Err(e) = query.reply(&key, bytes).await {
                    debug!("signing keys reply: {e}");
                }
            }
            Err(e) => warn!("signing keys: {e}"),
        }
    }
}

/// `sys/signing_keys`, at each admin start (a key change rebuilds).
pub(super) async fn publish_signing_keys(
    ctx: &LinkCtx,
    ctl: &Control,
) -> wyrm_link_sdk::Result<()> {
    ctx.declare_node(
        "signing_keys",
        NodeMeta::leaf(TypeCode::Map).attr(
            "description",
            "Keys that sign requests to the sites below this broker, by level and site (ADR 0018).",
        ),
    )
    .await?;
    ctx.update("signing_keys", keys_value(ctl), Quality::Good, now_us())
        .await
}

/// Ask every upstream site for its signing keys; a change is stored and
/// rebuilds the broker (every trust list follows), the same keys again
/// change nothing.
pub(super) async fn follow_signers(ctl: Arc<Control>, ctx: LinkCtx) {
    let mut refused: HashMap<String, String> = HashMap::new();
    loop {
        for u in ctl.peers().upstream {
            let Some(got) = ask(&ctx, &u).await else {
                continue;
            };
            if let Err(e) = check_signers(&got.write).and_then(|_| check_signers(&got.config)) {
                if refused.insert(u.clone(), e.clone()).as_ref() != Some(&e) {
                    warn!(site = %u, "upstream signing keys refused: {e}");
                }
                continue;
            }
            refused.remove(&u);
            let reg = ctl.registry();
            let stored = Signers {
                write: reg.signers.get(&u).cloned().unwrap_or_default(),
                config: reg.config_signers.get(&u).cloned().unwrap_or_default(),
            };
            if stored == got {
                continue;
            }
            match ctl.apply(Op::SetSigners {
                upstream: u.clone(),
                keys: got.write,
                config: got.config,
            }) {
                Ok(()) => {
                    ctl.record("system", "signers", &u, Status::Ok, "");
                    info!(site = %u, "upstream signing keys changed: rebuilding");
                    ctl.schedule_reload();
                }
                Err(e) => warn!(site = %u, "upstream signing keys: {e}"),
            }
        }
        tokio::time::sleep(FOLLOW_EVERY).await;
    }
}

fn parse_set(v: Option<Value>) -> Option<KeySet> {
    let Some(Value::Map(m)) = v else {
        return None;
    };
    m.into_iter()
        .map(|(site, ks)| match ks {
            Value::Array(a) => a
                .into_iter()
                .map(|k| match k {
                    Value::Str(s) => Some(s.to_ascii_lowercase()),
                    _ => None,
                })
                .collect::<Option<Vec<_>>>()
                .map(|keys| (site, keys)),
            _ => None,
        })
        .collect()
}

/// The value `wy/<u>/sys/signing_keys` holds; `None` without an answer.
async fn ask(ctx: &LinkCtx, u: &str) -> Option<Signers> {
    // Only the upstream's queryable for that one key is complete: the local
    // `~val` storage, which never holds it, is not asked.
    let replies = ctx
        .client()
        .get(acl::signing_keys_key(u))
        .target(zenoh::query::QueryTarget::AllComplete)
        .timeout(Duration::from_secs(3))
        .await
        .ok()?;
    let reply = replies.recv_async().await.ok()?;
    let s = reply.result().ok()?;
    let sample: wyrm_core::Sample = wyrm_core::codec::from_slice(&s.payload().to_bytes()).ok()?;
    let Value::Map(mut m) = sample.v else {
        return None;
    };
    Some(Signers {
        write: parse_set(m.remove("write"))?,
        config: parse_set(m.remove("config"))?,
    })
}
