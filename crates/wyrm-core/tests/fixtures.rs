//! Compatibility contract: every fixture in `spec/fixtures/fixtures.json`
//! must decode to the documented JSON and re-encode to the exact canonical bytes.
//! The same file drives the Dart and C bindings.

use serde::Deserialize;
use std::collections::BTreeMap;
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::meta::MetaPatch;
use wyrm_core::{Attachment, NodeMeta, PtokClaims, Sample, Value};

#[derive(Deserialize)]
struct Fixture {
    name: String,
    hex: String,
    json: serde_json::Value,
}

fn fixtures() -> Vec<Fixture> {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../spec/fixtures/fixtures.json"
    );
    serde_json::from_str(&std::fs::read_to_string(path).expect("fixtures.json")).unwrap()
}

/// JSON (as produced by the Python generator) → Value, honouring our conventions:
/// integral floats stay Float only where the fixture wrote them as float (we can't tell
/// from JSON), so we compare via re-encoding rather than structural equality for floats.
fn json_to_value(j: &serde_json::Value) -> Value {
    match j {
        serde_json::Value::Null => Value::Null,
        serde_json::Value::Bool(b) => Value::Bool(*b),
        serde_json::Value::Number(n) => {
            if let Some(u) = n.as_u64() {
                Value::UInt(u)
            } else if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else {
                Value::Float(n.as_f64().unwrap())
            }
        }
        serde_json::Value::String(s) => Value::Str(s.clone()),
        serde_json::Value::Array(a) => Value::Array(a.iter().map(json_to_value).collect()),
        serde_json::Value::Object(o) => Value::Map(
            o.iter()
                .map(|(k, v)| (k.clone(), json_to_value(v)))
                .collect::<BTreeMap<_, _>>(),
        ),
    }
}

fn roundtrip<T>(name: &str, bytes: &[u8])
where
    T: for<'a> minicbor::Decode<'a, ()> + minicbor::Encode<()> + std::fmt::Debug + PartialEq,
{
    let v: T = from_slice(bytes).unwrap_or_else(|e| panic!("{name}: decode failed: {e}"));
    let re = to_vec(&v).unwrap();
    assert_eq!(
        hex::encode(&re),
        hex::encode(bytes),
        "{name}: canonical re-encode mismatch\n decoded = {v:?}"
    );
    let v2: T = from_slice(&re).unwrap();
    assert_eq!(v, v2, "{name}: second decode differs");
}

#[test]
fn all_fixtures_roundtrip() {
    let fx = fixtures();
    assert_eq!(fx.len(), 24, "fixture count changed — update bindings too");
    for f in &fx {
        let bytes = hex::decode(&f.hex).unwrap();
        let n = f.name.as_str();
        match n {
            _ if n.starts_with("val_") => roundtrip::<Sample>(n, &bytes),
            "meta_view_list" => roundtrip::<Vec<NodeMeta>>(n, &bytes),
            "meta_view_keys" => roundtrip::<Vec<String>>(n, &bytes),
            "meta_patch" => roundtrip::<MetaPatch>(n, &bytes),
            _ if n.starts_with("profile_") => {
                roundtrip::<wyrm_core::profile::ProfileDef>(n, &bytes)
            }
            _ if n.starts_with("meta_") => roundtrip::<NodeMeta>(n, &bytes),
            _ if n.starts_with("att_") => roundtrip::<Attachment>(n, &bytes),
            "ptok_claims_v1" => roundtrip::<Value>(n, &bytes),
            other => panic!("unclassified fixture {other}"),
        }
    }
}

#[test]
fn val_number_matches_json() {
    let f = fixtures()
        .into_iter()
        .find(|f| f.name == "val_number")
        .unwrap();
    let s: Sample = from_slice(&hex::decode(&f.hex).unwrap()).unwrap();
    assert_eq!(s.v, Value::Float(21.4));
    assert_eq!(s.q, wyrm_core::Quality::Good);
    assert_eq!(s.t, 1760000000123456);
    assert_eq!(f.json["0"], 21.4);
}

#[test]
fn ptok_claims_structure_matches_json() {
    let f = fixtures()
        .into_iter()
        .find(|f| f.name == "ptok_claims_v1")
        .unwrap();
    let v: Value = from_slice(&hex::decode(&f.hex).unwrap()).unwrap();
    let mut expected = json_to_value(&f.json);
    // jti travels as bytes; JSON shows it hex-encoded
    if let Value::Map(m) = &mut expected {
        if let Some(Value::Str(h)) = m.get("jti").cloned() {
            m.insert("jti".into(), Value::Bytes(hex::decode(h).unwrap()));
        }
    }
    assert_eq!(v, expected);

    // typed decode: exact canonical re-encode
    roundtrip::<PtokClaims>(&f.name, &hex::decode(&f.hex).unwrap());
    let c: PtokClaims = from_slice(&hex::decode(&f.hex).unwrap()).unwrap();
    assert_eq!(c.site, "plant-a");
    assert_eq!(c.grants.len(), 3);
    assert_eq!(c.grants[1].k, "wy/plant-a/down/bacnet/**");
    assert_eq!(c.grants[1].p, wyrm_core::Perm::Write);
    assert_eq!(c.jti, [0x11; 16]);
}

#[test]
fn attachment_status_helpers() {
    let a: Attachment = from_slice(
        &hex::decode("a2001829077376616c756520313530203e206d6178203132").unwrap_or_default(),
    )
    .unwrap_or_default();
    let _ = a; // tolerant: fixture-specific assertions live in all_fixtures_roundtrip
    let f = fixtures()
        .into_iter()
        .find(|f| f.name == "att_reply_err")
        .unwrap();
    let a: Attachment = from_slice(&hex::decode(&f.hex).unwrap()).unwrap();
    assert!(a.status.unwrap().is_error());
    assert_eq!(a.err.as_deref(), Some("value 150 > max 120"));
}

/// Spec 0.1.6 UI fields decode into their typed places.
#[test]
fn action_ui_fields() {
    let f = fixtures()
        .into_iter()
        .find(|f| f.name == "meta_action_ui")
        .unwrap();
    let m: NodeMeta = wyrm_core::codec::from_slice(&hex::decode(&f.hex).unwrap()).unwrap();
    let a = &m.actions.as_ref().unwrap()["add_device"];
    assert_eq!(a.display.as_deref(), Some("Add Device"));
    assert_eq!(a.group.as_deref(), Some(wyrm_core::meta::GROUP_NEW));
    assert_eq!(a.params["unit"].display.as_deref(), Some("Slave ID"));
    assert_eq!(a.params["unit"].description.as_deref(), Some("1..247"));
    assert_eq!(a.params["host"].placeholder.as_deref(), Some("10.0.1.199"));
    assert_eq!(
        a.params["password"].editor.as_deref(),
        Some(wyrm_core::meta::EDITOR_PASSWORD)
    );
    assert_eq!(m.actions.as_ref().unwrap()["restart"].group, None);
}

#[test]
fn keys_compress_matches_fixture() {
    let f = fixtures()
        .into_iter()
        .find(|f| f.name == "meta_view_keys")
        .unwrap();
    let compressed: Vec<String> = from_slice(&hex::decode(&f.hex).unwrap()).unwrap();
    let expanded = wyrm_core::keyspace::expand_keys(&compressed);
    assert_eq!(
        expanded,
        vec![
            "ahu1/supply_temp",
            "ahu1/return_temp",
            "ahu1/fan",
            "ahu2/supply_temp"
        ]
    );
    assert_eq!(wyrm_core::keyspace::compress_keys(&expanded), compressed);
}

/// Every `wire_enum!` table must equal its table in `spec/tables.json`:
/// same codes, same names, nothing missing on either side.
#[test]
fn wire_enums_match_spec_tables() {
    use std::collections::BTreeSet;
    use wyrm_core::meta::{TypeCode, Writable};
    use wyrm_core::{Perm, Quality, Status};

    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../spec/tables.json");
    let tables: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(path).expect("tables.json")).unwrap();

    fn spec(tables: &serde_json::Value, name: &str) -> BTreeSet<(u8, String)> {
        tables[name]
            .as_object()
            .unwrap_or_else(|| panic!("table {name} missing in tables.json"))
            .iter()
            .map(|(k, v)| {
                let code = match k.strip_prefix("0x") {
                    Some(hex) => u8::from_str_radix(hex, 16).unwrap(),
                    None => k.parse().unwrap(),
                };
                (code, v.as_str().unwrap().to_owned())
            })
            .collect()
    }

    macro_rules! check {
        ($ty:ty, $table:literal) => {{
            let rust: BTreeSet<(u8, String)> = <$ty>::ALL
                .iter()
                .map(|v| (v.code(), v.name().to_owned()))
                .collect();
            assert_eq!(
                rust,
                spec(&tables, $table),
                "{} vs tables.json/{}",
                stringify!($ty),
                $table
            );
            for v in <$ty>::ALL {
                assert_eq!(<$ty>::try_from(v.code()), Ok(*v));
            }
        }};
    }

    check!(TypeCode, "type_codes");
    check!(Perm, "perm_levels");
    check!(Writable, "writable_codes");
    check!(Quality, "quality_codes");
    check!(Status, "status_codes");
}
