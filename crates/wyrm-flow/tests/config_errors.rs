//! Audit T7 (docs/rust-rules.md §8): a caller matches the variant of a refusal, and the cause
//! is kept. The texts themselves are in `refusal_texts.rs`.

#![allow(
    clippy::unwrap_used,
    clippy::panic,
    reason = "test code: a failed step fails the test"
)]

use std::collections::BTreeMap;
use std::error::Error as _;
use wyrm_core::Value;
use wyrm_flow::blocks::TableConfigError;
use wyrm_flow::scope::{AdmitError, Scope, ScopeError};
use wyrm_flow::{nodes, ConfigError, QueryError};

fn cfg(kv: &[(&str, Value)]) -> BTreeMap<String, Value> {
    kv.iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect()
}

fn refused(ty: &str, kv: &[(&str, Value)]) -> ConfigError {
    match nodes::ports(ty, &cfg(kv)) {
        Err(e) => e,
        Ok(_) => panic!("{ty}: not refused"),
    }
}

#[test]
fn a_config_refusal_has_its_variant() {
    let e = refused("timer", &[("period_ms", "x".into())]);
    assert!(
        matches!(&e, ConfigError::Number(f) if f == "period_ms"),
        "{e:?}"
    );
    let e = refused("timer", &[]);
    assert!(
        matches!(&e, ConfigError::Required(f) if f == "period_ms"),
        "{e:?}"
    );
    let e = refused("timer", &[("oops", Value::UInt(1))]);
    assert!(
        matches!(&e, ConfigError::UnknownField(f) if f == "oops"),
        "{e:?}"
    );
    let e = refused("latch", &[("reset", "x".into())]);
    assert!(
        matches!(&e, ConfigError::OneOf { field, names }
            if field == "reset" && *names == ["manual", "auto"]),
        "{e:?}"
    );
    let e = refused("if", &[("op", "xor".into())]);
    assert!(matches!(e, ConfigError::Op(_)), "{e:?}");
    let e = refused("nope", &[]);
    assert!(
        matches!(&e, ConfigError::UnknownType(t) if t == "nope"),
        "{e:?}"
    );
    let e = refused(
        "load_history",
        &[("key", "downstream/m/p0".into()), ("window", "5x".into())],
    );
    assert!(
        matches!(&e, ConfigError::Query(QueryError::Window(w)) if w == "5x"),
        "{e:?}"
    );
}

#[test]
fn a_refusal_keeps_its_cause() {
    // a script: rhai's own error is the source
    let c = cfg(&[("expr", "v >".into())]);
    let e = nodes::check_script("filter", &c).unwrap_err();
    assert!(matches!(e, ConfigError::Expr(_)), "{e:?}");
    let cause = e.source().and_then(|s| s.source());
    assert!(
        cause.is_some_and(|c| c.is::<rhai::ParseError>()),
        "{cause:?}"
    );
    // a table block's script
    let c = cfg(&[("expr", "row.a +".into())]);
    let e = nodes::check_script("table_filter", &c).unwrap_err();
    assert!(
        matches!(e, ConfigError::Table(TableConfigError::Expr(_))),
        "{e:?}"
    );
    // a `publish` name that is no segment
    let e = refused("publish", &[("node", "a/b".into())]);
    let cause = e.source();
    assert!(
        cause.is_some_and(|c| c.is::<wyrm_core::keyspace::KeyError>()),
        "{cause:?}"
    );
    // a time before the epoch
    let e = refused(
        "load_history",
        &[
            ("key", "downstream/m/p0".into()),
            (
                "time_range",
                "1960-01-01T00:00:00/1960-01-02T00:00:00".into(),
            ),
        ],
    );
    assert!(
        matches!(
            e,
            ConfigError::Query(QueryError::Before1970 {
                us: -315_619_200_000_000,
                ..
            })
        ),
        "{e:?}"
    );
}

#[test]
fn scopes_and_keys_have_their_variants() {
    let e = Scope::new("s", "sys/**").unwrap_err();
    assert!(
        matches!(&e, ScopeError::Outside { site, full } if site == "s" && full == "wy/s/sys/**"),
        "{e:?}"
    );
    let e = Scope::new("s", "downstream//x").unwrap_err();
    assert!(matches!(e, ScopeError::KeyExpr(_)), "{e:?}");
    assert!(e.source().is_some());
    let sc = Scope::new("s", "downstream/m/*").unwrap();
    let refused = |v: Value| sc.admit(&v).unwrap_err();
    assert!(matches!(refused(Value::UInt(1)), AdmitError::NotText));
    assert!(matches!(refused("".into()), AdmitError::Empty));
    assert!(matches!(
        refused("downstream/m/".repeat(64).into()),
        AdmitError::Long
    ));
    assert!(matches!(
        refused("downstream/m/*".into()),
        AdmitError::NotConcrete(_)
    ));
    assert!(matches!(
        refused("sys/audit".into()),
        AdmitError::OutsideSections
    ));
    let e = refused("downstream/x/p".into());
    assert!(
        matches!(&e, AdmitError::OutsideScope(s) if s == "downstream/m/*"),
        "{e:?}"
    );
}
