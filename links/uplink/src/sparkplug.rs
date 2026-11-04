//! Sparkplug B 3.0 payloads (Eclipse Tahu `sparkplug_b.proto`, EPL-2.0, not vendored): the part
//! an edge node sends, encoded by a protobuf writer of ours (no `protoc`, no `prost`), and the
//! part it reads from `NCMD`/`DCMD` (metric names and booleans: `Node Control/Rebirth`).
//!
//! `Payload { 1: timestamp, 2: metrics, 3: seq }`, `Metric { 1: name, 3: timestamp, 4: datatype,
//! 7: is_null, 11: long_value, 13: double_value, 14: boolean_value, 15: string_value,
//! 16: bytes_value }`. Every number is a Double, so a metric's type never changes between an
//! integer and a float (a host refuses a DATA metric whose type is not the BIRTH's).

use wyrm_core::Value;

pub const NAMESPACE: &str = "spBv1.0";
pub const BDSEQ: &str = "bdSeq";
pub const REBIRTH: &str = "Node Control/Rebirth";
pub const DEVICE_REBIRTH: &str = "Device Control/Rebirth";

/// Sparkplug data type codes (proto enum `DataType`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DataType {
    Int64 = 4,
    Double = 10,
    Boolean = 11,
    String = 12,
    Bytes = 17,
}

impl DataType {
    /// The type a value is sent as; `None` for a null (the type of the last value stays).
    pub fn of(v: &Value) -> Option<Self> {
        match v {
            Value::Null => None,
            Value::Bool(_) => Some(DataType::Boolean),
            Value::Int(_) | Value::UInt(_) | Value::Float(_) => Some(DataType::Double),
            Value::Str(_) => Some(DataType::String),
            Value::Bytes(_) => Some(DataType::Bytes),
            _ => Some(DataType::String),
        }
    }
}

fn varint(out: &mut Vec<u8>, mut v: u64) {
    loop {
        let b = (v & 0x7f) as u8;
        v >>= 7;
        if v == 0 {
            out.push(b);
            return;
        }
        out.push(b | 0x80);
    }
}

fn key(out: &mut Vec<u8>, field: u32, wire: u8) {
    varint(out, (u64::from(field) << 3) | u64::from(wire));
}

fn uint(out: &mut Vec<u8>, field: u32, v: u64) {
    key(out, field, 0);
    varint(out, v);
}

fn bytes(out: &mut Vec<u8>, field: u32, b: &[u8]) {
    key(out, field, 2);
    varint(out, b.len() as u64);
    out.extend(b);
}

fn double(out: &mut Vec<u8>, field: u32, f: f64) {
    key(out, field, 1);
    out.extend(f.to_le_bytes());
}

/// One metric of a payload.
pub struct Metric<'a> {
    pub name: &'a str,
    /// UTC milliseconds.
    pub t_ms: u64,
    pub value: &'a Value,
    /// The type last sent for it (a null keeps it); `None` when the value tells.
    pub datatype: Option<DataType>,
    /// BIRTH sends the type; DATA may leave it out (the host knows it from the BIRTH).
    pub with_type: bool,
}

fn number(v: &Value) -> Option<f64> {
    match v {
        Value::Int(i) => Some(*i as f64),
        Value::UInt(u) => Some(*u as f64),
        Value::Float(f) => Some(*f),
        _ => None,
    }
}

/// A value that line protocols and JSON cannot hold (a map, an array) as text.
pub fn text_of(v: &Value) -> String {
    match v {
        Value::Str(s) => s.clone(),
        other => crate::platform::json_value(other).to_string(),
    }
}

fn metric(out: &mut Vec<u8>, m: &Metric<'_>) {
    let mut b = Vec::new();
    bytes(&mut b, 1, m.name.as_bytes());
    uint(&mut b, 3, m.t_ms);
    let dt = DataType::of(m.value).or(m.datatype);
    if m.with_type {
        if let Some(dt) = dt {
            uint(&mut b, 4, dt as u64);
        }
    }
    match m.value {
        Value::Null => uint(&mut b, 7, 1),
        Value::Bool(x) => uint(&mut b, 14, u64::from(*x)),
        v if number(v).is_some() => {
            let f = number(v).unwrap_or(0.0);
            double(&mut b, 13, if f.is_finite() { f } else { 0.0 });
        }
        Value::Bytes(x) => bytes(&mut b, 16, x),
        other => bytes(&mut b, 15, text_of(other).as_bytes()),
    }
    bytes(out, 2, &b);
}

/// A payload: `metrics` in order, with `bd_seq` first when given (BIRTH and DEATH), `seq` when
/// given (every message but NDEATH).
pub fn payload(
    t_ms: u64,
    seq: Option<u64>,
    bd_seq: Option<u64>,
    metrics: &[Metric<'_>],
) -> Vec<u8> {
    let mut out = Vec::new();
    uint(&mut out, 1, t_ms);
    if let Some(bd) = bd_seq {
        let mut b = Vec::new();
        bytes(&mut b, 1, BDSEQ.as_bytes());
        uint(&mut b, 3, t_ms);
        uint(&mut b, 4, DataType::Int64 as u64);
        uint(&mut b, 11, bd);
        bytes(&mut out, 2, &b);
    }
    for m in metrics {
        metric(&mut out, m);
    }
    if let Some(s) = seq {
        uint(&mut out, 3, s);
    }
    out
}

/// A varint read: `(value, bytes)`.
fn read_varint(b: &[u8]) -> Option<(u64, usize)> {
    let mut v = 0u64;
    for (i, x) in b.iter().take(10).enumerate() {
        v |= u64::from(x & 0x7f) << (7 * i);
        if x & 0x80 == 0 {
            return Some((v, i + 1));
        }
    }
    None
}

/// Fields of one message: `(field, wire, bytes of the field's value)`; a varint or fixed value
/// comes as its raw bytes.
fn fields(mut b: &[u8]) -> Option<Vec<(u32, u8, &[u8])>> {
    let mut out = Vec::new();
    while !b.is_empty() {
        let (k, n) = read_varint(b)?;
        b = &b[n..];
        let (field, wire) = ((k >> 3) as u32, (k & 7) as u8);
        let (val, rest) = match wire {
            0 => {
                let (_, n) = read_varint(b)?;
                b.split_at(n)
            }
            1 => b.split_at_checked(8)?,
            2 => {
                let (len, n) = read_varint(b)?;
                let rest = &b[n..];
                rest.split_at_checked(usize::try_from(len).ok()?)?
            }
            5 => b.split_at_checked(4)?,
            _ => return None,
        };
        out.push((field, wire, val));
        b = rest;
        if out.len() > 10_000 {
            return None;
        }
    }
    Some(out)
}

/// The metrics of a command payload: `(name, boolean value)`; a metric without a name or a
/// boolean is left out. `None` when the bytes are not a payload.
pub fn command_metrics(b: &[u8]) -> Option<Vec<(String, bool)>> {
    let mut out = Vec::new();
    for (field, wire, val) in fields(b)? {
        if field != 2 || wire != 2 {
            continue;
        }
        let (mut name, mut flag) = (None, None);
        for (f, w, v) in fields(val)? {
            match (f, w) {
                (1, 2) => name = std::str::from_utf8(v).ok().map(str::to_owned),
                (14, 0) => flag = read_varint(v).map(|(x, _)| x != 0),
                _ => {}
            }
        }
        if let (Some(n), Some(f)) = (name, flag) {
            out.push((n, f));
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payload_bytes_are_protobuf() {
        let v = Value::Float(1.5);
        let m = [Metric {
            name: "d0/temp",
            t_ms: 1000,
            value: &v,
            datatype: None,
            with_type: true,
        }];
        let p = payload(1000, Some(3), Some(1), &m);
        // 1: timestamp 1000 → 08 e8 07
        assert_eq!(&p[..3], &[0x08, 0xe8, 0x07]);
        // the bdSeq metric comes first, as a message of field 2
        assert_eq!(p[3], 0x12);
        // the last field is seq = 3
        assert_eq!(&p[p.len() - 2..], &[0x18, 3]);
        let names: Vec<String> = fields(&p)
            .unwrap()
            .into_iter()
            .filter(|(f, _, _)| *f == 2)
            .filter_map(|(_, _, v)| {
                fields(v)?
                    .into_iter()
                    .find(|(f, _, _)| *f == 1)
                    .map(|(_, _, n)| String::from_utf8_lossy(n).into_owned())
            })
            .collect();
        assert_eq!(names, ["bdSeq", "d0/temp"]);
    }

    #[test]
    fn rebirth_command_is_read() {
        let t = Value::Bool(true);
        let m = [Metric {
            name: REBIRTH,
            t_ms: 1,
            value: &t,
            datatype: None,
            with_type: true,
        }];
        let p = payload(1, Some(0), None, &m);
        assert_eq!(command_metrics(&p).unwrap(), [(REBIRTH.to_owned(), true)]);
        assert_eq!(command_metrics(&[0xff, 0xff]), None);
        assert_eq!(DataType::of(&Value::UInt(1)), Some(DataType::Double));
        assert_eq!(DataType::of(&Value::Null), None);
    }
}
