//! What this site lays on other sites' points (ADR 0020): the admin
//! publishes the downstream points its historian records at
//! `wy/<site>/sys/overlays/.sites`; the gateway merges their `attr.history`
//! into `meta`, `children` and `list`, as a DSA broker does with the
//! override attributes of its remote nodes.

use std::collections::BTreeMap;
use std::sync::Arc;
use tokio::sync::watch;
use wyrm_client::{ValEvent, WyrmClient};
use wyrm_core::{NodeMeta, Value};

/// Point key → the watch keys that record it.
pub(crate) type Sites = BTreeMap<String, Vec<String>>;

/// `{<point key>: {"history": [<watch key>…]}}`; anything else is skipped.
pub(crate) fn parse(v: &Value) -> Sites {
    let Value::Map(m) = v else {
        return Sites::new();
    };
    m.iter()
        .filter_map(|(point, attrs)| {
            let Value::Map(a) = attrs else { return None };
            let Some(Value::Array(keys)) = a.get("history") else {
                return None;
            };
            let keys: Vec<String> = keys
                .iter()
                .filter_map(|k| match k {
                    Value::Str(s) => Some(s.clone()),
                    _ => None,
                })
                .collect();
            (!keys.is_empty()).then(|| (point.clone(), keys))
        })
        .collect()
}

/// `m` of `key` with this site's stores added to `attr.history` (a union)
/// and `has_history` set; unchanged when this site records nothing there.
pub(crate) fn lay(sites: &Sites, key: &str, m: &mut NodeMeta) {
    let Some(stores) = sites.get(key) else { return };
    let attr = m.attr.get_or_insert_with(BTreeMap::new);
    let mut all: Vec<Value> = match attr.remove("history") {
        Some(Value::Array(a)) => a,
        _ => Vec::new(),
    };
    for s in stores {
        let s = Value::Str(s.clone());
        if !all.contains(&s) {
            all.push(s);
        }
    }
    attr.insert("history".into(), Value::Array(all));
    m.has_history = Some(true);
}

/// The point a watch key of this map records.
pub(crate) fn point_of<'a>(sites: &'a Sites, watch: &str) -> Option<&'a str> {
    sites
        .iter()
        .find(|(_, stores)| stores.iter().any(|s| s == watch))
        .map(|(p, _)| p.as_str())
}

/// Keep `tx` equal to `wy/<site>/sys/overlays/.sites` while `session`
/// lives (the stored value first, then changes).
pub(crate) async fn follow(
    session: zenoh::Session,
    site: String,
    tx: Arc<watch::Sender<Arc<Sites>>>,
) {
    let key = format!("wy/{site}/sys/overlays/.sites");
    let c = WyrmClient::new(session);
    let mut s = match c.subscribe(&key).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!(%key, "gateway overlays: {e}");
            return;
        }
    };
    while let Some(ev) = s.next().await {
        let sites = match ev {
            ValEvent::Sample { sample, .. } => parse(&sample.v),
            ValEvent::Removed(_) => Sites::new(),
        };
        tx.send_if_modified(|cur| {
            let changed = **cur != sites;
            if changed {
                *cur = Arc::new(sites);
            }
            changed
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hist(keys: &[&str]) -> Value {
        Value::Map(
            [(
                "history".to_owned(),
                Value::Array(keys.iter().map(|k| Value::from(*k)).collect()),
            )]
            .into(),
        )
    }

    #[test]
    fn parse_lay_and_point() {
        let v = Value::Map(
            [
                (
                    "wy/e/downstream/l/p".to_owned(),
                    hist(&["wy/c/sys/history/g/w1"]),
                ),
                ("wy/e/downstream/l/q".to_owned(), Value::UInt(3)),
            ]
            .into(),
        );
        let sites = parse(&v);
        assert_eq!(sites.len(), 1);
        // the link's own store stays; ours joins it
        let mut m = NodeMeta::number().attr("history", Value::Array(vec![Value::from("s1")]));
        lay(&sites, "wy/e/downstream/l/p", &mut m);
        assert_eq!(
            m.attr.as_ref().unwrap()["history"],
            Value::Array(vec![
                Value::from("s1"),
                Value::from("wy/c/sys/history/g/w1")
            ])
        );
        assert_eq!(m.has_history, Some(true));
        let mut other = NodeMeta::number();
        lay(&sites, "wy/e/downstream/l/q", &mut other);
        assert_eq!(other, NodeMeta::number());
        assert_eq!(
            point_of(&sites, "wy/c/sys/history/g/w1"),
            Some("wy/e/downstream/l/p")
        );
        assert_eq!(point_of(&sites, "wy/c/sys/history/g/w2"), None);
    }
}
