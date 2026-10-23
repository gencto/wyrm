//! Zenoh `access_control` generated from the registry (wiki "Транспорт").
//!
//! Default deny. Directions are the router's: `ingress` = from that session
//! into the router, `egress` = from the router to that session.
//!
//! * link `L` (process/external, CN `L`): everything on `wy/S/downstream/L/**`,
//!   `query`/`reply` on its own `sys/links/L/~act/hello`, liveliness of
//!   `sys/broker` (re-publish after a broker restart), and reading the
//!   profiles under `pub/**` (also allowed to upstream peer sites).
//! * requesters — loopback `tcp`/`unixsock-stream` in `prod`, and operator
//!   CNs: they may ask (query, subscribe, liveliness) and receive (put,
//!   delete, reply, liveliness token) on `wy/S/**`, but never publish, serve
//!   queries or declare tokens outside `**/@adv/sub/**` (advanced
//!   subscriber bookkeeping, `@adv/sub`). A local process therefore cannot
//!   pose as a link or as a link's advanced publisher (`@adv/pub`).
//! * `dev` profile: loopback may do everything (external mock, benchmarks).
//! * In-process sessions (admin, embedded links, flows) never pass the ACL.

use crate::registry::Registry;
use serde_json::{json, Value};

/// Watching a liveliness token (subscriber and history query).
const WATCH: &[&str] = &["declare_liveliness_subscriber", "liveliness_query"];
/// Declaring a liveliness token.
const TOKEN: &[&str] = &["liveliness_token"];

const ALL: &[&str] = &[
    "put",
    "delete",
    "declare_subscriber",
    "query",
    "declare_queryable",
    "reply",
    "liveliness_token",
    "declare_liveliness_subscriber",
    "liveliness_query",
];

fn rule(id: &str, flows: &[&str], messages: &[&str], keys: &[String]) -> Value {
    json!({ "id": id, "permission": "allow", "flows": flows, "messages": messages, "key_exprs": keys })
}

/// ACL rules of a link's grants (it acts as a requester, ADR 0006):
/// `list` → `~meta` queries and liveliness; `read` → also `~val` queries and
/// subscriptions; `write` → any query (`~set`, `~act`) under the path. The
/// answers flow back (egress `put`, `delete`, `reply`, `liveliness_token`).
fn grant_rules(site: &str, id: &str, grants: &[(String, u8)]) -> Vec<(String, Value)> {
    use wyrm_core::Perm;
    let (mut meta, mut val, mut sub, mut all, mut watch, mut back) =
        (vec![], vec![], vec![], vec![], vec![], vec![]);
    for (path, code) in grants {
        let Ok(level) = Perm::try_from(*code) else {
            continue;
        };
        let p = path.replace("{site}", site);
        if level >= Perm::List {
            meta.push(format!("{p}/**/~meta"));
            watch.push(p.clone());
            watch.push(format!("{p}/**"));
            back.push(p.clone());
            back.push(format!("{p}/**"));
        }
        if level >= Perm::Read {
            val.push(format!("{p}/**/~val"));
            sub.push(format!("{p}/**"));
        }
        if level >= Perm::Write {
            all.push(format!("{p}/**"));
        }
    }
    let mut out = Vec::new();
    let mut add = |name: &str, flow: &str, msgs: &[&str], keys: Vec<String>| {
        if !keys.is_empty() {
            let rid = format!("grant-{id}-{name}");
            out.push((rid.clone(), rule(&rid, &[flow], msgs, &keys)));
        }
    };
    let queries: Vec<String> = meta.into_iter().chain(val).chain(all).collect();
    add("query", "ingress", &["query"], queries);
    add(
        "watch",
        "ingress",
        &["declare_liveliness_subscriber", "liveliness_query"],
        watch,
    );
    add("sub", "ingress", &["declare_subscriber"], sub);
    add(
        "back",
        "egress",
        &["put", "delete", "reply", "liveliness_token"],
        back,
    );
    out
}

/// Other brokers this one talks to (wiki "Два брокери"), by site name.
/// Broker certificates carry CN `broker:<site>`; brokers talk over QUIC,
/// links and operators over TLS, so a peer CA cannot mint a link identity
/// that matches a link rule.
#[derive(Debug, Clone, Default)]
pub struct Peers {
    /// Sites this broker connects to; they may only read our `downstream/**`,
    /// `dataflows/**`, `sys/**`, `upstream/**` and `storage/**`, and those of the sites we reach
    /// (subscribe, liveliness, queries on `~meta|~val`, and `~def|~state`
    /// under `downstream`/`dataflows`; no `~set`/`~act`).
    pub upstream: Vec<String>,
    /// Sites that connect to this broker; they serve their own `wy/<site>/**`.
    pub downstream: Vec<String>,
    /// Sites a downstream site relays from further down (a chain
    /// `plant → edge → here`: `edge → [plant]`); it may serve their keys too.
    pub via: std::collections::BTreeMap<String, Vec<String>>,
    /// A QUIC enrollment listener without client certificates is open: any
    /// QUIC session may ask `wy/<site>/sys/~act/enroll` and get its reply,
    /// nothing else (ADR 0015).
    pub enroll: bool,
}

impl Peers {
    /// A downstream site and the sites it relays.
    pub fn sites_through(&self, d: &str) -> Vec<String> {
        let mut out = vec![d.to_owned()];
        out.extend(self.via.get(d).into_iter().flatten().cloned());
        out
    }

    /// Every site below this broker: the downstream sites and those they
    /// relay.
    pub fn reachable(&self) -> Vec<String> {
        self.downstream
            .iter()
            .flat_map(|d| self.sites_through(d))
            .collect()
    }
}

/// Sections of a site an upstream site reads, with the suffixes it may query.
const UP_READ: [(&str, &[&str]); 5] = [
    ("downstream", &["~meta", "~val", "~def", "~state"]),
    ("dataflows", &["~meta", "~val", "~def", "~state"]),
    ("sys", &["~meta", "~val"]),
    ("upstream", &["~meta", "~val"]),
    ("storage", &["~meta", "~val"]),
];

/// The `access_control` section for the router config.
pub fn access_control(site: &str, reg: &Registry, operators: &[String], dev: bool) -> Value {
    access_control_with_peers(site, reg, operators, dev, &Peers::default())
}

/// [`access_control`] plus router-to-router rules for `peers`.
pub fn access_control_with_peers(
    site: &str,
    reg: &Registry,
    operators: &[String],
    dev: bool,
    peers: &Peers,
) -> Value {
    let all_site = vec![format!("wy/{site}/**")];
    // Requesters here may also ask downstream sites (their brokers serve
    // `wy/<d>/**` over the peer link; their ACL keeps us read-only).
    let mut requester_keys = all_site.clone();
    let mut adv_keys = vec![format!("wy/{site}/**/@adv/sub/**")];
    for d in peers.reachable() {
        requester_keys.push(format!("wy/{d}/**"));
        adv_keys.push(format!("wy/{d}/**/@adv/sub/**"));
    }
    let mut rules = vec![
        rule(
            "requester-in",
            &["ingress"],
            &[
                "query",
                "declare_subscriber",
                "declare_liveliness_subscriber",
                "liveliness_query",
            ],
            &requester_keys,
        ),
        rule(
            "requester-out",
            &["egress"],
            &["put", "delete", "reply", "liveliness_token"],
            &requester_keys,
        ),
        rule("requester-adv", &["ingress", "egress"], ALL, &adv_keys),
        // Profiles (`pub/**`): links and peer sites read and follow them;
        // only the admin (in-process, outside the ACL) writes them.
        rule(
            "pub-in",
            &["ingress"],
            &["query", "declare_subscriber"],
            &[format!("wy/{site}/pub/**")],
        ),
        rule(
            "pub-out",
            &["egress"],
            &["reply", "put", "delete"],
            &[format!("wy/{site}/pub/**")],
        ),
        // Links watch the broker token; only the broker declares it.
        rule(
            "broker-watch",
            &["ingress"],
            WATCH,
            &[format!("wy/{site}/sys/broker")],
        ),
        rule(
            "broker-token",
            &["egress"],
            TOKEN,
            &[format!("wy/{site}/sys/broker")],
        ),
    ];
    let mut subjects = vec![json!({ "id": "local", "link_protocols": ["tcp", "unixsock-stream"] })];
    let requester_rules = json!(["requester-in", "requester-out", "requester-adv"]);
    let mut policies = Vec::new();
    if dev {
        rules.push(rule("local-all", &["ingress", "egress"], ALL, &all_site));
        policies.push(json!({ "rules": ["local-all"], "subjects": ["local"] }));
    } else {
        policies.push(json!({ "rules": requester_rules, "subjects": ["local"] }));
    }
    if !operators.is_empty() {
        subjects.push(
            json!({ "id": "operators", "cert_common_names": operators, "link_protocols": ["tls"] }),
        );
        policies.push(json!({ "rules": requester_rules, "subjects": ["operators"] }));
    }
    // A link id equal to a downstream site would overlap `downstream/<d>`, the
    // broker node of that site (registry and config refuse it; this is the
    // last line).
    for def in reg
        .links
        .values()
        .filter(|d| d.mode.is_remote() && !peers.downstream.contains(&d.id))
    {
        let id = &def.id;
        rules.push(rule(
            &format!("link-{id}"),
            &["ingress", "egress"],
            ALL,
            &[format!("wy/{site}/downstream/{id}/**")],
        ));
        rules.push(rule(
            &format!("hello-{id}"),
            &["ingress", "egress"],
            &["query", "reply"],
            &[format!("wy/{site}/sys/links/{id}/~act/hello")],
        ));
        rules.push(rule(
            &format!("audit-{id}"),
            &["ingress"],
            &["put"],
            &[format!("wy/{site}/sys/audit/{id}")],
        ));
        // The broker's attributes for its nodes (ADR 0016): read, never put.
        let overlays = vec![format!("wy/{site}/sys/overlays/{id}/~val")];
        rules.push(rule(
            &format!("overlays-{id}-in"),
            &["ingress"],
            &["query", "declare_subscriber"],
            &overlays,
        ));
        rules.push(rule(
            &format!("overlays-{id}-out"),
            &["egress"],
            &["reply", "put"],
            &overlays,
        ));
        let mut link_rules = vec![
            json!(format!("link-{id}")),
            json!(format!("hello-{id}")),
            json!(format!("audit-{id}")),
            json!(format!("overlays-{id}-in")),
            json!(format!("overlays-{id}-out")),
            json!("broker-watch"),
            json!("broker-token"),
            json!("pub-in"),
            json!("pub-out"),
        ];
        // As a requester (link grants): read and command other branches.
        for (rid, r) in grant_rules(site, id, &def.grants) {
            rules.push(r);
            link_rules.push(json!(rid));
        }
        // TLS only: the main listener trusts our own CA alone; peer CAs are
        // trusted only on the QUIC broker listener.
        subjects.push(json!({ "id": format!("cn-{id}"), "cert_common_names": [id], "link_protocols": ["tls"] }));
        policies.push(json!({
            "rules": link_rules,
            "subjects": [format!("cn-{id}")],
        }));
    }
    if !peers.upstream.is_empty() {
        // This site and every site below it, as a DSA upstream sees its
        // downstream broker (owner decision 2026-10-22: sys too, read only).
        let sites: Vec<String> = std::iter::once(site.to_owned())
            .chain(peers.reachable())
            .collect();
        // Whole sections: declarations and liveliness (they carry key names).
        let readable: Vec<String> = sites
            .iter()
            .flat_map(|s| UP_READ.iter().map(move |(t, _)| format!("wy/{s}/{t}/**")))
            .collect();
        // Data: `downstream` and `dataflows` whole; the others only their values
        // and metadata, so nothing else published under `sys` (the audit
        // records of `sys/audit/<link>`) leaves for the upstream.
        let data: Vec<String> = sites
            .iter()
            .flat_map(|s| {
                UP_READ.iter().flat_map(move |(t, sfx)| {
                    if *t == "downstream" || *t == "dataflows" {
                        vec![format!("wy/{s}/{t}/**")]
                    } else {
                        sfx.iter().map(|x| format!("wy/{s}/{t}/**/{x}")).collect()
                    }
                })
            })
            .collect();
        rules.push(rule(
            "upstream-in",
            &["ingress"],
            &["declare_liveliness_subscriber", "liveliness_query"],
            &readable,
        ));
        rules.push(rule(
            "upstream-sub",
            &["ingress"],
            &["declare_subscriber"],
            &data,
        ));
        // Read-only: queries only on read suffixes, never `~set`/`~act`.
        let read_suffixes: Vec<String> = sites
            .iter()
            .flat_map(|s| {
                UP_READ
                    .iter()
                    .flat_map(move |(t, sfx)| sfx.iter().map(move |x| format!("wy/{s}/{t}/**/{x}")))
            })
            .collect();
        rules.push(rule(
            "upstream-query",
            &["ingress"],
            &["query"],
            &read_suffixes,
        ));
        rules.push(rule(
            "upstream-out",
            &["egress"],
            &[
                "liveliness_token",
                "declare_queryable",
                "declare_subscriber",
            ],
            &readable,
        ));
        rules.push(rule(
            "upstream-data",
            &["egress"],
            &["put", "delete", "reply"],
            &data,
        ));
        let cns: Vec<String> = peers
            .upstream
            .iter()
            .map(|u| format!("broker:{u}"))
            .collect();
        subjects.push(
            json!({ "id": "upstream", "cert_common_names": cns, "link_protocols": ["quic"] }),
        );
        policies
            .push(json!({ "rules": ["upstream-in", "upstream-sub", "upstream-query", "upstream-out", "upstream-data", "pub-in", "pub-out"], "subjects": ["upstream"] }));
        // Presence (`upstream/<u>/connected` here, `downstream/<site>/connected` there):
        // per upstream site, so one site cannot declare another's token,
        // and a peer never declares a token on our own key.
        let own = format!("wy/{site}/sys/broker");
        for u in &peers.upstream {
            let theirs = format!("wy/{u}/sys/broker");
            let ids = [
                format!("presence-{u}-token-in"),
                format!("presence-{u}-watch-in"),
                format!("presence-{u}-token-out"),
                format!("presence-{u}-watch-out"),
            ];
            rules.push(rule(
                &ids[0],
                &["ingress"],
                TOKEN,
                std::slice::from_ref(&theirs),
            ));
            rules.push(rule(
                &ids[1],
                &["ingress"],
                WATCH,
                std::slice::from_ref(&own),
            ));
            rules.push(rule(
                &ids[2],
                &["egress"],
                TOKEN,
                std::slice::from_ref(&own),
            ));
            rules.push(rule(&ids[3], &["egress"], WATCH, &[theirs]));
            subjects.push(json!({
                "id": format!("upstream-{u}"),
                "cert_common_names": [format!("broker:{u}")],
                "link_protocols": ["quic"],
            }));
            policies.push(json!({ "rules": ids, "subjects": [format!("upstream-{u}")] }));
        }
    }
    for d in &peers.downstream {
        // its own keys and those of the sites it relays
        let keys: Vec<String> = peers
            .sites_through(d)
            .iter()
            .map(|s| format!("wy/{s}/**"))
            .collect();
        rules.push(rule(
            &format!("site-{d}"),
            &["ingress", "egress"],
            ALL,
            &keys,
        ));
        subjects.push(json!({
            "id": format!("broker-{d}"),
            "cert_common_names": [format!("broker:{d}")],
            "link_protocols": ["quic"],
        }));
        // The downstream site watches our broker token (its `upstream/<site>`);
        // it may not declare one on our key. Its own token is in `site-d`.
        let own = format!("wy/{site}/sys/broker");
        rules.push(rule(
            &format!("presence-{d}-watch-in"),
            &["ingress"],
            WATCH,
            std::slice::from_ref(&own),
        ));
        rules.push(rule(
            &format!("presence-{d}-token-out"),
            &["egress"],
            TOKEN,
            &[own],
        ));
        policies.push(json!({
            "rules": [format!("site-{d}"), format!("presence-{d}-watch-in"), format!("presence-{d}-token-out")],
            "subjects": [format!("broker-{d}")],
        }));
    }
    if peers.enroll {
        // No CN in the subject: it matches sessions without a certificate
        // (and every QUIC broker, which gains nothing it lacks).
        let key = vec![format!("wy/{site}/sys/~act/enroll")];
        rules.push(rule("enroll-in", &["ingress"], &["query"], &key));
        rules.push(rule("enroll-out", &["egress"], &["reply"], &key));
        subjects.push(json!({ "id": "enroll", "link_protocols": ["quic"] }));
        policies.push(json!({ "rules": ["enroll-in", "enroll-out"], "subjects": ["enroll"] }));
    }
    json!({
        "enabled": true,
        "default_permission": "deny",
        "rules": rules,
        "subjects": subjects,
        "policies": policies,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::{LinkDef, Mode, Origin};

    fn def(id: &str, mode: Mode) -> LinkDef {
        LinkDef {
            id: id.into(),
            driver: "modbus".into(),
            mode,
            params: vec![0xa0],
            token_hash: "h".into(),
            rev: 1,
            origin: Origin::Runtime,
            created: 0,
            display: None,
            granted: None,
            log_level: None,
            grants: Vec::new(),
        }
    }

    #[test]
    fn link_grants_open_other_branches() {
        use wyrm_core::Perm;
        let mut reg = Registry::default();
        let mut d = def("rec", Mode::External);
        d.grants = vec![
            ("wy/{site}/downstream/mock".into(), Perm::Read.code()),
            ("wy/{site}/downstream/plc1".into(), Perm::Write.code()),
            ("wy/{site}/dataflows".into(), Perm::List.code()),
        ];
        reg.links.insert("rec".into(), d);
        let acl = access_control("s", &reg, &[], false);
        let rule = |id: &str| {
            acl["rules"]
                .as_array()
                .unwrap()
                .iter()
                .find(|r| r["id"] == id)
                .cloned()
                .unwrap_or_else(|| panic!("rule {id}"))
        };
        let keys = |id: &str| -> Vec<String> {
            rule(id)["key_exprs"]
                .as_array()
                .unwrap()
                .iter()
                .map(|k| k.as_str().unwrap().to_owned())
                .collect()
        };
        let q = keys("grant-rec-query");
        assert!(q.contains(&"wy/s/downstream/mock/**/~val".into()));
        assert!(q.contains(&"wy/s/dataflows/**/~meta".into()));
        assert!(
            q.contains(&"wy/s/downstream/plc1/**".into()),
            "write: ~set, ~act"
        );
        assert!(
            !q.contains(&"wy/s/downstream/mock/**".into()),
            "read: no ~set/~act"
        );
        assert!(
            !q.iter().any(|k| k.starts_with("wy/s/dataflows/**/~val")),
            "list: no values"
        );
        assert!(keys("grant-rec-sub")
            .iter()
            .all(|k| !k.starts_with("wy/s/dataflows")));
        assert!(q
            .iter()
            .chain(&keys("grant-rec-back"))
            .all(|k| !k.contains("/sys")));
        let policy = acl["policies"]
            .as_array()
            .unwrap()
            .iter()
            .find(|p| p["subjects"][0] == "cn-rec")
            .unwrap();
        assert!(policy["rules"]
            .as_array()
            .unwrap()
            .contains(&json!("grant-rec-query")));
        // a link without grants gets none of these rules
        assert!(!acl.to_string().contains("grant-mock"));
    }

    #[test]
    fn peer_brokers() {
        let peers = Peers {
            upstream: vec!["cloud".into()],
            downstream: vec!["plant-b".into()],
            ..Default::default()
        };
        let acl = access_control_with_peers("plant-a", &Registry::default(), &[], false, &peers);
        let text = acl.to_string();
        assert!(text.contains(r#""cert_common_names":["broker:cloud"]"#));
        assert!(text.contains("wy/plant-a/downstream/**"));
        assert!(text.contains(r#""key_exprs":["wy/plant-b/**"]"#));
        // the upstream reads sys and up too, never ~set/~act anywhere
        let keys = |id: &str| -> Vec<String> {
            acl["rules"]
                .as_array()
                .unwrap()
                .iter()
                .find(|r| r["id"] == id)
                .map(|r| {
                    r["key_exprs"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|k| k.as_str().unwrap().to_owned())
                        .collect()
                })
                .unwrap_or_default()
        };
        let q = keys("upstream-query");
        assert!(q.contains(&"wy/plant-a/sys/**/~meta".to_owned()));
        assert!(q.contains(&"wy/plant-a/upstream/**/~val".to_owned()));
        assert!(
            q.contains(&"wy/plant-b/sys/**/~meta".to_owned()),
            "and below"
        );
        assert!(q.iter().all(|k| !k.contains("~set") && !k.contains("~act")));
        assert!(!q.iter().any(|k| k.starts_with("wy/plant-a/sys/**/~def")));
        // data leaving for the upstream: sys only as ~val and ~meta (no
        // audit records of sys/audit/<link>); down whole
        for id in ["upstream-data", "upstream-sub"] {
            let k = keys(id);
            assert!(k.contains(&"wy/plant-a/downstream/**".to_owned()), "{id}");
            assert!(k.contains(&"wy/plant-a/sys/**/~val".to_owned()), "{id}");
            assert!(!k.contains(&"wy/plant-a/sys/**".to_owned()), "{id}: {k:?}");
        }
        let mut c = zenoh::Config::default();
        c.insert_json5("access_control", &text).unwrap();
    }

    /// A peer never declares a liveliness token on our `sys/broker` key
    /// (it would fake our presence); an upstream declares only its own.
    /// The enrollment listener (ADR 0015): any QUIC session, certificate or
    /// not, may query one key and get its reply; nothing else.
    #[test]
    fn enrollment_reaches_one_key() {
        let peers = Peers {
            enroll: true,
            ..Default::default()
        };
        let acl = access_control_with_peers("hub", &Registry::default(), &[], false, &peers);
        let by_id = |list: &str, id: &str| {
            acl[list]
                .as_array()
                .unwrap()
                .iter()
                .find(|r| r["id"] == id)
                .cloned()
                .unwrap()
        };
        let subject = by_id("subjects", "enroll");
        assert!(subject.get("cert_common_names").is_none());
        assert_eq!(subject["link_protocols"], serde_json::json!(["quic"]));
        for (id, flow, msg) in [
            ("enroll-in", "ingress", "query"),
            ("enroll-out", "egress", "reply"),
        ] {
            let r = by_id("rules", id);
            assert_eq!(
                r["key_exprs"],
                serde_json::json!(["wy/hub/sys/~act/enroll"])
            );
            assert_eq!(r["flows"], serde_json::json!([flow]));
            assert_eq!(r["messages"], serde_json::json!([msg]));
        }
        let off =
            access_control_with_peers("hub", &Registry::default(), &[], false, &Peers::default());
        assert!(!off.to_string().contains("enroll"));
    }

    #[test]
    fn presence_tokens_by_direction() {
        let peers = Peers {
            upstream: vec!["cloud".into(), "hq".into()],
            downstream: vec!["plant-b".into()],
            ..Default::default()
        };
        let mut reg = Registry::default();
        reg.links
            .insert("plant-b".into(), def("plant-b", Mode::External));
        let acl = access_control_with_peers("plant-a", &reg, &[], false, &peers);
        let rules = acl["rules"].as_array().unwrap();
        let own = "wy/plant-a/sys/broker";
        for r in rules {
            let keys: Vec<&str> = r["key_exprs"]
                .as_array()
                .unwrap()
                .iter()
                .map(|k| k.as_str().unwrap())
                .collect();
            let token = r["messages"]
                .as_array()
                .unwrap()
                .iter()
                .any(|m| m == "liveliness_token");
            let ingress = r["flows"]
                .as_array()
                .unwrap()
                .iter()
                .any(|f| f == "ingress");
            if token && ingress {
                assert!(
                    !keys.contains(&own),
                    "token on our key accepted: {}",
                    r["id"]
                );
            }
            if r["id"] == "presence-cloud-token-in" {
                assert_eq!(keys, ["wy/cloud/sys/broker"]);
            }
        }
        // a link with a downstream site's name gets no rule over downstream/<d>
        assert!(!acl.to_string().contains("wy/plant-a/downstream/plant-b/**"));
        let mut c = zenoh::Config::default();
        c.insert_json5("access_control", &acl.to_string()).unwrap();
    }

    #[test]
    fn rules_follow_the_registry() {
        let mut reg = Registry::default();
        reg.links.insert("plc1".into(), def("plc1", Mode::Process));
        reg.links.insert("emb".into(), def("emb", Mode::Embedded));
        let acl = access_control("s", &reg, &["ops".into()], false);
        let text = acl.to_string();
        assert!(text.contains("wy/s/downstream/plc1/**"));
        assert!(text.contains("wy/s/sys/links/plc1/~act/hello"));
        assert!(
            !text.contains("downstream/emb"),
            "embedded links need no rule"
        );
        assert!(!text.contains("local-all"));
        assert!(text.contains(r#""cert_common_names":["ops"]"#));
        // the result is a valid zenoh config section
        let mut c = zenoh::Config::default();
        c.insert_json5("access_control", &text).unwrap();
        let dev = access_control("s", &reg, &[], true).to_string();
        assert!(dev.contains("local-all"));
        c.insert_json5("access_control", &dev).unwrap();
    }

    /// A chain `cell → plant-b → plant-a → cloud`: plant-a lets plant-b
    /// serve the site it relays and lets cloud read both; nothing else.
    #[test]
    fn chains_of_brokers() {
        let peers = Peers {
            upstream: vec!["cloud".into()],
            downstream: vec!["plant-b".into()],
            via: [("plant-b".to_owned(), vec!["cell".to_owned()])].into(),
            ..Default::default()
        };
        assert_eq!(peers.reachable(), ["plant-b", "cell"]);
        let acl = access_control_with_peers("plant-a", &Registry::default(), &[], false, &peers);
        let rule = |id: &str| {
            acl["rules"]
                .as_array()
                .unwrap()
                .iter()
                .find(|r| r["id"] == id)
                .cloned()
                .unwrap()
        };
        assert_eq!(
            rule("site-plant-b")["key_exprs"],
            serde_json::json!(["wy/plant-b/**", "wy/cell/**"])
        );
        let q = rule("upstream-query").to_string();
        assert!(q.contains("wy/cell/downstream/**/~val") && q.contains("wy/cell/sys/**/~meta"));
        assert!(rule("requester-in").to_string().contains("wy/cell/**"));
        let mut c = zenoh::Config::default();
        c.insert_json5("access_control", &acl.to_string()).unwrap();
    }
}
