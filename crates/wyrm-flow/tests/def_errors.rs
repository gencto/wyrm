//! Audit T7 (docs/rust-rules.md §8): a caller matches the variant of a refused flow
//! definition and reads its fields; a wrapped refusal is a typed field, printed once. The
//! texts themselves are in `refusal_texts.rs`.

#![allow(
    clippy::unwrap_used,
    clippy::panic,
    reason = "test code: a failed step fails the test"
)]

use std::error::Error as _;
use wyrm_core::{Perm, Value};
use wyrm_flow::def::{self, ConstantError, DefError};
use wyrm_flow::nodes::PortType;
use wyrm_flow::ConfigError;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn s(x: &str) -> Value {
    Value::from(x)
}

fn node(ty: &str, kv: &[(&str, Value)]) -> Value {
    let mut kv = kv.to_vec();
    kv.push(("type", s(ty)));
    map(&kv)
}

fn flow(nodes: &[(&str, Value)], edges: &[(&str, &str)], more: &[(&str, Value)]) -> Value {
    let edges = edges
        .iter()
        .map(|(a, b)| Value::Array(vec![s(a), s(b)]))
        .collect();
    let mut kv = vec![
        ("id", s("f")),
        ("nodes", map(nodes)),
        ("edges", Value::Array(edges)),
    ];
    kv.extend(more.iter().cloned());
    map(&kv)
}

fn refused(d: &Value) -> DefError {
    match def::compile(d) {
        Err(e) => e,
        Ok(_) => panic!("not refused"),
    }
}

#[test]
fn a_refused_definition_has_its_variant() {
    // the place and what is wrong, as fields
    let e = refused(&flow(
        &[
            ("a", node("not", &[])),
            ("b", node("window", &[("size_s", Value::UInt(1))])),
        ],
        &[("a.out", "b.in")],
        &[],
    ));
    let DefError::NoFit {
        at,
        from,
        from_type,
        to,
        to_type,
    } = &e
    else {
        panic!("{e:?}");
    };
    assert_eq!(at, "edges[0]");
    assert_eq!((from.node.as_str(), from.port.as_str()), ("a", "out"));
    assert_eq!((to.node.as_str(), to.port.as_str()), ("b", "in"));
    assert_eq!((*from_type, *to_type), (PortType::Bool, PortType::Number));

    // the rights a command needs, as levels
    let invoke = node(
        "invoke",
        &[("path", s("downstream/m/a")), ("action", s("go"))],
    );
    let e = refused(&flow(&[("i", invoke)], &[], &[]));
    assert!(
        matches!(
            &e,
            DefError::MaxPerm { maxperm: Perm::Read, need: Perm::Write, node, ty }
                if node == "i" && ty == "invoke"
        ),
        "{e:?}"
    );

    // a loop, as the nodes it goes through
    let e = refused(&flow(
        &[("x", node("not", &[])), ("y", node("not", &[]))],
        &[("x.out", "y.in"), ("y.out", "x.in")],
        &[],
    ));
    let DefError::Cycle { cycle } = &e else {
        panic!("{e:?}");
    };
    assert_eq!(cycle, &["x", "y", "x"]);

    // the targets of a definition that does not parse
    let e = wyrm_flow::command_targets(&Value::UInt(1), "s").unwrap_err();
    assert!(
        matches!(&e, DefError::NotMap { at } if at == "~def"),
        "{e:?}"
    );
}

#[test]
fn a_wrapped_refusal_is_typed_and_printed_once() {
    // a node's own config refusal: the node, and the config error as it is
    let e = refused(&flow(&[("t", node("nope", &[]))], &[], &[]));
    let DefError::Node { node: id, error } = &e else {
        panic!("{e:?}");
    };
    assert_eq!(id, "t");
    assert!(
        matches!(error, ConfigError::UnknownType(t) if t == "nope"),
        "{error:?}"
    );
    // printed once: the text holds it, the chain does not repeat it
    assert_eq!(e.to_string(), format!("nodes.t: {error}"));
    assert!(e.source().is_none());

    // a constant of a custom block's input that an inner input does not take
    let block = map(&[
        (
            "nodes",
            map(&[("f", node("filter", &[("expr", s("v > 1"))]))]),
        ),
        (
            "inputs",
            Value::Array(vec![map(&[
                ("name", s("x")),
                ("to", s("f.in")),
                ("default", Value::UInt(1)),
            ])]),
        ),
    ]);
    let e = refused(&flow(
        &[("u", node("block:b", &[]))],
        &[],
        &[("blocks", map(&[("b", block)]))],
    ));
    assert!(
        matches!(
            &e,
            DefError::Constant { node, input, error: ConstantError::TakesNone { node: inner, port } }
                if node == "u" && input == "x" && inner == "f" && port == "in"
        ),
        "{e:?}"
    );
    assert!(e.source().is_none());

    // an id that is no key segment
    let e = refused(&map(&[("id", s("a/b"))]));
    assert!(matches!(&e, DefError::Id(_)), "{e:?}");
    assert!(e.source().is_none());
}
