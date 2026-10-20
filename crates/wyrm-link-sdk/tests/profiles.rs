//! Profiles in the responder (spec 02): `view=full&expand=true` folds the
//! node's profile chain in; `view=list` flags children that deviate.

use std::time::Duration;
use wyrm_core::meta::{Profile, TextOrCode, TypeCode};
use wyrm_core::profile::ProfileDef;
use wyrm_core::NodeMeta;
use wyrm_link_sdk::harness::SITE;
use wyrm_link_sdk::{Link, LinkCtx, TestHarness};

struct P;

fn temp(unit: Option<&str>) -> NodeMeta {
    NodeMeta {
        is: Some(Profile::Name("acme:temp".into())),
        unit: unit.map(|u| TextOrCode::Text(u.into())),
        ..Default::default()
    }
}

impl Link for P {
    const NAME: &'static str = "p";
    const VERSION: &'static str = "0";
    type Config = ();

    async fn start(_: (), ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node("plain", temp(None)).await?;
        ctx.declare_node("odd", temp(Some("K"))).await?;
        Ok(P)
    }
}

fn get_meta(r: &[wyrm_link_sdk::harness::Reply]) -> Vec<u8> {
    r.first().expect("a reply").payload.clone()
}

#[tokio::test(flavor = "multi_thread")]
async fn expand_and_has_override() {
    let h = TestHarness::<P>::start(()).await;
    let profile = ProfileDef {
        meta: NodeMeta {
            unit: Some(TextOrCode::Text("°C".into())),
            ..Default::default()
        },
        extends: Some("wy:number".into()),
    };
    // the follower picks the profile up (re-put: it may subscribe late)
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    let expanded = loop {
        h.session()
            .put(
                format!("wy/{SITE}/pub/acme:temp/~meta"),
                wyrm_core::codec::to_vec(&profile).unwrap(),
            )
            .await
            .unwrap();
        let r = h
            .query(
                &format!("{}?view=full&expand=true", h.key("plain", "~meta")),
                None,
                Default::default(),
            )
            .await;
        let m: NodeMeta = wyrm_core::codec::from_slice(&get_meta(&r)).unwrap();
        if m.unit.is_some() || tokio::time::Instant::now() > deadline {
            break m;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    };
    assert_eq!(expanded.unit, Some(TextOrCode::Text("°C".into())));
    assert_eq!(expanded.ty, Some(TypeCode::Number), "through wy:number");
    // without expand: own fields only
    let r = h
        .query(&h.key("plain", "~meta"), None, Default::default())
        .await;
    let own: NodeMeta = wyrm_core::codec::from_slice(&get_meta(&r)).unwrap();
    assert_eq!(own.unit, None);
    // view=list: only the deviating child is flagged
    let r = h
        .query(
            &format!("{}?view=list", h.key("", "~meta")),
            None,
            Default::default(),
        )
        .await;
    let list: Vec<NodeMeta> = wyrm_core::codec::from_slice(&get_meta(&r)).unwrap();
    let flags: Vec<Option<bool>> = list.iter().map(|m| m.has_override).collect();
    assert_eq!(flags, [None, Some(true)], "{list:?}");
    h.stop().await;
}
