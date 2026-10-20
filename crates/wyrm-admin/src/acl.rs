//! Zenoh `access_control` generated from the registry (wiki "Транспорт").
//!
//! Default deny. Directions are the router's: `ingress` = from that session
//! into the router, `egress` = from the router to that session.
//!
//! * link `L` (process/external, CN `L`): everything on `wy/S/down/L/**`,
//!   `query`/`reply` on its own `sys/links/L/~act/hello`, and liveliness of
//!   `sys/broker` (re-publish after a broker restart).
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
/// Broker certificates carry CN `broker:<site>`.
#[derive(Debug, Clone, Default)]
pub struct Peers {
    /// Sites this broker connects to; they may only read our `down/**` and
    /// `flows/**` (queries reach links, whose commands still need a `ptok`).
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
            &all_site,
        ),
        rule(
            "requester-out",
            &["egress"],
            &["put", "delete", "reply", "liveliness_token"],
            &all_site,
        ),
        rule(
            "requester-adv",
            &["ingress", "egress"],
            ALL,
            &[format!("wy/{site}/**/@adv/sub/**")],
        ),
        rule(
            "broker-watch",
            &["ingress", "egress"],
            &[
                "declare_liveliness_subscriber",
                "liveliness_query",
                "liveliness_token",
            ],
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
        subjects.push(json!({ "id": "operators", "cert_common_names": operators }));
        policies.push(json!({ "rules": requester_rules, "subjects": ["operators"] }));
    }
    for def in reg.links.values().filter(|d| d.mode.is_remote()) {
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
        subjects.push(json!({ "id": format!("cn-{id}"), "cert_common_names": [id] }));
        policies.push(json!({
            "rules": [format!("link-{id}"), format!("hello-{id}"), "broker-watch"],
            "subjects": [format!("cn-{id}")],
        }));
    }
    if !peers.upstream.is_empty() {
        let readable = vec![format!("wy/{site}/down/**"), format!("wy/{site}/flows/**")];
        rules.push(rule(
            "upstream-in",
            &["ingress"],
            &["query", "declare_subscriber", "declare_liveliness_subscriber", "liveliness_query"],
            &readable,
        ));
        rules.push(rule(
            "upstream-out",
            &["egress"],
            &["put", "delete", "reply", "liveliness_token", "declare_queryable", "declare_subscriber"],
            &readable,
        ));
        let cns: Vec<String> = peers.upstream.iter().map(|u| format!("broker:{u}")).collect();
        subjects.push(json!({ "id": "upstream", "cert_common_names": cns }));
        policies.push(json!({ "rules": ["upstream-in", "upstream-out"], "subjects": ["upstream"] }));
    }
    for d in &peers.downstream {
        rules.push(rule(&format!("site-{d}"), &["ingress", "egress"], ALL, &[format!("wy/{d}/**")]));
        subjects.push(json!({ "id": format!("broker-{d}"), "cert_common_names": [format!("broker:{d}")] }));
        policies.push(json!({ "rules": [format!("site-{d}")], "subjects": [format!("broker-{d}")] }));
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
        assert!(!text.contains("wy/plant-a/sys/**"), "upstream never reads sys");
        assert!(text.contains(r#""key_exprs":["wy/plant-b/**"]"#));
        let mut c = zenoh::Config::default();
        c.insert_json5("access_control", &text).unwrap();
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
