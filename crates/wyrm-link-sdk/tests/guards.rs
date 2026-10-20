//! Responder guards: per-caller rate limit and audit records.

use std::time::Duration;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Perm, Status, Value};
use wyrm_link_sdk::harness::SITE;
use wyrm_link_sdk::{Caller, Link, LinkCtx, TestHarness};

struct W;

impl Link for W {
    const NAME: &'static str = "w";
    const VERSION: &'static str = "0";
    type Config = ();

    async fn start(_: (), ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node("p", NodeMeta::number().writable(Writable::Write))
            .await?;
        Ok(W)
    }

    async fn on_set(&mut self, _p: &str, _v: Value, _w: &Caller) -> wyrm_link_sdk::Result<()> {
        Ok(())
    }
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn rate_limit_per_caller() {
    let h = TestHarness::<W>::start_with((), |c| c.rate_limit = Some((0.5, 2.0))).await;
    let mut seen = Vec::new();
    for _ in 0..3 {
        seen.push(status(&h.set("p", 1.0, Some(h.ptok(Perm::Write))).await));
    }
    assert_eq!(
        seen,
        [
            Some(Status::Ok),
            Some(Status::Ok),
            Some(Status::RateLimited)
        ]
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn every_set_is_audited_without_values() {
    let h = TestHarness::<W>::start(()).await;
    let sub = h
        .session()
        .declare_subscriber(format!("wy/{SITE}/sys/audit/w"))
        .await
        .unwrap();
    assert_eq!(
        status(&h.set("p", 42.0, Some(h.ptok(Perm::Write))).await),
        Some(Status::Ok)
    );
    assert_eq!(
        status(&h.set("p", 1.0, None).await),
        Some(Status::PermissionDenied)
    );
    let mut recs = Vec::new();
    for _ in 0..2 {
        let s = tokio::time::timeout(Duration::from_secs(2), sub.recv_async())
            .await
            .expect("audit record")
            .unwrap();
        let Value::Map(m) = wyrm_core::codec::from_slice::<Value>(&s.payload().to_bytes()).unwrap()
        else {
            panic!("record is a map");
        };
        recs.push(m);
    }
    assert_eq!(recs[0]["sub"], Value::from("user:test"));
    assert_eq!(recs[0]["op"], Value::from("set"));
    assert_eq!(recs[0]["status"], Value::UInt(Status::Ok.code().into()));
    assert!(matches!(&recs[0]["args_hash"], Value::Bytes(b) if b.len() == 32));
    assert!(
        !recs[0].values().any(|v| *v == Value::Float(42.0)),
        "no values in audit"
    );
    assert_eq!(
        recs[1]["status"],
        Value::UInt(Status::PermissionDenied.code().into())
    );
    h.stop().await;
}
