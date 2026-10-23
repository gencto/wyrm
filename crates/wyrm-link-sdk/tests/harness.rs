//! End-to-end responder tests over an in-memory Zenoh session.

use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};
use wyrm_link_sdk::harness::SITE;
use wyrm_link_sdk::{Caller, Link, LinkCtx, LinkError, ReplySink, TestHarness};

type Calls = Arc<Mutex<Vec<(String, Value)>>>;

struct Demo {
    calls: Calls,
}

impl Link for Demo {
    const NAME: &'static str = "demo";
    const VERSION: &'static str = "0.1.0";
    type Config = Calls;

    async fn start(calls: Calls, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node("ahu1", NodeMeta::folder().display("AHU 1"))
            .await?;
        ctx.declare_node(
            "ahu1/supply_temp",
            NodeMeta::number()
                .unit("°C")
                .writable(Writable::Write)
                .cfg("min", -40.0)
                .cfg("max", 120.0)
                .attr("tag", Value::Array(vec!["hvac".into()])),
        )
        .await?;
        ctx.declare_node(
            "ahu1/fan",
            NodeMeta::leaf(TypeCode::Bool).writable(Writable::Write),
        )
        .await?;
        ctx.declare_node(
            "ahu1/setpoint_cfg",
            NodeMeta::number().writable(Writable::Config),
        )
        .await?;
        ctx.declare_node("ahu1/ro", NodeMeta::number()).await?;
        ctx.declare_node("vault", NodeMeta::folder().cfg("restricted", true))
            .await?;
        ctx.declare_action(
            "ahu1",
            "reset",
            ActionMeta::new()
                .param(
                    "mode",
                    ParamMeta::of(TypeCode::Enum)
                        .enum_values(["soft", "hard"])
                        .required(true),
                )
                .result(ActionResult::Type(TypeCode::String))
                .level(Perm::Write),
        )
        .await?;
        ctx.declare_action(
            "ahu1",
            "count",
            ActionMeta::new()
                .result(ActionResult::Stream)
                .stream(true)
                .level(Perm::Read),
        )
        .await?;
        ctx.declare_action(
            "ahu1",
            "slow",
            ActionMeta::new().level(Perm::Read).timeout_ms(200),
        )
        .await?;
        Ok(Self { calls })
    }

    async fn on_set(
        &mut self,
        path: &str,
        value: Value,
        _who: &Caller,
    ) -> wyrm_link_sdk::Result<()> {
        self.calls.lock().unwrap().push((path.to_owned(), value));
        Ok(())
    }

    async fn on_invoke(
        &mut self,
        _path: &str,
        action: &str,
        args: Value,
        _who: &Caller,
        out: ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        match action {
            "reset" => {
                let Value::Map(m) = args else { unreachable!() };
                assert_eq!(m.get("mode"), Some(&Value::UInt(1)));
                out.reply("done").await
            }
            "count" => {
                tokio::spawn(async move {
                    for i in 0..3u64 {
                        if out.reply(i).await.is_err() {
                            return;
                        }
                    }
                    let _ = out.done(None).await;
                });
                Ok(())
            }
            "slow" => {
                tokio::time::sleep(Duration::from_secs(2)).await;
                Ok(())
            }
            _ => Err(LinkError::not_supported(action)),
        }
    }
}

async fn harness() -> (TestHarness<Demo>, Calls) {
    let calls = Calls::default();
    (TestHarness::<Demo>::start(calls.clone()).await, calls)
}

fn status(a: &wyrm_core::Attachment) -> Status {
    match a.status.expect("status present") {
        wyrm_core::status::StatusCode::Known(s) => s,
        other => panic!("unexpected status {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn root_meta_and_list_order() {
    let (h, _) = harness().await;
    let (att, root) = h.meta("").await;
    assert_eq!(status(&att), Status::Ok);
    let root = root.unwrap();
    // `vault` is restricted: hidden from anonymous callers
    assert_eq!(root.children.as_deref(), Some(&["ahu1".into()][..]));
    let att = wyrm_core::Attachment {
        ptok: Some(h.ptok(Perm::List)),
        ..Default::default()
    };
    let r = h.query(&h.key("", "~meta"), None, att).await;
    let full: NodeMeta = wyrm_core::codec::from_slice(&r[0].payload).unwrap();
    assert_eq!(full.children.unwrap(), ["ahu1", "vault"]);
    assert_eq!(root.attr_value("driver"), Some(&Value::from("demo")));

    let (att, list) = h.list("ahu1").await;
    assert_eq!(status(&att), Status::Ok);
    let types: Vec<_> = list.iter().map(|m| m.ty).collect();
    assert_eq!(
        types,
        [
            Some(TypeCode::Number),
            Some(TypeCode::Bool),
            Some(TypeCode::Number),
            Some(TypeCode::Number)
        ]
    );
    let (_, ahu1) = h.meta("ahu1").await;
    let ahu1 = ahu1.unwrap();
    assert_eq!(
        ahu1.children.unwrap(),
        ["supply_temp", "fan", "setpoint_cfg", "ro"]
    );
    assert_eq!(ahu1.actions.unwrap().len(), 3);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn rev_bumps_and_not_modified() {
    let (h, _) = harness().await;
    let (att, _) = h.meta("ahu1").await;
    let rev = att.rev.unwrap();
    let r = h
        .query(
            &format!("{}?rev={rev}", h.key("ahu1", "~meta")),
            None,
            Default::default(),
        )
        .await;
    assert_eq!(r.len(), 1);
    assert!(r[0].payload.is_empty());
    assert_eq!(r[0].att.rev, Some(rev));

    h.ctx()
        .declare_node("ahu1/extra", NodeMeta::number())
        .await
        .unwrap();
    let (att, m) = h.meta("ahu1").await;
    assert_eq!(att.rev, Some(rev + 1));
    assert_eq!(m.unwrap().children.unwrap().last().unwrap(), "extra");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn keys_compressed_and_filtered() {
    let (h, _) = harness().await;
    let (_, all) = h.keys("", "").await;
    assert_eq!(
        all,
        [
            "ahu1",
            "ahu1/supply_temp",
            "ahu1/fan",
            "ahu1/setpoint_cfg",
            "ahu1/ro",
        ]
    );
    let (_, temps) = h.keys("", "match=tag:hvac").await;
    assert_eq!(temps, ["ahu1/supply_temp"]);
    let (_, temps) = h.keys("", "match=type:1;tag:hvac&depth=2").await;
    assert_eq!(temps, ["ahu1/supply_temp"]);
    let (_, none) = h.keys("", "match=type:1;tag:hvac&depth=1").await;
    assert!(none.is_empty());
    let (_, top) = h.keys("", "depth=1").await;
    assert_eq!(top, ["ahu1"], "restricted vault is not listed");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn unknown_path_is_not_found() {
    let (h, calls) = harness().await;
    let (att, m) = h.meta("nope").await;
    assert_eq!(status(&att), Status::NotFound);
    assert!(m.is_none());
    let att = h.set("nope", 1.0, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::NotFound);
    let r = h
        .invoke(
            "ahu1",
            "nope",
            Value::Map(Default::default()),
            Some(h.ptok(Perm::Config)),
        )
        .await;
    assert_eq!(status(&r[0].att), Status::NotFound);
    assert!(calls.lock().unwrap().is_empty());
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn set_with_valid_ptok_calls_driver() {
    let (h, calls) = harness().await;
    let att = h
        .set("ahu1/supply_temp", 21.5, Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), Status::Ok);
    assert!(att.err.is_none());
    assert_eq!(
        calls.lock().unwrap().as_slice(),
        [("ahu1/supply_temp".to_owned(), Value::Float(21.5))]
    );
    // a grant narrowed to the point itself is enough
    let k = h.key("ahu1/fan", "~set");
    let att = h
        .set("ahu1/fan", true, Some(h.mint_ptok(&[(&k, Perm::Write)])))
        .await;
    assert_eq!(status(&att), Status::Ok);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn set_denied_never_reaches_driver() {
    let (h, calls) = harness().await;
    let p = "ahu1/supply_temp";
    let deny = |att: wyrm_core::Attachment| {
        assert_eq!(status(&att), Status::PermissionDenied);
        assert!(att.err.is_none(), "no detail on denial");
    };

    // no token
    deny(h.set(p, 1.0, None).await);
    // expired
    let mut c = h.claims(&[(&h.key("**", ""), Perm::Write)]);
    c.exp = c.iat - 1;
    deny(h.set(p, 1.0, Some(h.sign(&c))).await);
    // wrong site
    let mut c = h.claims(&[(&h.key("**", ""), Perm::Write)]);
    c.site = "other".into();
    deny(h.set(p, 1.0, Some(h.sign(&c))).await);
    // replayed jti
    let tok = h.ptok(Perm::Write);
    assert_eq!(status(&h.set(p, 1.0, Some(tok.clone())).await), Status::Ok);
    deny(h.set(p, 2.0, Some(tok)).await);
    // grant on another branch
    deny(
        h.set(
            p,
            1.0,
            Some(h.mint_ptok(&[(&format!("wy/{SITE}/downstream/other/**"), Perm::Config)])),
        )
        .await,
    );
    // first intersecting grant wins even if a later one is higher
    let tok = h.mint_ptok(&[
        (&h.key("**", ""), Perm::Read),
        (&h.key("**", ""), Perm::Config),
    ]);
    deny(h.set(p, 1.0, Some(tok)).await);
    // max caps the grant
    let mut c = h.claims(&[(&h.key("**", ""), Perm::Config)]);
    c.max = Perm::Read;
    deny(h.set(p, 1.0, Some(h.sign(&c))).await);
    // maxperm in the attachment caps it too
    let payload = wyrm_core::codec::to_vec(&wyrm_core::SetRequest { v: 1.0.into() }).unwrap();
    let att = wyrm_core::Attachment {
        ptok: Some(h.ptok(Perm::Config)),
        maxperm: Some(Perm::Read),
        ..Default::default()
    };
    deny(
        h.query(&h.key(p, "~set"), Some(payload), att)
            .await
            .remove(0)
            .att,
    );
    // tampered signature
    let mut tok = h.ptok(Perm::Write);
    let last = tok.len() - 1;
    tok[last] ^= 0xff;
    deny(h.set(p, 1.0, Some(tok)).await);
    // write is not enough for a config-writable point
    deny(
        h.set("ahu1/setpoint_cfg", 1.0, Some(h.ptok(Perm::Write)))
            .await,
    );

    assert_eq!(
        calls.lock().unwrap().len(),
        1,
        "only the valid set reached the driver"
    );
    assert_eq!(
        status(
            &h.set("ahu1/setpoint_cfg", 1.0, Some(h.ptok(Perm::Config)))
                .await
        ),
        Status::Ok
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn set_validation_before_driver() {
    let (h, calls) = harness().await;
    let att = h
        .set("ahu1/supply_temp", 150u64, Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), Status::OutOfRange);
    assert_eq!(att.err.as_deref(), Some("value 150 > max 120"));
    let att = h.set("ahu1/fan", "on", Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::InvalidParameter);
    let att = h.set("ahu1/ro", 1.0, Some(h.ptok(Perm::Config))).await;
    assert_eq!(status(&att), Status::NotSupported);
    let att = h.set("ahu1", 1.0, Some(h.ptok(Perm::Config))).await;
    assert_eq!(status(&att), Status::NotSupported);
    assert!(calls.lock().unwrap().is_empty());
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn invoke_plain_and_required_params() {
    let (h, _) = harness().await;
    let mut args = std::collections::BTreeMap::new();
    let r = h
        .invoke(
            "ahu1",
            "reset",
            Value::Map(args.clone()),
            Some(h.ptok(Perm::Write)),
        )
        .await;
    assert_eq!(status(&r[0].att), Status::InvalidParameter);
    args.insert("mode".to_owned(), Value::UInt(1));
    let r = h
        .invoke(
            "ahu1",
            "reset",
            Value::Map(args.clone()),
            Some(h.ptok(Perm::Read)),
        )
        .await;
    assert_eq!(status(&r[0].att), Status::PermissionDenied);
    let r = h
        .invoke("ahu1", "reset", Value::Map(args), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(r.len(), 1);
    assert_eq!(status(&r[0].att), Status::Ok);
    assert_eq!(r[0].value(), Some(Value::from("done")));
    assert!(r[0].att.rid.is_none() && r[0].att.last.is_none());
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn invoke_stream_seq_rid_last() {
    let (h, _) = harness().await;
    let r = h
        .invoke(
            "ahu1",
            "count",
            Value::Map(Default::default()),
            Some(h.ptok(Perm::Read)),
        )
        .await;
    assert_eq!(r.len(), 4, "3 elements + final");
    let rid = r[0].att.rid.unwrap();
    for (i, rep) in r.iter().enumerate() {
        assert_eq!(status(&rep.att), Status::Ok);
        assert_eq!(rep.att.rid, Some(rid));
        assert_eq!(rep.att.seq, Some(i as u32));
        assert_eq!(rep.att.last, Some(i == 3));
    }
    assert_eq!(r[2].value(), Some(Value::UInt(2)));
    assert!(r[3].payload.is_empty());
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn invoke_timeout() {
    let (h, _) = harness().await;
    let r = h
        .invoke(
            "ahu1",
            "slow",
            Value::Map(Default::default()),
            Some(h.ptok(Perm::Read)),
        )
        .await;
    assert_eq!(r.len(), 1);
    assert_eq!(status(&r[0].att), Status::Timeout);
    // the driver task is free again
    let att = h.set("ahu1/fan", true, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn restricted_meta_needs_list() {
    let (h, _) = harness().await;
    let (att, m) = h.meta("vault").await;
    assert_eq!(status(&att), Status::PermissionDenied);
    assert!(m.is_none());
    let att = wyrm_core::Attachment {
        ptok: Some(h.ptok(Perm::List)),
        ..Default::default()
    };
    let r = h.query(&h.key("vault", "~meta"), None, att).await;
    assert_eq!(status(&r[0].att), Status::Ok);
    assert!(!r[0].payload.is_empty());
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn wildcard_fan_in() {
    let (h, _) = harness().await;
    let r = h
        .query(&h.key("ahu1/*", "~meta"), None, Default::default())
        .await;
    let mut keys: Vec<_> = r.iter().map(|r| r.key.clone()).collect();
    keys.sort();
    assert_eq!(keys.len(), 4);
    assert!(keys.iter().all(|k| k.ends_with("/~meta")));
    // restricted nodes are not part of fan-in
    let r = h
        .query(&h.key("*", "~meta"), None, Default::default())
        .await;
    assert_eq!(r.len(), 1);
    assert!(r[0].key.ends_with("/ahu1/~meta"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn liveliness_token() {
    let (h, _) = harness().await;
    let r = h
        .session()
        .liveliness()
        .get(format!("wy/{SITE}/downstream/*"))
        .await
        .unwrap();
    let mut keys = Vec::new();
    while let Ok(rep) = r.recv_async().await {
        keys.push(rep.result().unwrap().key_expr().to_string());
    }
    assert_eq!(keys, [format!("wy/{SITE}/downstream/demo")]);

    h.ctx().set_dynamic("ahu1", true).await.unwrap();
    let r = h.session().liveliness().get(h.key("*", "")).await.unwrap();
    let rep = r.recv_async().await.unwrap();
    assert_eq!(rep.result().unwrap().key_expr().as_str(), h.key("ahu1", ""));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn updates_publish_val_and_mark_all() {
    let (h, _) = harness().await;
    let sub = h
        .session()
        .declare_subscriber(h.key("**", "~val"))
        .await
        .unwrap();
    h.ctx()
        .update("ahu1/supply_temp", 21.4, Quality::Good, 1)
        .await
        .unwrap();
    let s = sub.recv_async().await.unwrap();
    assert_eq!(s.key_expr().as_str(), h.key("ahu1/supply_temp", "~val"));
    let v: Sample = wyrm_core::codec::from_slice(&s.payload().to_bytes()).unwrap();
    assert_eq!(
        v,
        Sample {
            v: Value::Float(21.4),
            q: Quality::Good,
            t: 1
        }
    );

    // containers have no ~val
    assert!(h.ctx().update("ahu1", 1.0, Quality::Good, 1).await.is_err());

    h.ctx()
        .mark_all(Quality::Bad, Some("bad/comm_fail"))
        .await
        .unwrap();
    let s = sub.recv_async().await.unwrap();
    let v: Sample = wyrm_core::codec::from_slice(&s.payload().to_bytes()).unwrap();
    assert_eq!(v.q, Quality::Bad);
    assert_eq!(v.v, Value::Float(21.4));
    let att: wyrm_core::Attachment =
        wyrm_core::codec::from_slice(&s.attachment().unwrap().to_bytes()).unwrap();
    assert_eq!(att.qual.as_deref(), Some("bad/comm_fail"));

    // list summary carries current quality
    let (_, list) = h.list("ahu1").await;
    assert_eq!(list[0].q, Some(Quality::Bad.code()));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn val_answered_only_when_enabled() {
    let (h, _) = harness().await;
    h.ctx()
        .update("ahu1/fan", true, Quality::Good, 5)
        .await
        .unwrap();
    assert!(h
        .query(&h.key("ahu1/fan", "~val"), None, Default::default())
        .await
        .is_empty());
    h.stop().await;

    let h = TestHarness::<Demo>::start_with(Calls::default(), |c| c.answer_val = true).await;
    h.ctx()
        .update("ahu1/fan", true, Quality::Good, 5)
        .await
        .unwrap();
    let r = h
        .query(&h.key("ahu1/fan", "~val"), None, Default::default())
        .await;
    assert_eq!(r.len(), 1);
    let v: Sample = wyrm_core::codec::from_slice(&r[0].payload).unwrap();
    assert_eq!(v.v, Value::Bool(true));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn remove_node_deletes_and_updates_parent() {
    let (h, _) = harness().await;
    let sub = h
        .session()
        .declare_subscriber(h.key("**", ""))
        .await
        .unwrap();
    let (att, _) = h.meta("").await;
    let rev = att.rev.unwrap();
    h.ctx().remove_node("ahu1").await.unwrap();

    let mut deleted = Vec::new();
    let mut parent_meta = None;
    while let Ok(Ok(s)) = tokio::time::timeout(Duration::from_millis(500), sub.recv_async()).await {
        match s.kind() {
            zenoh::sample::SampleKind::Delete => deleted.push(s.key_expr().to_string()),
            zenoh::sample::SampleKind::Put if s.key_expr().as_str() == h.key("", "~meta") => {
                parent_meta = Some(
                    wyrm_core::codec::from_slice::<NodeMeta>(&s.payload().to_bytes()).unwrap(),
                );
            }
            _ => {}
        }
    }
    assert_eq!(
        deleted.len(),
        5 * 2,
        "~meta and ~val of ahu1 and its 4 children"
    );
    let parent_meta = parent_meta.expect("parent ~meta republished");
    assert_eq!(parent_meta.rev, Some(rev + 1));
    assert!(
        parent_meta.children.unwrap().is_empty(),
        "published ~meta hides restricted vault"
    );
    let (att, _) = h.meta("ahu1/fan").await;
    assert_eq!(status(&att), Status::NotFound);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn stop_drops_liveliness_and_closes_ctx() {
    // Embedded mode: the session outlives the link.
    let session = zenoh::open(wyrm_link_sdk::harness::isolated_config())
        .await
        .unwrap();
    let handle = wyrm_link_sdk::spawn::<Demo>(
        session.clone(),
        wyrm_link_sdk::LinkConfig::new(SITE, "demo"),
        Calls::default(),
    )
    .await
    .unwrap();
    let ctx = handle.ctx().clone(); // as a driver polling task would hold it
    ctx.set_dynamic("ahu1", true).await.unwrap();
    let alive = |s: zenoh::Session| async move {
        let r = s
            .liveliness()
            .get(format!("wy/{SITE}/downstream/**"))
            .await
            .unwrap();
        let mut n = 0;
        while r.recv_async().await.is_ok() {
            n += 1;
        }
        n
    };
    assert_eq!(alive(session.clone()).await, 2, "link + dynamic node");

    handle.stop().await;
    assert_eq!(alive(session.clone()).await, 0);
    assert!(ctx.is_closed());
    let e = ctx
        .update("ahu1/fan", true, Quality::Good, 1)
        .await
        .unwrap_err();
    assert_eq!(e.status, Status::Closed);
    assert!(ctx.set_dynamic("ahu1", true).await.is_err());
}

#[tokio::test(flavor = "multi_thread")]
async fn data_dir_reaches_ctx() {
    let (h, _) = harness().await;
    assert_eq!(h.ctx().data_dir(), None);
    h.stop().await;

    let dir = std::env::temp_dir().join(format!("wyrm-sdk-data-{}", std::process::id()));
    let d = dir.clone();
    let h = TestHarness::<Demo>::start_with(Calls::default(), move |c| c.data_dir = Some(d)).await;
    assert_eq!(h.ctx().data_dir(), Some(dir.as_path()));
    h.stop().await;
}

/// ADR 0016: the broker's attributes arrive on `sys/overlays/<link>/~val`;
/// `~meta` and the list summary show them, `rev` moves, a re-declared node
/// keeps them, unknown names are ignored, an empty map clears them.
#[tokio::test(flavor = "multi_thread")]
async fn broker_overlays_merge_into_meta() {
    let (h, _) = harness().await;
    let overlay_key = format!("wy/{SITE}/sys/overlays/demo/~val");
    let publish = |v: Value| {
        let key = overlay_key.clone();
        let s = h.session().clone();
        async move {
            let sample = Sample {
                v,
                q: Quality::Good,
                t: 1,
            };
            s.put(key, wyrm_core::codec::to_vec(&sample).unwrap())
                .await
                .unwrap();
        }
    };
    let store = "wy/test/sys/history/g/w1";
    let attrs = |pairs: Vec<(&str, Value)>| {
        Value::Map(pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
    };
    let (att, _) = h.meta("ahu1/supply_temp").await;
    let (parent_att, _) = h.meta("ahu1").await;
    let rev = att.rev.unwrap();
    publish(attrs(vec![(
        "ahu1/supply_temp",
        attrs(vec![
            ("history", Value::Array(vec![store.into()])),
            ("display", "forged".into()),
        ]),
    )]))
    .await;
    let mut seen = None;
    for _ in 0..50 {
        let (att, m) = h.meta("ahu1/supply_temp").await;
        if att.rev != Some(rev) {
            seen = m;
            assert_eq!(att.rev, Some(rev + 1));
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let m = seen.expect("the overlay arrives");
    assert_eq!(
        m.attr_value("history"),
        Some(&Value::Array(vec![store.into()]))
    );
    // own attributes stay; an unknown name is not laid over
    assert_eq!(
        m.attr_value("tag"),
        Some(&Value::Array(vec!["hvac".into()]))
    );
    assert_eq!(m.attr_value("display"), None);
    // a cached rev is not "unchanged" any more
    let r = h
        .query(
            &format!("{}?rev={rev}", h.key("ahu1/supply_temp", "~meta")),
            None,
            Default::default(),
        )
        .await;
    assert!(!r[0].payload.is_empty());
    let (parent_now, _) = h.meta("ahu1").await;
    assert_ne!(parent_now.rev, parent_att.rev, "the parent's list changed");
    let (_, kids) = h.list("ahu1").await;
    let flags: Vec<Option<bool>> = kids.iter().map(|k| k.has_history).collect();
    assert_eq!(flags.iter().filter(|f| **f == Some(true)).count(), 1);
    // the driver declares the node again: the overlay stays
    h.ctx()
        .declare_node("ahu1/supply_temp", NodeMeta::number().unit("K"))
        .await
        .unwrap();
    let (_, m) = h.meta("ahu1/supply_temp").await;
    assert!(m.unwrap().attr_value("history").is_some());
    // an empty map clears it
    publish(Value::Map(Default::default())).await;
    for _ in 0..50 {
        let (_, m) = h.meta("ahu1/supply_temp").await;
        if m.unwrap().attr_value("history").is_none() {
            h.stop().await;
            return;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("the overlay was not cleared");
}
