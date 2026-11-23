//! The alarm behind the SDK (`Portable<Alarm>` on the link runtime), as a caller on the wire
//! meets it. The SDK checks an action's arguments against `~meta` before the link sees them
//! (a map, no unknown name, every required one, each value of its declared type, an `enum` by
//! its index), so most refusals of a wrong argument are the SDK's; the link's own decoder
//! (`#[derive(Args)]`) answers for what the SDK lets through: a number that is no whole number
//! from 0, and a `dynamic` argument.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    reason = "test code: a failed step fails the test"
)]

use std::collections::BTreeMap;
use std::path::PathBuf;

use wyrm_core::status::StatusCode;
use wyrm_core::{Perm, Status, Value};
use wyrm_link_alarm::Alarm;
use wyrm_link_portable::{Portable, PortableConfig};
use wyrm_link_sdk::harness::{Reply, TestHarness, TEST_KEY_SEED};
use wyrm_link_sdk::Secret;

type Harness = TestHarness<Portable<Alarm>>;

fn data_dir() -> PathBuf {
    let d = std::env::temp_dir().join(format!(
        "wyrm-alarm-wire-{}-{}",
        std::process::id(),
        wyrm_link_sdk::now_us()
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn map<const N: usize>(entries: [(&str, Value); N]) -> Value {
    Value::Map(
        entries
            .into_iter()
            .map(|(k, v)| (k.to_owned(), v))
            .collect::<BTreeMap<_, _>>(),
    )
}

/// The status and the text of the one answer.
fn answer(r: &[Reply]) -> (Status, String) {
    assert_eq!(r.len(), 1, "{r:?}");
    let status = match r[0].att.status.expect("status present") {
        StatusCode::Known(s) => s,
        other => panic!("unexpected status {other:?}"),
    };
    (status, r[0].att.err.clone().unwrap_or_default())
}

async fn call(h: &Harness, path: &str, action: &str, args: Value) -> (Status, String) {
    answer(
        &h.invoke(path, action, args, Some(h.ptok(Perm::Config)))
            .await,
    )
}

fn refused(text: &str) -> (Status, String) {
    (Status::InvalidParameter, text.to_owned())
}

#[tokio::test(flavor = "multi_thread")]
async fn arguments_on_the_wire() {
    let dir = data_dir();
    let d = dir.clone();
    let h = Harness::start_with(PortableConfig::default(), move |c| {
        c.data_dir = Some(d);
        c.secrets.insert(".store_key", Secret::new(vec![9; 32]));
        c.secrets
            .insert(".requester_key", Secret::new(TEST_KEY_SEED.to_vec()));
    })
    .await;

    // the SDK: a required argument, an unknown name
    assert_eq!(
        call(&h, "", "add_class", map([])).await,
        refused("missing id")
    );
    assert_eq!(
        call(
            &h,
            "",
            "add_class",
            map([("id", Value::from("c")), ("x", Value::UInt(1))])
        )
        .await,
        refused("unknown param x")
    );
    let (status, text) = call(&h, "", "add_class", map([("id", Value::from("c"))])).await;
    assert_eq!(status, Status::Ok, "{text}");

    // the SDK: a `null` is no value of a typed argument, so it never says "keep" or "clear"
    assert_eq!(
        call(&h, "c", "edit", map([("escalation1_s", Value::Null)])).await,
        refused("escalation1_s: expected number")
    );
    let source = ("source", Value::from("wy/test/downstream/plc/temp"));
    assert_eq!(
        call(
            &h,
            "c",
            "add_watch",
            map([
                source.clone(),
                ("algorithm", Value::UInt(1)),
                ("max", Value::Null)
            ])
        )
        .await,
        refused("max: expected number")
    );
    // the SDK: an `enum` by its index only, a text parameter takes text only
    assert_eq!(
        call(
            &h,
            "c",
            "add_watch",
            map([source, ("algorithm", Value::from("boolean"))])
        )
        .await,
        refused("algorithm: expected enum index")
    );
    assert_eq!(
        call(
            &h,
            "",
            "add_sink",
            map([
                ("name", Value::from("n")),
                ("link", Value::from("l")),
                ("classes", Value::Array(vec![Value::from("c")]))
            ])
        )
        .await,
        refused("classes: value type does not match ~meta.type")
    );

    // the link: a number the SDK lets through that is no whole number from 0
    assert_eq!(
        call(&h, "c", "edit", map([("escalation1_s", Value::Int(-1))])).await,
        refused("escalation1_s: expected a whole number (a negative number)")
    );
    assert_eq!(
        call(&h, "c", "edit", map([("escalation2_s", Value::Float(1.5))])).await,
        refused("escalation2_s: expected a whole number (not a whole number)")
    );
    // what an action is about comes before its arguments: a caller whose rights are unknown
    // reads no record, whatever it asks for
    assert_eq!(
        call(&h, "", "get_alarms", map([("limit", Value::Float(1.5))])).await,
        (
            Status::PermissionDenied,
            "the caller's rights are unknown (its token carries no auth)".to_owned()
        )
    );
    // the link: a `dynamic` argument, where a `null` that is there reaches it
    assert_eq!(
        call(&h, "", "acknowledge", map([("id", Value::Null)])).await,
        refused("id: required")
    );
    assert_eq!(
        call(&h, "", "acknowledge", map([("id", Value::from("nine"))])).await,
        refused("id: a record id")
    );

    // an action without parameters: no arguments, or none of them
    assert_eq!(
        call(&h, "c", "remove", map([("x", Value::UInt(1))])).await,
        refused("unknown param x")
    );
    let (status, text) = call(&h, "c", "remove", map([])).await;
    assert_eq!(status, Status::Ok, "{text}");

    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
