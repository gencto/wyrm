//! Zenoh `access_control` generated from the registry (wiki "Транспорт").
//!
//! Default deny. Directions are the router's: `ingress` = from that session
//! into the router, `egress` = from the router to that session.
//!
//! * link `L` (process/external, CN `L`): everything on `wy/S/down/L/**`,
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

/// Other brokers this one talks to (wiki "Два брокери"), by site name.
/// Broker certificates carry CN `broker:<site>`; brokers talk over QUIC,
/// links and operators over TLS, so a peer CA cannot mint a link identity
/// that matches a link rule.
#[derive(Debug, Clone, Default)]
pub struct Peers {
    /// Sites this broker connects to; they may only read our `down/**` and
    /// `flows/**` (subscribe, liveliness, queries on `~meta|~val|~def|~state`;
    /// no `~set`/`~act`).
    pub upstream: Vec<String>,
    /// Sites that connect to this broker; they serve their own `wy/<site>/**`.
    pub downstream: Vec<String>,
}

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
    for d in &peers.downstream {
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
    // A link id equal to a downstream site would overlap `down/<d>`, the
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
            &[format!("wy/{site}/down/{id}/**")],
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
        // TLS only: the main listener trusts our own CA alone; peer CAs are
        // trusted only on the QUIC broker listener.
        subjects.push(json!({ "id": format!("cn-{id}"), "cert_common_names": [id], "link_protocols": ["tls"] }));
        policies.push(json!({
            "rules": [format!("link-{id}"), format!("hello-{id}"), format!("audit-{id}"), "broker-watch", "broker-token", "pub-in", "pub-out"],
            "subjects": [format!("cn-{id}")],
        }));
    }
    if !peers.upstream.is_empty() {
        let readable = vec![format!("wy/{site}/down/**"), format!("wy/{site}/flows/**")];
        rules.push(rule(
            "upstream-in",
            &["ingress"],
            &[
                "declare_subscriber",
                "declare_liveliness_subscriber",
                "liveliness_query",
            ],
            &readable,
        ));
        // Read-only: queries only on read suffixes, never `~set`/`~act`.
        let read_suffixes: Vec<String> = ["down", "flows"]
            .iter()
            .flat_map(|t| {
                ["~meta", "~val", "~def", "~state"]
                    .iter()
                    .map(move |sfx| format!("wy/{site}/{t}/**/{sfx}"))
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
                "put",
                "delete",
                "reply",
                "liveliness_token",
                "declare_queryable",
                "declare_subscriber",
            ],
            &readable,
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
            .push(json!({ "rules": ["upstream-in", "upstream-query", "upstream-out", "pub-in", "pub-out"], "subjects": ["upstream"] }));
        // Presence (`up/<u>/connected` here, `down/<site>/connected` there):
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
        rules.push(rule(
            &format!("site-{d}"),
            &["ingress", "egress"],
            ALL,
            &[format!("wy/{d}/**")],
        ));
        subjects.push(json!({
            "id": format!("broker-{d}"),
            "cert_common_names": [format!("broker:{d}")],
            "link_protocols": ["quic"],
        }));
        // The downstream site watches our broker token (its `up/<site>`);
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
        }
    }

    #[test]
    fn peer_brokers() {
        let peers = Peers {
            upstream: vec!["cloud".into()],
            downstream: vec!["plant-b".into()],
        };
        let acl = access_control_with_peers("plant-a", &Registry::default(), &[], false, &peers);
        let text = acl.to_string();
        assert!(text.contains(r#""cert_common_names":["broker:cloud"]"#));
        assert!(text.contains("wy/plant-a/down/**"));
        assert!(
            !text.contains("wy/plant-a/sys/**"),
            "upstream never reads sys"
        );
        assert!(text.contains(r#""key_exprs":["wy/plant-b/**"]"#));
        let mut c = zenoh::Config::default();
        c.insert_json5("access_control", &text).unwrap();
    }

    /// A peer never declares a liveliness token on our `sys/broker` key
    /// (it would fake our presence); an upstream declares only its own.
    #[test]
    fn presence_tokens_by_direction() {
        let peers = Peers {
            upstream: vec!["cloud".into(), "hq".into()],
            downstream: vec!["plant-b".into()],
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
        // a link with a downstream site's name gets no rule over down/<d>
        assert!(!acl.to_string().contains("wy/plant-a/down/plant-b/**"));
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
        assert!(text.contains("wy/s/down/plc1/**"));
        assert!(text.contains("wy/s/sys/links/plc1/~act/hello"));
        assert!(!text.contains("down/emb"), "embedded links need no rule");
        assert!(!text.contains("local-all"));
        assert!(text.contains(r#""cert_common_names":["ops"]"#));
        // the result is a valid zenoh config section
        let mut c = zenoh::Config::default();
        c.insert_json5("access_control", &text).unwrap();
        let dev = access_control("s", &reg, &[], true).to_string();
        assert!(dev.contains("local-all"));
        c.insert_json5("access_control", &dev).unwrap();
    }
}
