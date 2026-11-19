//! `#[derive(Args)]`: one struct is the declared parameters of an action and
//! the decoder of its arguments.

#![allow(
    dead_code,
    clippy::unwrap_used,
    reason = "test code: a failed step fails the test; some structs are only declared and decoded"
)]

use std::collections::BTreeMap;
use wyrm_core::args::{ArgError, Fault};
use wyrm_core::meta::{Editor, ParamMeta};
use wyrm_core::value::IntError;
use wyrm_core::{TypeCode, Value};
use wyrm_link_sdk::{Args, LinkError, Secret, SecretBytes, SecretLine};

wyrm_core::name_enum! {
    pub enum Mode as "mode" {
        Add => "add",
        Replace => "replace",
    }
}

#[derive(Args, Debug, PartialEq)]
struct Common {
    #[param(display = "Accept", absent = false)]
    accept: bool,
    #[param(display = "Seconds", min = 0.0, max = 3600.0)]
    wait_s: Option<f64>,
}

/// A secret, a text that is trimmed, a set that is trimmed.
#[derive(Args, Debug)]
struct Sealed {
    #[param(secret, nonempty)]
    passphrase: Option<Secret>,
    #[param(nonempty)]
    role: Option<String>,
    #[param(trim, nonempty)]
    note: Option<String>,
    #[param(choice, trim, nonempty)]
    mode: Option<Mode>,
    #[param(secret, trim, nonempty)]
    token: Option<SecretLine>,
}

#[derive(Args, Debug)]
struct Install {
    #[param(display = "Name", desc = "Id of the new link", trim, nonempty)]
    name: String,
    #[param(display = "ZIP file", editor = "file")]
    zip: Vec<u8>,
    #[param(name = "ref", placeholder = format!("branch or {}", "tag"), trim, nonempty)]
    git_ref: Option<String>,
    #[param(choice, display = "Mode")]
    mode: Option<Mode>,
    #[param(enum)]
    index: Option<Mode>,
    #[param(choice, reversed)]
    last_first: Option<Mode>,
    #[param(choice)]
    modes: Option<Vec<Mode>>,
    #[param(suggest = ["1s", "1m"])]
    interval: Option<String>,
    #[param(min = 1, max = 2000, default = 200)]
    lines: u64,
    count: Option<u16>,
    params: Option<BTreeMap<String, Value>>,
    via: Option<Vec<String>>,
    #[param(secret)]
    passphrase: Option<Secret>,
    #[param(secret)]
    value: Option<SecretBytes>,
    #[param(flatten)]
    common: Common,
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn base() -> Vec<(&'static str, Value)> {
    vec![("name", " a ".into()), ("zip", Value::Bytes(vec![1]))]
}

fn with(extra: &[(&'static str, Value)]) -> Result<Install, ArgError> {
    let mut kv = base();
    kv.extend(extra.iter().cloned());
    Install::decode(map(&kv))
}

fn fault(extra: &[(&'static str, Value)]) -> (String, Fault) {
    let e = with(extra).unwrap_err();
    (e.field, e.fault)
}

#[test]
fn the_struct_declares_the_parameters() {
    let a = Install::action();
    let names: Vec<&str> = a.params.keys().map(String::as_str).collect();
    assert_eq!(
        names,
        [
            "accept",
            "count",
            "index",
            "interval",
            "last_first",
            "lines",
            "mode",
            "modes",
            "name",
            "params",
            "passphrase",
            "ref",
            "value",
            "via",
            "wait_s",
            "zip"
        ]
    );
    let p = |n: &str| a.params[n].clone();
    assert_eq!(
        p("name"),
        ParamMeta::of(TypeCode::String)
            .required(true)
            .display("Name")
            .description("Id of the new link")
    );
    assert_eq!(
        p("zip"),
        ParamMeta::of(TypeCode::Binary)
            .required(true)
            .display("ZIP file")
            .editor(Editor::File)
    );
    // optional: no `required` key at all
    assert_eq!(
        p("ref"),
        ParamMeta::of(TypeCode::String).placeholder("branch or tag")
    );
    assert_eq!(
        p("mode"),
        ParamMeta::of(TypeCode::String)
            .enum_values(["add", "replace"])
            .display("Mode")
    );
    assert_eq!(
        p("index"),
        ParamMeta::of(TypeCode::Enum).enum_values(["add", "replace"])
    );
    assert_eq!(
        p("last_first"),
        ParamMeta::of(TypeCode::String).enum_values(["replace", "add"])
    );
    assert_eq!(p("modes"), ParamMeta::of(TypeCode::Array));
    assert_eq!(
        p("interval"),
        ParamMeta::of(TypeCode::String).enum_values(["1s", "1m"])
    );
    let mut lines = ParamMeta::of(TypeCode::Number);
    lines.default = Some(Value::UInt(200));
    assert_eq!(p("lines"), lines);
    assert_eq!(p("count"), ParamMeta::of(TypeCode::Number));
    assert_eq!(p("params"), ParamMeta::of(TypeCode::Map));
    assert_eq!(p("via"), ParamMeta::of(TypeCode::Array));
    assert_eq!(
        p("passphrase"),
        ParamMeta::of(TypeCode::String).editor(Editor::Password)
    );
    assert_eq!(
        p("value"),
        ParamMeta::of(TypeCode::Binary).editor(Editor::Password)
    );
    // a flattened struct's fields are parameters of the action; `absent` is not published
    assert_eq!(p("accept"), ParamMeta::of(TypeCode::Bool).display("Accept"));
    assert_eq!(
        p("wait_s"),
        ParamMeta::of(TypeCode::Number).display("Seconds")
    );
}

#[test]
fn the_struct_decodes_the_arguments() {
    let a = with(&[]).unwrap();
    assert_eq!(a.name, "a", "trimmed");
    assert_eq!(a.zip, [1]);
    assert_eq!(a.lines, 200, "the default");
    assert_eq!((a.git_ref, a.last_first), (None, None));
    assert_eq!(
        a.common,
        Common {
            accept: false,
            wait_s: None
        }
    );

    let a = with(&[
        ("ref", " main ".into()),
        ("mode", "replace".into()),
        ("index", Value::UInt(1)),
        ("modes", Value::Array(vec!["add".into()])),
        ("interval", "7h".into()),
        ("lines", Value::Float(20.0)),
        ("count", Value::UInt(65_535)),
        ("params", map(&[("x", Value::Bool(true))])),
        ("via", Value::Array(vec!["plant".into()])),
        ("passphrase", "pw".into()),
        ("value", Value::Bytes(vec![7])),
        ("accept", Value::Bool(true)),
        ("wait_s", Value::UInt(5)),
    ])
    .unwrap();
    assert_eq!(a.git_ref.as_deref(), Some("main"));
    assert_eq!(
        (a.mode, a.index),
        (Some(Mode::Replace), Some(Mode::Replace))
    );
    assert_eq!(a.modes, Some(vec![Mode::Add]));
    assert_eq!(a.interval.as_deref(), Some("7h"), "a suggestion is no set");
    assert_eq!((a.lines, a.count), (20, Some(65_535)));
    assert_eq!(a.params.unwrap()["x"], Value::Bool(true));
    assert_eq!(a.via, Some(vec!["plant".to_owned()]));
    assert_eq!(a.passphrase.unwrap().expose(), b"pw");
    assert_eq!(a.value.unwrap().0.expose(), [7]);
    assert_eq!(
        a.common,
        Common {
            accept: true,
            wait_s: Some(5.0)
        }
    );
    // an empty optional `nonempty` text and a null are not there
    let a = with(&[("ref", "  ".into()), ("count", Value::Null)]).unwrap();
    assert_eq!((a.git_ref, a.count), (None, None));
}

#[test]
fn a_bad_argument_is_refused_with_its_name() {
    let name = |s: &str| s.to_owned();
    // required
    let e = Install::decode(map(&[("zip", Value::Bytes(vec![]))])).unwrap_err();
    assert_eq!(e, ArgError::new("name", Fault::Missing));
    let e = Install::decode(map(&[("name", " ".into()), ("zip", Value::Bytes(vec![]))]));
    assert_eq!(e.unwrap_err(), ArgError::new("name", Fault::Missing));
    // a wrong type
    assert_eq!(
        fault(&[("zip", "text".into())]),
        (name("zip"), Fault::Type("bytes"))
    );
    assert_eq!(
        fault(&[("ref", Value::UInt(1))]),
        (name("ref"), Fault::Type("text"))
    );
    assert_eq!(
        fault(&[("accept", Value::UInt(1))]),
        (name("accept"), Fault::Type("true or false"))
    );
    assert_eq!(
        fault(&[("lines", "20".into())]),
        (name("lines"), Fault::Type("a number"))
    );
    assert_eq!(
        fault(&[("params", Value::Array(vec![]))]),
        (name("params"), Fault::Type("a map"))
    );
    assert_eq!(
        fault(&[("via", Value::Array(vec![Value::UInt(1)]))]),
        (
            name("via"),
            Fault::Item {
                index: 0,
                fault: Box::new(Fault::Type("text"))
            }
        )
    );
    assert_eq!(
        fault(&[("passphrase", Value::Bytes(vec![1]))]),
        (name("passphrase"), Fault::Type("text"))
    );
    // whole numbers only, inside the type and inside the bounds
    assert_eq!(
        fault(&[("lines", Value::Float(0.5))]),
        (name("lines"), Fault::Int(IntError::Fractional))
    );
    assert_eq!(
        fault(&[("count", Value::Int(-1))]),
        (name("count"), Fault::Int(IntError::Negative))
    );
    assert_eq!(
        fault(&[("count", Value::UInt(65_536))]),
        (name("count"), Fault::Int(IntError::OutOfRange))
    );
    assert_eq!(
        fault(&[("lines", Value::UInt(0))]),
        (name("lines"), Fault::Below(name("0"), name("1")))
    );
    assert_eq!(
        fault(&[("lines", Value::UInt(2001))]),
        (name("lines"), Fault::Above(name("2001"), name("2000")))
    );
    assert_eq!(
        fault(&[("wait_s", Value::Float(-0.5))]),
        (name("wait_s"), Fault::Below(name("-0.5"), name("0")))
    );
    assert_eq!(
        fault(&[("wait_s", Value::Float(f64::INFINITY))]),
        (name("wait_s"), Fault::NotFinite)
    );
    // a closed set
    assert!(matches!(
        fault(&[("mode", "merge".into())]),
        (f, Fault::Name(_)) if f == "mode"
    ));
    assert_eq!(
        fault(&[("mode", Value::UInt(0))]),
        (name("mode"), Fault::Type("a name"))
    );
    assert_eq!(
        fault(&[("index", Value::UInt(2))]),
        (name("index"), Fault::Index { index: 2, len: 2 })
    );
    assert_eq!(
        fault(&[("index", "add".into())]),
        (name("index"), Fault::Type("an index"))
    );
    assert!(matches!(
        fault(&[("modes", Value::Array(vec!["add".into(), "x".into()]))]),
        (f, Fault::Item { index: 1, .. }) if f == "modes"
    ));
    // a name that is no parameter, also beside a flattened struct
    assert_eq!(
        fault(&[("acept", Value::Bool(true))]),
        (name("acept"), Fault::Unknown)
    );
    assert_eq!(
        Install::decode(Value::Array(vec![])).unwrap_err(),
        ArgError::new("args", Fault::NotAMap)
    );
}

#[test]
fn a_refusal_is_a_link_error_with_the_field() {
    use wyrm_core::Status;
    let e: LinkError = with(&[("lines", Value::Float(0.5))]).unwrap_err().into();
    assert_eq!(e.status, Status::InvalidParameter);
    assert_eq!(
        e.message,
        "lines: expected a whole number (not a whole number)"
    );
    let e: LinkError = with(&[("lines", Value::UInt(5000))]).unwrap_err().into();
    assert_eq!(e.status, Status::InvalidParameter);
    assert_eq!(e.message, "lines: 5000 is above 2000");
    let e: LinkError = with(&[("typo", Value::UInt(1))]).unwrap_err().into();
    assert_eq!(e.status, Status::InvalidParameter);
    assert_eq!(e.message, "typo: unknown argument");
}

/// Audit of #136, finding 3: a secret is never trimmed. A passphrase of spaces
/// is a passphrase (read as "not given", a backup would be made unsealed); only
/// the empty text is "not given".
#[test]
fn a_secret_of_spaces_is_a_secret() {
    let pass = |text: &str| {
        Sealed::decode(map(&[("passphrase", text.into())]))
            .unwrap()
            .passphrase
            .map(|p| p.expose().to_vec())
    };
    assert_eq!(pass("            "), Some(b"            ".to_vec()));
    assert_eq!(pass(" a b "), Some(b" a b ".to_vec()));
    assert_eq!(pass(""), None);
    // a text without `trim`: only "" is not there
    let a = Sealed::decode(map(&[("role", "  ".into()), ("note", "  ".into())])).unwrap();
    assert_eq!((a.role.as_deref(), a.note), (Some("  "), None));
    // a set with `trim`: the name with white space around it
    let a = Sealed::decode(map(&[("mode", " replace ".into())])).unwrap();
    assert_eq!(a.mode, Some(Mode::Replace));
    assert_eq!(
        Sealed::decode(map(&[("mode", "  ".into())])).unwrap().mode,
        None
    );
    // the one secret that is trimmed: a pasted token
    let token = |text: &str| {
        Sealed::decode(map(&[("token", text.into())]))
            .unwrap()
            .token
            .map(|t| t.0.expose().to_vec())
    };
    assert_eq!(token(" abc.def\n"), Some(b"abc.def".to_vec()));
    assert_eq!(token(" \n"), None);
    assert_eq!(token(""), None);
    // the value is not in `Debug`
    let a = Sealed::decode(map(&[("passphrase", "hunter2hunter2".into())])).unwrap();
    assert!(!format!("{a:?}").contains("hunter2"), "{a:?}");
}

/// Audit of #136, finding 8: the arguments are taken, so a large binary argument
/// moves into the struct: the same allocation, no copy.
#[test]
fn bytes_move_into_the_struct() {
    let zip = vec![7u8; 1 << 20];
    let at = zip.as_ptr();
    let a = Install::decode(map_owned(vec![
        ("name", "a".into()),
        ("zip", Value::Bytes(zip)),
    ]))
    .unwrap();
    assert_eq!(a.zip.as_ptr(), at);
    assert_eq!(a.zip.len(), 1 << 20);
}

fn map_owned(kv: Vec<(&str, Value)>) -> Value {
    Value::Map(kv.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

/// Audit of #136, finding 6: an unknown name is the caller's text; the refusal
/// repeats at most 64 bytes of it.
#[test]
fn an_unknown_name_does_not_size_the_answer() {
    let long = "k".repeat(50_000);
    let e: LinkError = with(&[(Box::leak(long.into_boxed_str()), Value::UInt(1))])
        .unwrap_err()
        .into();
    assert!(e.message.len() < 100, "{}", e.message.len());
    assert!(e.message.ends_with(": unknown argument"));
}

/// Second audit of #136: the names of a struct and of what it flattens are a
/// constant the derive checks (`wyrm_link_sdk::args_rules` has the structs that
/// do not compile).
#[test]
fn the_names_are_a_constant() {
    let n = &<Install as Args>::NAMES;
    assert!(n.own.contains(&"name") && n.own.contains(&"ref"));
    assert_eq!(n.flat.len(), 1);
    assert_eq!(n.flat[0].own, ["accept", "wait_s"]);
    assert_eq!(
        (n.count("accept"), n.count("zip"), n.count("nope")),
        (1, 1, 0)
    );
    assert!(!n.repeats_in(n));
    // every declared parameter is a name, and the reverse
    assert_eq!(Install::params().len(), n.own.len() + n.flat[0].own.len());
}
