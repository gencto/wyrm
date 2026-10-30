//! The DQL link on `SimHost` (ADR 0025): stored and ad-hoc queries, their tables, restarts,
//! rights of sink queries, bounds per event.

mod common;

use common::*;
use wyrm_core::{Status, Value};

fn add(
    h: &mut SimHost,
    id: &str,
    text: &str,
    who: &wyrm_link_api::Who,
) -> Result<Value, wyrm_link_api::AppError> {
    h.invoke(
        "",
        "add_query",
        map(&[
            ("id", s(id)),
            ("text", s(text)),
            ("publish_ms", Value::UInt(100)),
        ]),
        who,
    )
}

fn temps(h: &SimHost, q: &str) -> Vec<Value> {
    h.table(q)
        .into_iter()
        .map(|r| match r {
            Value::Map(m) => m.get("value").cloned().unwrap_or(Value::Null),
            r => panic!("{r:?}"),
        })
        .collect()
}

#[test]
fn a_stored_query_publishes_its_table_and_survives_a_restart() {
    let mut h = SimHost::new().with_mock(3);
    h.start();
    add(
        &mut h,
        "temps",
        "list wy/s/downstream/mock/** | where type == 'number' | subscribe",
        &writer(),
    )
    .unwrap();
    h.advance_ms(200);
    assert_eq!(
        temps(&h, "temps"),
        [Value::Int(0), Value::Int(1), Value::Int(2)]
    );
    assert_eq!(h.attr("temps", "status"), s("ready"));
    assert_eq!(h.attr("temps", "rows"), Value::UInt(3));
    assert_eq!(h.attr("temps", "created_by"), s("user:op"));
    assert!(matches!(h.attr("temps", "collect_ms"), Value::UInt(_)));
    assert_eq!(h.subs.len(), 1, "one subtree subscription");
    assert!(h.store_has("q/temps") && h.store_has("index"));

    h.put_value("wy/s/downstream/mock/d1/temp", Value::Int(42));
    h.advance_ms(200);
    assert_eq!(temps(&h, "temps")[1], Value::Int(42));

    h.restart();
    h.advance_ms(200);
    assert_eq!(
        temps(&h, "temps"),
        [Value::Int(0), Value::Int(42), Value::Int(2)]
    );

    // stats count it
    assert_eq!(h.nodes["stats/queries"].1, Some(Value::UInt(1)));
    assert_eq!(h.nodes["stats/rows"].1, Some(Value::UInt(3)));
}

#[test]
fn sink_queries_need_config_and_never_fire_on_start() {
    let mut h = SimHost::new().with_mock(2);
    h.start();
    let text = "list wy/s/downstream/mock/*/temp | subscribe | set ../sp = value * 2";
    let e = add(&mut h, "sp", text, &writer()).unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied);
    add(&mut h, "sp", text, &engineer()).unwrap();
    h.advance_ms(200);
    assert!(h.calls.is_empty(), "the first values are the baseline");
    h.put_value("wy/s/downstream/mock/d0/temp", Value::Int(5));
    assert_eq!(
        h.calls,
        [(
            "wy/s/downstream/mock/d0/sp".to_owned(),
            None,
            Value::Int(10)
        )]
    );
    // a restart with the same values writes nothing (D5)
    h.restart();
    h.advance_ms(200);
    assert_eq!(h.calls.len(), 1);
    // a write-only caller cannot turn a query into a sink query
    let e = h
        .invoke(
            "sp",
            "edit",
            map(&[("text", s("list wy/s/downstream/mock | invoke ack()"))]),
            &writer(),
        )
        .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied);
    // but may switch it off and on, and remove it
    h.set("sp/enabled", Value::Bool(false)).unwrap();
    assert_eq!(h.attr("sp", "status"), s("disabled"));
    assert!(h.subs.is_empty() && h.lists.is_empty());
    h.invoke("sp", "remove", Value::Null, &writer()).unwrap();
    assert!(!h.nodes.contains_key("sp") && !h.store_has("q/sp"));
}

#[test]
fn ad_hoc_queries_are_shared_and_expire() {
    let mut h = SimHost::new().with_mock(2);
    h.start();
    let args = || {
        map(&[
            ("text", s("list wy/s/downstream/mock")),
            ("ttl_s", Value::UInt(10)),
        ])
    };
    let a = h.invoke("", "run", args(), &writer()).unwrap();
    let b = h.invoke("", "run", args(), &writer()).unwrap();
    assert_eq!(a, b, "the same text shares one query");
    let Value::Map(m) = &a else { panic!() };
    let id = match m.get("id") {
        Some(Value::Str(s)) => s.clone(),
        _ => panic!(),
    };
    assert_eq!(m.get("table"), Some(&s(&format!("{id}/table"))));
    h.advance_ms(600);
    assert_eq!(h.table(&id).len(), 2);
    assert!(
        !h.store_has(&format!("q/{id}")),
        "ad-hoc queries are not stored"
    );
    // read again: renewed
    h.advance_ms(8_000);
    let t = h.invoke(&id, "get_table", Value::Null, &writer()).unwrap();
    assert!(matches!(&t, Value::Map(m) if m.get("total") == Some(&Value::UInt(2))));
    h.advance_ms(8_000);
    assert!(h.nodes.contains_key(&id));
    h.advance_ms(3_000);
    assert!(!h.nodes.contains_key(&id), "expired");
    assert!(h.lists.is_empty());
    // a named one, for a dataflow
    let r = h
        .invoke(
            "",
            "run",
            map(&[("text", s("list wy/s/downstream/mock")), ("id", s("flowq"))]),
            &writer(),
        )
        .unwrap();
    assert!(matches!(&r, Value::Map(m) if m.get("table") == Some(&s("flowq/table"))));
}

#[test]
fn wide_trees_stay_within_the_event_budget() {
    let mut h = SimHost::new().with_mock(900);
    h.start();
    add(
        &mut h,
        "all",
        "list wy/s/downstream/mock/** | where type == 'number' | subscribe | option max_rows=5000",
        &writer(),
    )
    .unwrap();
    h.advance_ms(200);
    assert_eq!(h.table("all").len(), 900);
    assert!(h.max_cmds <= wyrm_link_dql::BUDGET + 50, "{}", h.max_cmds);
    assert_eq!(h.attr("all", "lists_pending"), Value::UInt(0));
    assert_eq!(h.attr("all", "depth"), Value::UInt(2));
    // removing it ends its 901 lists within the budget too
    h.invoke("all", "remove", Value::Null, &writer()).unwrap();
    h.advance_ms(10);
    assert!(h.lists.is_empty());
    assert!(h.max_cmds <= wyrm_link_dql::BUDGET + 50);

    // wider than the list bound of one query: the table is incomplete and says why
    let mut h = SimHost::new().with_mock(1_200);
    h.start();
    add(
        &mut h,
        "all",
        "list wy/s/downstream/mock/** | where type == 'number'",
        &writer(),
    )
    .unwrap();
    h.advance_ms(200);
    assert!(h.table("all").len() < 1_200);
    assert!(matches!(h.attr("all", "error"), Value::Str(e) if e.starts_with("max_lists")));
    assert_eq!(h.attr("all", "status"), s("ready"));
}

#[test]
fn rows_appear_as_nodes_appear() {
    let mut h = SimHost::new().with_mock(1);
    h.start();
    add(
        &mut h,
        "q",
        "list wy/s/downstream/mock/** | where name == 'temp'",
        &writer(),
    )
    .unwrap();
    h.advance_ms(200);
    assert_eq!(h.table("q").len(), 1);
    h.add_node("wy/s/downstream/mock/d9", folder());
    h.add_node("wy/s/downstream/mock/d9/temp", number());
    h.advance_ms(200);
    assert_eq!(h.table("q").len(), 2);
}

#[test]
fn actions_validate_and_explain() {
    let mut h = SimHost::new();
    h.start();
    let e = add(&mut h, "q", "list x", &writer()).unwrap_err();
    assert_eq!(e.status, Status::InvalidParameter);
    assert!(e.msg.contains("stage 1"), "{}", e.msg);
    assert_eq!(
        add(&mut h, "stats", "list wy/s/downstream", &writer())
            .unwrap_err()
            .status,
        Status::InvalidParameter
    );
    add(&mut h, "q", "list wy/s/downstream", &writer()).unwrap();
    assert_eq!(
        add(&mut h, "q", "list wy/s/downstream", &writer())
            .unwrap_err()
            .status,
        Status::InvalidParameter
    );
    let x = h
        .invoke(
            "",
            "explain",
            map(&[(
                "text",
                s("list wy/s/downstream/m/** | subscribe | set ./x = value"),
            )]),
            &writer(),
        )
        .unwrap();
    let Value::Map(m) = x else { panic!() };
    assert_eq!(m["roots"], Value::Array(vec![s("wy/s/downstream/m")]));
    assert_eq!(m["sinks"], Value::Array(vec![s("./x/~set")]));
    let c = h
        .invoke(
            "",
            "convert_dsa",
            map(&[
                ("text", s("list /downstream/System/* | filter $type")),
                ("site", s("s")),
            ]),
            &writer(),
        )
        .unwrap();
    assert_eq!(
        c,
        map(&[("text", s("list wy/s/downstream/System/** | filter $type"))])
    );
    // export, then import under another id
    let Value::Map(x) = h.invoke("q", "export", Value::Null, &writer()).unwrap() else {
        panic!()
    };
    let json = x["json"].clone();
    h.invoke(
        "",
        "import",
        map(&[("json", json.clone()), ("id", s("q2"))]),
        &engineer(),
    )
    .unwrap();
    assert!(h.store_has("q/q2"));
    let e = h
        .invoke(
            "",
            "import",
            map(&[("json", json), ("id", s("q2"))]),
            &engineer(),
        )
        .unwrap_err();
    assert_eq!(e.status, Status::InvalidParameter);
}
