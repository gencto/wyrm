//! `#[derive(Params)]` / `#[derive(ParamEnum)]` against the `Params` contract.

use std::collections::BTreeMap;
use wyrm_core::{TypeCode, Value};
use wyrm_link_sdk::driver::params::{ParamEnum, Params};
use wyrm_link_sdk::{ParamEnum, Params};

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
enum WriteMode {
    Auto,
    Single,
    #[param(name = "multi")]
    Multiple,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {
    #[param(desc = "device host")]
    host: String,
    #[param(default = 502)]
    port: u16,
    #[param(default = 500, min = 100, max = 10000)]
    timeout_ms: u32,
    #[param(default = 2)]
    retries: u8,
    #[param(default = -5)]
    offset: i16,
    #[param(default = 5.0, min = 0.1)]
    ping_s: f64,
    #[param(default = false)]
    contiguous_only: bool,
    #[param(enum, default = "auto")]
    write_mode: WriteMode,
    #[param(default = "", secret)]
    password: String,
    #[param(name = "unit-id", default = 1)]
    unit: u8,
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect::<BTreeMap<_, _>>(),
    )
}

#[test]
fn defaults_fill_in() {
    let c = Conn::from_value(&map(&[("host", "10.0.0.2".into())])).unwrap();
    assert_eq!(
        c,
        Conn {
            host: "10.0.0.2".into(),
            port: 502,
            timeout_ms: 500,
            retries: 2,
            offset: -5,
            ping_s: 5.0,
            contiguous_only: false,
            write_mode: WriteMode::Auto,
            password: String::new(),
            unit: 1,
        }
    );
    assert!(Conn::from_value(&map(&[])).is_err(), "host has no default");
}

#[test]
fn schema_shape() {
    let s = Conn::schema();
    let get = |n: &str| s.iter().find(|p| p.name == n).unwrap().clone();
    assert_eq!(get("host").ty, TypeCode::String);
    assert_eq!(get("host").desc, "device host");
    assert!(get("host").default.is_none());
    assert_eq!(get("port").ty, TypeCode::Number);
    assert_eq!(
        (get("port").min, get("port").max),
        (Some(0.0), Some(65535.0))
    );
    assert_eq!(get("timeout_ms").min, Some(100.0));
    assert_eq!(get("offset").default, Some(Value::Int(-5)));
    assert_eq!(get("ping_s").max, Some(f64::MAX));
    assert_eq!(get("write_mode").ty, TypeCode::Enum);
    assert_eq!(get("write_mode").enum_values, ["auto", "single", "multi"]);
    assert!(get("password").secret);
    assert!(s.iter().any(|p| p.name == "unit-id"));
}

#[test]
fn bounds_from_type_and_explicit() {
    let e = Conn::from_value(&map(&[
        ("host", "h".into()),
        ("timeout_ms", Value::UInt(5)),
    ]))
    .unwrap_err();
    assert_eq!(e.message, "timeout_ms: 5 < min 100");
    let e =
        Conn::from_value(&map(&[("host", "h".into()), ("port", Value::UInt(70_000))])).unwrap_err();
    assert_eq!(e.message, "port: 70000 > max 65535");
    assert!(Conn::from_value(&map(&[("host", "h".into()), ("retries", Value::Int(-1))])).is_err());
    assert!(
        Conn::from_value(&map(&[("host", "h".into()), ("ping_s", Value::Float(0.0))])).is_err()
    );
}

#[test]
fn enums_round_trip() {
    for m in [WriteMode::Auto, WriteMode::Single, WriteMode::Multiple] {
        assert_eq!(WriteMode::from_name(m.name()), Some(m));
    }
    assert_eq!(WriteMode::Multiple.name(), "multi");
    assert_eq!(WriteMode::from_name("multiple"), None);
    let c = Conn::from_value(&map(&[
        ("host", "h".into()),
        ("write_mode", "single".into()),
    ]))
    .unwrap();
    assert_eq!(c.write_mode, WriteMode::Single);
    assert!(Conn::from_value(&map(&[
        ("host", "h".into()),
        ("write_mode", "bogus".into())
    ]))
    .is_err());
}

#[test]
fn unknown_key_rejected_and_round_trip() {
    let e = Conn::from_value(&map(&[("host", "h".into()), ("prot", Value::UInt(1))])).unwrap_err();
    assert_eq!(e.message, "prot: unknown parameter");

    let c = Conn::from_value(&map(&[
        ("host", "h".into()),
        ("offset", Value::Int(-300)),
        ("password", "s3cret".into()),
        ("write_mode", "multi".into()),
    ]))
    .unwrap();
    let v = c.to_value();
    let Value::Map(m) = &v else { panic!() };
    assert_eq!(m["port"], Value::UInt(502));
    assert_eq!(m["offset"], Value::Int(-300));
    assert_eq!(m["ping_s"], Value::Float(5.0));
    assert_eq!(m["write_mode"], Value::Str("multi".into()));
    assert_eq!(Conn::from_value(&v).unwrap(), c);

    let public = c.public_map();
    assert!(!public.contains_key("password"));
    assert!(public.contains_key("host"));
}
