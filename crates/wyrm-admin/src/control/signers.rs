//! Requests from upstream sites (ADR 0018): the keys this broker signs
//! requests with, published for the sites below it, and the keys of each
//! upstream site, followed and trusted at the levels this broker allows.

use super::*;
use crate::registry::{check_signers, MAX_SIGNER_KEYS, MAX_SIGNER_SITES};

/// How often each upstream site is asked for its keys.
const FOLLOW_EVERY: Duration = Duration::from_secs(10);

fn parse_key(h: &str) -> Option<VerifyingKey> {
    let raw: [u8; 32] = hex::decode(h).ok()?.try_into().ok()?;
    VerifyingKey::from_bytes(&raw).ok()
}

impl Control {
    /// The keys requests to sites below this broker may be signed with, by
    /// site: our admin keys and gateway key, and those our upstream sites
    /// publish (the sites above). Cut to what a downstream accepts.
    pub(crate) fn signing_keys(&self) -> BTreeMap<String, Vec<String>> {
        let mut all: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        all.entry(self.cfg.site.clone()).or_default().extend(
            self.cfg
                .admin_keys
                .iter()
                .chain(&self.cfg.control_keys)
                .map(|k| hex::encode(k.to_bytes())),
        );
        let reg = self.registry();
        for u in self.peers().upstream {
            for (site, keys) in reg.signers.get(&u).into_iter().flatten() {
                if *site != self.cfg.site {
                    all.entry(site.clone())
                        .or_default()
                        .extend(keys.iter().cloned());
                }
            }
        }
        all.into_iter()
            .filter(|(_, k)| !k.is_empty())
            .take(MAX_SIGNER_SITES)
            .map(|(s, k)| (s, k.into_iter().take(MAX_SIGNER_KEYS).collect()))
            .collect()
    }

    /// Upstream keys trusted on our `section`: `downstream`, `dataflows` and
    /// `storage` at `write`; `sys` at `config`, from upstream sites with
    /// `allow_config` only. Never admin keys: each is capped and scoped to
    /// `wy/<site>/<section>`.
    pub fn upstream_trust(&self, section: &str) -> Vec<wyrm_link_sdk::LimitedKey> {
        let peers = self.peers();
        let sys = section == "sys";
        let cap = if sys { Perm::Config } else { Perm::Write };
        let scope = format!("wy/{}/{section}", self.cfg.site);
        let reg = self.registry();
        let keys: BTreeSet<String> = peers
            .upstream
            .iter()
            .filter(|u| !sys || peers.config_from.contains(u))
            .filter_map(|u| reg.signers.get(u))
            .flat_map(|m| m.values().flatten().cloned())
            .collect();
        keys.iter()
            .filter_map(|h| parse_key(h))
            .map(|key| wyrm_link_sdk::LimitedKey {
                key,
                cap,
                scopes: vec![scope.clone()],
                subject: None,
            })
            .collect()
    }
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

fn keys_value(ctl: &Control) -> Value {
    Value::Map(
        ctl.signing_keys()
            .into_iter()
            .map(|(s, ks)| (s, Value::Array(ks.into_iter().map(Value::Str).collect())))
            .collect(),
    )
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
            "Keys that sign requests to the sites below this broker, by site (ADR 0018).",
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
            let Some(keys) = ask(&ctx, &u).await else {
                continue;
            };
            if let Err(e) = check_signers(&keys) {
                if refused.insert(u.clone(), e.clone()).as_ref() != Some(&e) {
                    warn!(site = %u, "upstream signing keys refused: {e}");
                }
                continue;
            }
            refused.remove(&u);
            let stored = ctl.registry().signers.get(&u).cloned().unwrap_or_default();
            if stored == keys {
                continue;
            }
            match ctl.apply(Op::SetSigners {
                upstream: u.clone(),
                keys,
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

/// The value `wy/<u>/sys/signing_keys` holds; `None` without an answer.
async fn ask(ctx: &LinkCtx, u: &str) -> Option<BTreeMap<String, Vec<String>>> {
    let replies = ctx
        .client()
        .get(acl::signing_keys_key(u))
        .timeout(Duration::from_secs(3))
        .await
        .ok()?;
    let reply = replies.recv_async().await.ok()?;
    let s = reply.result().ok()?;
    let sample: wyrm_core::Sample = wyrm_core::codec::from_slice(&s.payload().to_bytes()).ok()?;
    let Value::Map(m) = sample.v else {
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
