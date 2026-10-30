//! Against a real agent (net-snmp `snmpd`), when one is given:
//!
//! ```text
//! WYRM_SNMP_AGENT=127.0.0.1:16163 WYRM_SNMP_COMMUNITY=public \
//! WYRM_SNMP_USER=sha1user WYRM_SNMP_PASS=sha1user-pass \
//!   cargo test -p wyrm-link-snmp --test interop -- --ignored
//! ```
//!
//! The v3 user is SHA-1 + AES-128 with one passphrase for both
//! (`createUser sha1user SHA "<pass>" AES "<pass>"` in `snmpd.conf`).

use std::time::Duration;
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_sdk::driver::{NodeState, Tree};
use wyrm_link_sdk::TestHarness;
use wyrm_link_snmp::Snmp;

type H = TestHarness<Snmp>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

fn state(h: &H, base: &str) -> Option<&'static str> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => NodeState::NAMES.get(i as usize).copied(),
        _ => None,
    }
}

fn points() -> Value {
    let p = |kv: &[(&str, Value)]| {
        let mut kv = kv.to_vec();
        kv.push(("poll_s", Value::Float(0.5)));
        map(&kv)
    };
    map(&[
        (
            "uptime",
            p(&[
                ("oid", "1.3.6.1.2.1.1.3.0".into()),
                ("conv", "timeticks_s".into()),
            ]),
        ),
        ("name", p(&[("oid", "iso.3.6.1.2.1.1.5.0".into())])),
        (
            "if1",
            p(&[
                ("oid", "1.3.6.1.2.1.2.2.1.2".into()),
                ("kind", "table_column".into()),
                ("index", "1".into()),
            ]),
        ),
        ("missing", p(&[("oid", "1.3.6.1.4.1.64999.9.0".into())])),
    ])
}

async fn check(conn: Vec<(&str, Value)>) {
    let mut c = conn;
    c.push((
        "devices",
        map(&[(
            "d1",
            map(&[("ping_s", Value::Float(1.0)), ("points", points())]),
        )]),
    ));
    let h = H::start(Tree(map(&[("connections", map(&[("c1", map(&c))]))]))).await;
    let good = |p: &str| {
        h.ctx()
            .last(&format!("c1/d1/{p}"))
            .is_some_and(|s| s.q == Quality::Good)
    };
    wait("values", || good("uptime") && good("name") && good("if1")).await;
    wait("missing is a point error", || {
        h.ctx()
            .last("c1/d1/missing")
            .is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    assert_eq!(state(&h, "c1/d1"), Some("connected"));
    let mut r = h
        .invoke(
            "c1/d1",
            "walk",
            map(&[("oid", "1.3.6.1.2.1.1".into())]),
            Some(h.ptok(Perm::Read)),
        )
        .await;
    let r = r.remove(0);
    assert_eq!(
        r.att.status,
        Some(wyrm_core::status::StatusCode::Known(Status::Ok))
    );
    let Some(Value::Array(rows)) = r.value() else {
        panic!("walk")
    };
    assert!(rows.len() >= 7, "system group: {} rows", rows.len());
    h.stop().await;
}

fn agent() -> Option<(String, u16)> {
    let a = std::env::var("WYRM_SNMP_AGENT").ok()?;
    let (host, port) = a.rsplit_once(':')?;
    Some((host.to_owned(), port.parse().ok()?))
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs an SNMP agent: WYRM_SNMP_AGENT=host:port"]
async fn v2c_against_a_real_agent() {
    let Some((host, port)) = agent() else {
        eprintln!("WYRM_SNMP_AGENT not set: skipped");
        return;
    };
    let community = std::env::var("WYRM_SNMP_COMMUNITY").unwrap_or_else(|_| "public".into());
    check(vec![
        ("kind", "snmp_v2c".into()),
        ("host", host.into()),
        ("port", Value::UInt(port.into())),
        ("community", community.into()),
    ])
    .await;
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs an SNMPv3 agent: WYRM_SNMP_AGENT, WYRM_SNMP_USER, WYRM_SNMP_PASS"]
async fn v3_sha1_aes_against_a_real_agent() {
    let (Some((host, port)), Ok(user), Ok(pass)) = (
        agent(),
        std::env::var("WYRM_SNMP_USER"),
        std::env::var("WYRM_SNMP_PASS"),
    ) else {
        eprintln!("WYRM_SNMP_AGENT, WYRM_SNMP_USER or WYRM_SNMP_PASS not set: skipped");
        return;
    };
    check(vec![
        ("kind", "snmp_v3".into()),
        ("host", host.into()),
        ("port", Value::UInt(port.into())),
        ("user", user.into()),
        ("auth_protocol", "sha1".into()),
        ("auth_passphrase", pass.clone().into()),
        ("priv_protocol", "aes128".into()),
        ("priv_passphrase", pass.into()),
    ])
    .await;
}
