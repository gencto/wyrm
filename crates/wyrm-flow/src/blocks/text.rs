//! Text and codec blocks of the third set (ADR 0044): `left`, `right`, `trim`, Base64, URL
//! components, camel case, hashes and JSON. Pure functions over a [`View`].

use super::{bounded_text, num, param, Outs, Shape, View, MAX_TEXT, N};
use crate::nodes::PortType::{self, *};
use base64::Engine as _;
use std::collections::BTreeMap;
use wyrm_core::Value;

/// The longest JSON text `json_parse` reads and `json_stringify` makes, bytes.
pub const MAX_JSON: usize = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Op {
    Left,
    Right,
    Trim,
    Base64Encode,
    Base64Decode,
    UrlEncode,
    UrlDecode,
    ToCamelCase,
    FromCamelCase,
    Hash,
    JsonParse,
    JsonStringify,
}

pub(super) const OPS: &[(&str, Op)] = &[
    ("left", Op::Left),
    ("right", Op::Right),
    ("trim", Op::Trim),
    ("base64_encode", Op::Base64Encode),
    ("base64_decode", Op::Base64Decode),
    ("url_encode", Op::UrlEncode),
    ("url_decode", Op::UrlDecode),
    ("to_camel_case", Op::ToCamelCase),
    ("from_camel_case", Op::FromCamelCase),
    ("hash", Op::Hash),
    ("json_parse", Op::JsonParse),
    ("json_stringify", Op::JsonStringify),
];

/// `hash`'s algorithms.
pub const HASHES: &[&str] = &["sha256", "sha1", "md5"];

fn one_in(params: Vec<super::Param>, outputs: &'static [(&'static str, PortType)]) -> Shape {
    Shape {
        inputs: &["in"],
        params,
        items: false,
        outputs,
    }
}

pub(super) fn shape(op: Op) -> Shape {
    match op {
        Op::Left | Op::Right => one_in(vec![param("length", Value::Int(0), true)], &[("out", Any)]),
        Op::Hash => one_in(
            vec![param("algorithm", Value::Str("sha256".into()), true)],
            &[("out", Any)],
        ),
        Op::Base64Decode => one_in(vec![], &[("out", Any), ("bytes", Any)]),
        Op::JsonParse => one_in(vec![], &[("out", Any), ("parse_error", Bool)]),
        Op::JsonStringify => one_in(
            vec![param("pretty", Value::Bool(false), true)],
            &[("out", Any)],
        ),
        _ => one_in(vec![], &[("out", Any)]),
    }
}

/// A text result within [`MAX_TEXT`], else `null` and `bad`.
fn bounded(s: String) -> (Value, bool) {
    if s.len() > MAX_TEXT {
        (Value::Null, true)
    } else {
        (Value::Str(s), false)
    }
}

/// The input as text, `None` for `null`; a text past [`MAX_TEXT`] is `Err` (null and bad).
fn input_text(v: &Value) -> Result<Option<String>, ()> {
    match v {
        Value::Null => Ok(None),
        Value::Str(s) if s.len() <= MAX_TEXT => Ok(Some(s.clone())),
        Value::Str(_) => Err(()),
        v => bounded_text(v).map(Some).ok_or(()),
    }
}

pub(super) fn calc(op: Op, v: &View) -> Outs {
    let one = |(val, bad): (Value, bool)| vec![("out", val, bad)];
    let nul = vec![("out", Value::Null, false)];
    match op {
        Op::Left | Op::Right => {
            let Ok(Some(s)) = input_text(v.inv) else {
                return if matches!(input_text(v.inv), Err(())) {
                    one((Value::Null, true))
                } else {
                    nul
                };
            };
            let k = num(v.p("length")).map_or(0, |n| {
                let x = n.f();
                if x < 0.0 {
                    0
                } else {
                    x.min(MAX_TEXT as f64) as usize
                }
            });
            let n = s.chars().count();
            let part: String = if op == Op::Left {
                s.chars().take(k).collect()
            } else {
                s.chars().skip(n.saturating_sub(k)).collect()
            };
            one(bounded(part))
        }
        Op::Trim => match input_text(v.inv) {
            Ok(s) => one(bounded(s.unwrap_or_default().trim().to_owned())),
            Err(()) => one((Value::Null, true)),
        },
        Op::Base64Encode => match v.inv {
            Value::Str(s) => one(bounded(b64(s.as_bytes()))),
            Value::Bytes(b) => one(bounded(b64(b))),
            _ => nul,
        },
        Op::Base64Decode => {
            let bytes = match v.inv {
                Value::Str(s) if s.len() <= MAX_JSON => unb64(s),
                _ => None,
            };
            match bytes {
                None => vec![("out", Value::Null, false), ("bytes", Value::Null, false)],
                Some(b) => {
                    let (t, bad) = bounded(String::from_utf8_lossy(&b).into_owned());
                    let bb = b.len() > MAX_TEXT;
                    vec![
                        ("out", t, bad),
                        ("bytes", if bb { Value::Null } else { Value::Bytes(b) }, bb),
                    ]
                }
            }
        }
        Op::UrlEncode => match v.inv {
            Value::Str(s) => one(bounded(url_encode(s))),
            _ => nul,
        },
        Op::UrlDecode => match v.inv {
            Value::Str(s) => one(bounded(url_decode(s))),
            _ => nul,
        },
        Op::ToCamelCase => match v.inv {
            Value::Str(s) => one(bounded(to_camel_case(s))),
            _ => nul,
        },
        Op::FromCamelCase => match v.inv {
            Value::Str(s) => one(bounded(from_camel_case(s))),
            _ => nul,
        },
        Op::Hash => {
            let alg = match v.p("algorithm") {
                Value::Str(a) if HASHES.contains(&a.as_str()) => a.as_str(),
                _ => return nul,
            };
            let data: &[u8] = match v.inv {
                Value::Str(s) => s.as_bytes(),
                Value::Bytes(b) => b,
                _ => return nul,
            };
            if data.len() > MAX_JSON {
                return one((Value::Null, true));
            }
            one((Value::Str(digest(alg, data)), false))
        }
        Op::JsonParse => match v.inv {
            Value::Str(s) => match parse_json(s) {
                Ok(val) => vec![
                    ("out", val, false),
                    ("parse_error", Value::Bool(false), false),
                ],
                Err(()) => vec![
                    ("out", Value::Null, false),
                    ("parse_error", Value::Bool(true), false),
                ],
            },
            // a value that is no text is already parsed
            Value::Null => vec![
                ("out", Value::Null, false),
                ("parse_error", Value::Bool(false), false),
            ],
            other => vec![
                ("out", other.clone(), false),
                ("parse_error", Value::Bool(false), false),
            ],
        },
        Op::JsonStringify => {
            let pretty = super::truth(v.p("pretty"), false);
            match stringify(v.inv, pretty) {
                Some(s) => one((Value::Str(s), false)),
                None => one((Value::Null, true)),
            }
        }
    }
}

fn b64(b: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(b)
}

/// Base64 in the standard or the URL alphabet, with or without padding.
pub(super) fn unb64(s: &str) -> Option<Vec<u8>> {
    use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD, URL_SAFE, URL_SAFE_NO_PAD};
    let s = s.trim();
    [STANDARD, STANDARD_NO_PAD, URL_SAFE, URL_SAFE_NO_PAD]
        .iter()
        .find_map(|e| e.decode(s).ok())
}

/// `encodeURIComponent`: UTF-8 percent-encoded except `A-Za-z0-9-_.!~*'()`.
pub(super) fn url_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.!~*'()".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The URL decoder: `+` is a space, `%XX` a byte, a bad or cut `%` stays as it is;
/// the bytes as UTF-8 (a malformed sequence becomes U+FFFD).
pub(super) fn url_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'+' => out.push(b' '),
            b'%' => {
                let hex = b
                    .get(i + 1..i + 3)
                    .and_then(|h| std::str::from_utf8(h).ok());
                match hex.and_then(|h| u8::from_str_radix(h, 16).ok()) {
                    Some(x) => {
                        out.push(x);
                        i += 2;
                    }
                    None => out.push(b'%'),
                }
            }
            c => out.push(c),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Camel case: only `A-Za-z0-9_- ` kept, leading `_` and digits dropped,
/// lower case, a letter after spaces or dashes upper case, a letter after a digit upper case.
pub(super) fn to_camel_case(s: &str) -> String {
    let kept: String = s
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | ' '))
        .collect();
    let kept = kept.trim_start_matches(|c: char| c == '_' || c.is_ascii_digit());
    let low = kept.trim().to_ascii_lowercase();
    let mut out = String::with_capacity(low.len());
    let mut up = false;
    let mut prev_digit = false;
    for c in low.chars() {
        if c == ' ' || c == '-' {
            up = true;
            continue;
        }
        if up {
            out.extend(c.to_uppercase());
            up = false;
        } else if prev_digit && c.is_ascii_lowercase() {
            out.push(c.to_ascii_uppercase());
        } else {
            out.push(c);
        }
        prev_digit = c.is_ascii_digit();
    }
    out
}

/// Each capital `X` becomes ` x` (`HelloWorld` → ` hello world`, with the leading space).
pub(super) fn from_camel_case(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 8);
    for c in s.chars() {
        if c.is_ascii_uppercase() {
            out.push(' ');
            out.push(c.to_ascii_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}

fn digest(alg: &str, data: &[u8]) -> String {
    use sha2::Digest as _;
    match alg {
        "sha1" => hex::encode(sha1::Sha1::digest(data)),
        "md5" => hex::encode(md5(data)),
        _ => hex::encode(sha2::Sha256::digest(data)),
    }
}

/// MD5 (RFC 1321): only for `hash` (a check sum some devices and services ask for, not a
/// secret).
pub(super) fn md5(data: &[u8]) -> [u8; 16] {
    const S: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5,
        9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10,
        15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    let k: Vec<u32> = (0..64)
        .map(|i| ((i as f64 + 1.0).sin().abs() * 4_294_967_296.0) as u32)
        .collect();
    let mut h: [u32; 4] = [0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476];
    let mut msg = data.to_vec();
    let bits = (data.len() as u64).wrapping_mul(8);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bits.to_le_bytes());
    for chunk in msg.as_chunks::<64>().0 {
        let m: Vec<u32> = chunk
            .as_chunks::<4>()
            .0
            .iter()
            .map(|w| u32::from_le_bytes(*w))
            .collect();
        let [mut a, mut b, mut c, mut d] = h;
        for i in 0..64 {
            let (f, g) = match i / 16 {
                0 => ((b & c) | (!b & d), i),
                1 => ((d & b) | (!d & c), (5 * i + 1) % 16),
                2 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | !d), (7 * i) % 16),
            };
            let f = f.wrapping_add(a).wrapping_add(k[i]).wrapping_add(m[g]);
            a = d;
            d = c;
            c = b;
            b = b.wrapping_add(f.rotate_left(S[i]));
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
    }
    let mut out = [0u8; 16];
    for (i, w) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&w.to_le_bytes());
    }
    out
}

/// A JSON text as a value: at most [`MAX_JSON`] bytes and 32 levels deep (spec README rule 6).
pub fn parse_json(s: &str) -> Result<Value, ()> {
    if s.len() > MAX_JSON {
        return Err(());
    }
    let j: serde_json::Value = serde_json::from_str(s.trim()).map_err(|_| ())?;
    from_json(&j, 0)
}

fn from_json(j: &serde_json::Value, depth: usize) -> Result<Value, ()> {
    use serde_json::Value as J;
    if depth > wyrm_core::value::MAX_DEPTH {
        return Err(());
    }
    Ok(match j {
        J::Null => Value::Null,
        J::Bool(b) => Value::Bool(*b),
        J::Number(n) => {
            if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else if let Some(u) = n.as_u64() {
                Value::UInt(u)
            } else {
                n.as_f64().map_or(Value::Null, |x| N::F(x).value())
            }
        }
        J::String(s) => Value::Str(s.clone()),
        J::Array(a) => Value::Array(
            a.iter()
                .map(|x| from_json(x, depth + 1))
                .collect::<Result<_, _>>()?,
        ),
        J::Object(o) => Value::Map(
            o.iter()
                .map(|(k, x)| Ok((k.clone(), from_json(x, depth + 1)?)))
                .collect::<Result<BTreeMap<_, _>, ()>>()?,
        ),
    })
}

/// A value as JSON: bytes as Base64 text; `None` when the text would pass [`MAX_JSON`].
pub fn stringify(v: &Value, pretty: bool) -> Option<String> {
    let j = to_json(v);
    let s = if pretty {
        serde_json::to_string_pretty(&j).ok()?
    } else {
        serde_json::to_string(&j).ok()?
    };
    (s.len() <= MAX_JSON).then_some(s)
}

pub(super) fn to_json(v: &Value) -> serde_json::Value {
    use serde_json::Value as J;
    match v {
        Value::Null => J::Null,
        Value::Bool(b) => J::Bool(*b),
        Value::Int(n) => J::from(*n),
        Value::UInt(n) => J::from(*n),
        Value::Float(f) => serde_json::Number::from_f64(*f).map_or(J::Null, J::Number),
        Value::Str(s) => J::String(s.clone()),
        Value::Bytes(b) => J::String(b64(b)),
        Value::Array(a) => J::Array(a.iter().map(to_json).collect()),
        Value::Map(m) => J::Object(m.iter().map(|(k, x)| (k.clone(), to_json(x))).collect()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(op: Op, x: Value, kv: &[(&str, Value)]) -> Vec<(&'static str, Value, bool)> {
        let params: BTreeMap<String, Value> = shape(op)
            .params
            .into_iter()
            .map(|p| (p.name.to_owned(), p.default))
            .chain(kv.iter().map(|(k, v)| ((*k).to_owned(), v.clone())))
            .collect();
        calc(
            op,
            &View {
                inv: &x,
                params: &params,
                items: Vec::new(),
                now_us: 0,
                ins: &super::super::NO_INPUTS,
            },
        )
    }

    fn out(op: Op, x: impl Into<Value>, kv: &[(&str, Value)]) -> Value {
        run(op, x.into(), kv).remove(0).1
    }

    #[test]
    fn left_right_trim() {
        assert_eq!(
            out(Op::Left, "hello", &[("length", Value::Int(2))]),
            "he".into()
        );
        assert_eq!(
            out(Op::Right, "hello", &[("length", Value::Int(3))]),
            "llo".into()
        );
        assert_eq!(
            out(Op::Right, "hé", &[("length", Value::Int(9))]),
            "hé".into()
        );
        assert_eq!(out(Op::Left, "hello", &[]), "".into(), "no length: empty");
        assert_eq!(
            out(Op::Left, "hello", &[("length", Value::Int(-1))]),
            "".into()
        );
        assert_eq!(
            out(Op::Left, Value::Null, &[("length", Value::Int(2))]),
            Value::Null
        );
        assert_eq!(
            out(Op::Left, 12345u64, &[("length", Value::Int(2))]),
            "12".into()
        );
        assert_eq!(out(Op::Trim, "  x ", &[]), "x".into());
        assert_eq!(
            out(Op::Trim, Value::Null, &[]),
            "".into(),
            "null trims to empty text"
        );
        let r = run(Op::Trim, "x".repeat(MAX_TEXT + 1).into(), &[]);
        assert_eq!((r[0].1.clone(), r[0].2), (Value::Null, true));
    }

    #[test]
    fn codecs() {
        assert_eq!(out(Op::Base64Encode, "hi", &[]), "aGk=".into());
        assert_eq!(
            out(Op::Base64Encode, Value::Bytes(vec![0, 255]), &[]),
            "AP8=".into()
        );
        assert_eq!(
            out(Op::Base64Encode, 5u64, &[]),
            Value::Null,
            "only text and bytes"
        );
        let r = run(Op::Base64Decode, "aGk=".into(), &[]);
        assert_eq!(r[0].1, "hi".into());
        assert_eq!(r[1].1, Value::Bytes(b"hi".to_vec()));
        assert_eq!(out(Op::Base64Decode, "aGk", &[]), "hi".into(), "no padding");
        assert_eq!(out(Op::Base64Decode, "%%%", &[]), Value::Null);
        assert_eq!(
            out(Op::UrlEncode, "a b&c=ü", &[]),
            "a%20b%26c%3D%C3%BC".into()
        );
        assert_eq!(out(Op::UrlEncode, "-_.!~*'()", &[]), "-_.!~*'()".into());
        assert_eq!(out(Op::UrlDecode, "a+b", &[]), "a b".into());
        assert_eq!(out(Op::UrlDecode, "100%", &[]), "100%".into());
        assert_eq!(out(Op::UrlDecode, "%C3%BC%2", &[]), "ü%2".into());
        assert_eq!(out(Op::UrlDecode, "%zz%41", &[]), "%zzA".into());
        assert_eq!(
            out(Op::ToCamelCase, "Hello World-foo", &[]),
            "helloWorldFoo".into()
        );
        assert_eq!(out(Op::ToCamelCase, "abc 2nd", &[]), "abc2Nd".into());
        assert_eq!(out(Op::ToCamelCase, "_12 go!", &[]), "go".into());
        assert_eq!(
            out(Op::FromCamelCase, "HelloWorld", &[]),
            " hello world".into()
        );
    }

    #[test]
    fn hashes() {
        assert_eq!(
            out(Op::Hash, "abc", &[("algorithm", "md5".into())]),
            "900150983cd24fb0d6963f7d28e17f72".into()
        );
        assert_eq!(
            out(Op::Hash, "", &[("algorithm", "md5".into())]),
            "d41d8cd98f00b204e9800998ecf8427e".into()
        );
        let long = "a".repeat(1000);
        assert_eq!(
            hex::encode(md5(long.as_bytes())),
            "cabe45dcc9ae5b66ba86600cca6b8ba8"
        );
        assert_eq!(
            out(Op::Hash, "abc", &[("algorithm", "sha1".into())]),
            "a9993e364706816aba3e25717850c26c9cd0d89d".into()
        );
        assert_eq!(
            out(Op::Hash, "abc", &[]),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad".into()
        );
        assert_eq!(
            out(Op::Hash, "abc", &[("algorithm", "crc".into())]),
            Value::Null
        );
    }

    #[test]
    fn json() {
        let r = run(
            Op::JsonParse,
            r#"{"t": 21.5, "a": [1, -2, true, null]}"#.into(),
            &[],
        );
        let Value::Map(m) = &r[0].1 else {
            panic!("{r:?}")
        };
        assert_eq!(m.get("t"), Some(&Value::Float(21.5)));
        assert_eq!(r[1].1, Value::Bool(false));
        let r = run(Op::JsonParse, "{".into(), &[]);
        assert_eq!(
            (r[0].1.clone(), r[1].1.clone()),
            (Value::Null, Value::Bool(true))
        );
        let deep = format!("{}{}", "[".repeat(40), "]".repeat(40));
        assert_eq!(run(Op::JsonParse, deep.into(), &[])[1].1, Value::Bool(true));
        assert_eq!(
            out(
                Op::JsonStringify,
                Value::Map(BTreeMap::from([("a".into(), Value::Int(1))])),
                &[]
            ),
            r#"{"a":1}"#.into()
        );
        assert_eq!(
            out(Op::JsonStringify, Value::Bytes(vec![1]), &[]),
            r#""AQ==""#.into()
        );
        let big = Value::Str("x".repeat(MAX_JSON));
        let r = run(Op::JsonStringify, big, &[]);
        assert_eq!((r[0].1.clone(), r[0].2), (Value::Null, true));
    }
}
