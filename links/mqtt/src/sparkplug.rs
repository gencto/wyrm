//! Sparkplug B: the subset of `Payload` (Eclipse Tahu `sparkplug_b.proto`,
//! https://github.com/eclipse/tahu/blob/master/sparkplug_b/sparkplug_b.proto,
//! EPL-2.0, not vendored here) this driver reads and writes, hand-written for
//! prost so the build needs no `protoc`. Fields left out (metadata,
//! properties, datasets, templates, extensions) are skipped by the decoder.
//!
//! [`State`] follows edge nodes and devices: BIRTH records metric names,
//! aliases and data types; DATA updates by name or alias; NDEATH (with a
//! matching `bdSeq`) takes the node and all its devices offline; DDEATH one
//! device.

use std::collections::HashMap;
use std::time::{Duration, Instant};
use wyrm_core::Value;

pub const NAMESPACE: &str = "spBv1.0";
pub const REBIRTH: &str = "Node Control/Rebirth";
pub const BDSEQ: &str = "bdSeq";
/// At most one rebirth request per edge node in this period.
pub const REBIRTH_PERIOD: Duration = Duration::from_secs(5);

#[derive(Clone, PartialEq, prost::Message)]
pub struct Payload {
    #[prost(uint64, optional, tag = "1")]
    pub timestamp: Option<u64>,
    #[prost(message, repeated, tag = "2")]
    pub metrics: Vec<Metric>,
    #[prost(uint64, optional, tag = "3")]
    pub seq: Option<u64>,
    #[prost(string, optional, tag = "4")]
    pub uuid: Option<String>,
    #[prost(bytes = "vec", optional, tag = "5")]
    pub body: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct Metric {
    #[prost(string, optional, tag = "1")]
    pub name: Option<String>,
    #[prost(uint64, optional, tag = "2")]
    pub alias: Option<u64>,
    #[prost(uint64, optional, tag = "3")]
    pub timestamp: Option<u64>,
    #[prost(uint32, optional, tag = "4")]
    pub datatype: Option<u32>,
    #[prost(bool, optional, tag = "5")]
    pub is_historical: Option<bool>,
    #[prost(bool, optional, tag = "6")]
    pub is_transient: Option<bool>,
    #[prost(bool, optional, tag = "7")]
    pub is_null: Option<bool>,
    #[prost(oneof = "MetricValue", tags = "10, 11, 12, 13, 14, 15, 16")]
    pub value: Option<MetricValue>,
}

#[derive(Clone, PartialEq, prost::Oneof)]
pub enum MetricValue {
    #[prost(uint32, tag = "10")]
    Int(u32),
    #[prost(uint64, tag = "11")]
    Long(u64),
    #[prost(float, tag = "12")]
    Float(f32),
    #[prost(double, tag = "13")]
    Double(f64),
    #[prost(bool, tag = "14")]
    Boolean(bool),
    #[prost(string, tag = "15")]
    String(String),
    #[prost(bytes = "vec", tag = "16")]
    Bytes(Vec<u8>),
}

/// Scalar Sparkplug data types (proto enum `DataType`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DataType {
    Int8,
    Int16,
    Int32,
    Int64,
    UInt8,
    UInt16,
    UInt32,
    UInt64,
    Float,
    Double,
    Boolean,
    String,
    DateTime,
    Text,
    Uuid,
    Bytes,
    File,
}

impl DataType {
    const CODES: [(u32, DataType); 17] = [
        (1, DataType::Int8),
        (2, DataType::Int16),
        (3, DataType::Int32),
        (4, DataType::Int64),
        (5, DataType::UInt8),
        (6, DataType::UInt16),
        (7, DataType::UInt32),
        (8, DataType::UInt64),
        (9, DataType::Float),
        (10, DataType::Double),
        (11, DataType::Boolean),
        (12, DataType::String),
        (13, DataType::DateTime),
        (14, DataType::Text),
        (15, DataType::Uuid),
        (17, DataType::Bytes),
        (18, DataType::File),
    ];

    /// `None` for unknown, array, dataset, template and property types.
    pub fn from_code(c: u32) -> Option<Self> {
        Self::CODES.iter().find(|(k, _)| *k == c).map(|(_, d)| *d)
    }

    pub fn code(self) -> u32 {
        Self::CODES
            .iter()
            .find(|(_, d)| *d == self)
            .map(|(k, _)| *k)
            .unwrap_or(0)
    }

    /// Type for a written value when no BIRTH told it.
    pub fn infer(v: &Value) -> Option<Self> {
        Some(match v {
            Value::Bool(_) => DataType::Boolean,
            Value::Int(_) => DataType::Int64,
            Value::UInt(_) => DataType::UInt64,
            Value::Float(_) => DataType::Double,
            Value::Str(_) => DataType::String,
            Value::Bytes(_) => DataType::Bytes,
            _ => return None,
        })
    }
}

/// Decode a metric value. Signed types arrive two's complement in the
/// unsigned `int_value`/`long_value`; the low bits are reinterpreted.
pub fn metric_value(dt: Option<DataType>, m: &Metric) -> Result<Value, String> {
    use DataType as D;
    use MetricValue as M;
    if m.is_null == Some(true) {
        return Ok(Value::Null);
    }
    let Some(v) = &m.value else {
        return Ok(Value::Null);
    };
    Ok(match (dt, v) {
        (Some(D::Int8), M::Int(x)) => Value::from(i64::from(*x as u8 as i8)),
        (Some(D::Int16), M::Int(x)) => Value::from(i64::from(*x as u16 as i16)),
        (Some(D::Int32), M::Int(x)) => Value::from(i64::from(*x as i32)),
        (Some(D::Int64), M::Long(x)) => Value::from(*x as i64),
        (_, M::Int(x)) => Value::UInt(u64::from(*x)),
        (_, M::Long(x)) => Value::UInt(*x),
        (_, M::Float(f)) => Value::Float(f64::from(*f)),
        (_, M::Double(f)) => Value::Float(*f),
        (_, M::Boolean(b)) => Value::Bool(*b),
        (_, M::String(s)) => Value::Str(s.clone()),
        (_, M::Bytes(b)) => Value::Bytes(b.clone()),
    })
}

fn int_in(v: &Value, min: i64, max: i64) -> Result<i64, String> {
    let i = match v {
        Value::Int(i) => *i,
        Value::UInt(u) => i64::try_from(*u).map_err(|_| "value out of range")?,
        Value::Float(f) if f.fract() == 0.0 && f.is_finite() => *f as i64,
        _ => return Err("expected an integer".into()),
    };
    if i < min || i > max {
        return Err(format!("{i} is out of range {min}..={max}"));
    }
    Ok(i)
}

fn uint_in(v: &Value, max: u64) -> Result<u64, String> {
    let u = match v {
        Value::UInt(u) => *u,
        Value::Int(i) => u64::try_from(*i).map_err(|_| "value out of range")?,
        Value::Float(f) if f.fract() == 0.0 && *f >= 0.0 && f.is_finite() => *f as u64,
        _ => return Err("expected an unsigned integer".into()),
    };
    if u > max {
        return Err(format!("{u} is out of range 0..={max}"));
    }
    Ok(u)
}

/// Encode a written value for `dt`.
pub fn encode_value(dt: DataType, v: &Value) -> Result<MetricValue, String> {
    use DataType as D;
    use MetricValue as M;
    Ok(match dt {
        D::Int8 => M::Int(int_in(v, i8::MIN.into(), i8::MAX.into())? as i32 as u32),
        D::Int16 => M::Int(int_in(v, i16::MIN.into(), i16::MAX.into())? as i32 as u32),
        D::Int32 => M::Int(int_in(v, i32::MIN.into(), i32::MAX.into())? as i32 as u32),
        D::Int64 => M::Long(int_in(v, i64::MIN, i64::MAX)? as u64),
        D::UInt8 => M::Int(uint_in(v, u8::MAX.into())? as u32),
        D::UInt16 => M::Int(uint_in(v, u16::MAX.into())? as u32),
        D::UInt32 => M::Int(uint_in(v, u32::MAX.into())? as u32),
        D::UInt64 | D::DateTime => M::Long(uint_in(v, u64::MAX)?),
        D::Float => M::Float(v.as_f64().ok_or("expected a number")? as f32),
        D::Double => M::Double(v.as_f64().ok_or("expected a number")?),
        D::Boolean => match v {
            Value::Bool(b) => M::Boolean(*b),
            _ => return Err("expected true or false".into()),
        },
        D::String | D::Text | D::Uuid => match v {
            Value::Str(s) => M::String(s.clone()),
            _ => return Err("expected a string".into()),
        },
        D::Bytes | D::File => match v {
            Value::Bytes(b) => M::Bytes(b.clone()),
            _ => return Err("expected bytes".into()),
        },
    })
}

/// One command metric (NCMD/DCMD) with `dt` from BIRTH or inferred.
pub fn command(
    name: &str,
    dt: Option<DataType>,
    v: &Value,
    now_ms: u64,
) -> Result<Payload, String> {
    let dt = dt
        .or_else(|| DataType::infer(v))
        .ok_or("value type cannot be written")?;
    Ok(Payload {
        timestamp: Some(now_ms),
        metrics: vec![Metric {
            name: Some(name.to_owned()),
            timestamp: Some(now_ms),
            datatype: Some(dt.code()),
            value: Some(encode_value(dt, v)?),
            ..Default::default()
        }],
        ..Default::default()
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MsgType {
    NBirth,
    NDeath,
    NData,
    NCmd,
    DBirth,
    DDeath,
    DData,
    DCmd,
}

impl MsgType {
    fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "NBIRTH" => MsgType::NBirth,
            "NDEATH" => MsgType::NDeath,
            "NDATA" => MsgType::NData,
            "NCMD" => MsgType::NCmd,
            "DBIRTH" => MsgType::DBirth,
            "DDEATH" => MsgType::DDeath,
            "DDATA" => MsgType::DData,
            "DCMD" => MsgType::DCmd,
            _ => return None,
        })
    }
}

/// `spBv1.0/<group>/<type>/<edge>[/<device>]`.
#[derive(Debug, PartialEq, Eq)]
pub struct Topic<'a> {
    pub group: &'a str,
    pub kind: MsgType,
    pub edge: &'a str,
    pub device: Option<&'a str>,
}

pub fn parse_topic(t: &str) -> Option<Topic<'_>> {
    let mut it = t.split('/');
    if it.next()? != NAMESPACE {
        return None;
    }
    let group = it.next()?;
    let kind = MsgType::parse(it.next()?)?;
    let edge = it.next()?;
    let device = it.next();
    if it.next().is_some() {
        return None;
    }
    let is_device = matches!(
        kind,
        MsgType::DBirth | MsgType::DDeath | MsgType::DData | MsgType::DCmd
    );
    (is_device == device.is_some()).then_some(Topic {
        group,
        kind,
        edge,
        device,
    })
}

/// Subscription filter for one edge node and all its devices (`#` also
/// matches the node-level topic).
pub fn edge_filter(group: &str, edge: &str) -> String {
    format!("{NAMESPACE}/{group}/+/{edge}/#")
}

/// NCMD or DCMD topic.
pub fn cmd_topic(group: &str, edge: &str, device: &str) -> String {
    if device.is_empty() {
        format!("{NAMESPACE}/{group}/NCMD/{edge}")
    } else {
        format!("{NAMESPACE}/{group}/DCMD/{edge}/{device}")
    }
}

/// Metrics of one edge node or device.
#[derive(Debug, Default)]
struct Entity {
    born: bool,
    dead: bool,
    values: HashMap<String, Value>,
    types: HashMap<String, DataType>,
    aliases: HashMap<u64, String>,
}

impl Entity {
    fn birth(&mut self, metrics: &[Metric]) {
        *self = Entity {
            born: true,
            ..Default::default()
        };
        for m in metrics {
            let Some(name) = &m.name else { continue };
            if let Some(a) = m.alias {
                self.aliases.insert(a, name.clone());
            }
            let dt = m.datatype.and_then(DataType::from_code);
            if let Some(dt) = dt {
                self.types.insert(name.clone(), dt);
            }
            if let Ok(v) = metric_value(dt, m) {
                self.values.insert(name.clone(), v);
            }
        }
    }

    /// Returns `true` when a metric could not be resolved (no BIRTH seen).
    fn data(&mut self, metrics: &[Metric]) -> bool {
        let mut unknown = !self.born;
        for m in metrics {
            if m.is_historical == Some(true) {
                continue;
            }
            let name = match (&m.name, m.alias) {
                (Some(n), _) => n.clone(),
                (None, Some(a)) => match self.aliases.get(&a) {
                    Some(n) => n.clone(),
                    None => {
                        unknown = true;
                        continue;
                    }
                },
                (None, None) => continue,
            };
            let dt = m
                .datatype
                .and_then(DataType::from_code)
                .or_else(|| self.types.get(&name).copied());
            if let Ok(v) = metric_value(dt, m) {
                self.values.insert(name, v);
            }
        }
        unknown
    }

    fn die(&mut self) {
        self.born = false;
        self.dead = true;
    }
}

#[derive(Debug, Default)]
struct Node {
    ent: Entity,
    bdseq: Option<u64>,
    devices: HashMap<String, Entity>,
    last_rebirth: Option<Instant>,
}

fn bdseq(p: &Payload) -> Option<u64> {
    p.metrics
        .iter()
        .find(|m| m.name.as_deref() == Some(BDSEQ))
        .and_then(|m| match m.value {
            Some(MetricValue::Long(v)) => Some(v),
            Some(MetricValue::Int(v)) => Some(v.into()),
            _ => None,
        })
}

/// Sparkplug view of all edge nodes seen on one connection.
#[derive(Debug, Default)]
pub struct State {
    nodes: HashMap<(String, String), Node>,
}

impl State {
    /// Apply one message. Returns `true` when the edge node should be asked
    /// to rebirth (DATA that cannot be mapped), at most once per
    /// [`REBIRTH_PERIOD`].
    pub fn apply(&mut self, t: &Topic<'_>, p: &Payload, now: Instant) -> bool {
        let node = self
            .nodes
            .entry((t.group.to_owned(), t.edge.to_owned()))
            .or_default();
        let unknown = match (t.kind, t.device) {
            (MsgType::NBirth, _) => {
                node.ent.birth(&p.metrics);
                node.bdseq = bdseq(p);
                false
            }
            (MsgType::NDeath, _) => {
                // A death certificate from an older session is stale.
                let stale = matches!((node.bdseq, bdseq(p)), (Some(b), Some(d)) if b != d);
                if !stale {
                    // A new session may be asked to rebirth at once.
                    node.last_rebirth = None;
                    node.ent.die();
                    for d in node.devices.values_mut() {
                        d.die();
                    }
                }
                false
            }
            (MsgType::NData, _) => node.ent.data(&p.metrics),
            (MsgType::DBirth, Some(d)) => {
                node.devices
                    .entry(d.to_owned())
                    .or_default()
                    .birth(&p.metrics);
                false
            }
            (MsgType::DDeath, Some(d)) => {
                node.devices.entry(d.to_owned()).or_default().die();
                false
            }
            (MsgType::DData, Some(d)) => node
                .devices
                .entry(d.to_owned())
                .or_default()
                .data(&p.metrics),
            _ => false,
        };
        if unknown
            && node
                .last_rebirth
                .is_none_or(|l| now.duration_since(l) >= REBIRTH_PERIOD)
        {
            node.last_rebirth = Some(now);
            return true;
        }
        false
    }

    fn entity(&self, group: &str, edge: &str, device: &str) -> Option<&Entity> {
        let n = self.nodes.get(&(group.to_owned(), edge.to_owned()))?;
        if device.is_empty() {
            Some(&n.ent)
        } else {
            n.devices.get(device)
        }
    }

    /// `Err(why)` while the node or device is offline (after its DEATH).
    /// Nothing seen yet is not an error.
    pub fn alive(&self, group: &str, edge: &str, device: &str) -> Result<(), &'static str> {
        let Some(n) = self.nodes.get(&(group.to_owned(), edge.to_owned())) else {
            return Ok(());
        };
        if n.ent.dead {
            return Err("edge node offline (NDEATH)");
        }
        if !device.is_empty() && n.devices.get(device).is_some_and(|d| d.dead) {
            return Err("device offline (DDEATH)");
        }
        Ok(())
    }

    pub fn value(&self, group: &str, edge: &str, device: &str, metric: &str) -> Option<Value> {
        self.entity(group, edge, device)?
            .values
            .get(metric)
            .cloned()
    }

    /// Record a rebirth request sent outside [`apply`](Self::apply), so the
    /// DATA path does not repeat it within [`REBIRTH_PERIOD`].
    pub fn note_rebirth(&mut self, group: &str, edge: &str, now: Instant) {
        self.nodes
            .entry((group.to_owned(), edge.to_owned()))
            .or_default()
            .last_rebirth = Some(now);
    }

    pub fn datatype(
        &self,
        group: &str,
        edge: &str,
        device: &str,
        metric: &str,
    ) -> Option<DataType> {
        self.entity(group, edge, device)?.types.get(metric).copied()
    }
}

/// NCMD asking `edge` to publish its BIRTH certificates again.
pub fn rebirth_request(now_ms: u64) -> Payload {
    Payload {
        timestamp: Some(now_ms),
        metrics: vec![Metric {
            name: Some(REBIRTH.to_owned()),
            timestamp: Some(now_ms),
            datatype: Some(DataType::Boolean.code()),
            value: Some(MetricValue::Boolean(true)),
            ..Default::default()
        }],
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use prost::Message;

    /// Hand-encoded protobuf, independent of the prost structs: checks the
    /// field tags against the Tahu proto.
    fn varint(mut v: u64, out: &mut Vec<u8>) {
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

    fn field(tag: u32, wire: u8, out: &mut Vec<u8>) {
        varint(u64::from(tag << 3 | u32::from(wire)), out);
    }

    fn len_field(tag: u32, body: &[u8], out: &mut Vec<u8>) {
        field(tag, 2, out);
        varint(body.len() as u64, out);
        out.extend_from_slice(body);
    }

    #[test]
    fn wire_tags_match_tahu() {
        // Metric{name="Temp"(1), alias=7(2), datatype=Double(4), double_value=20.5(13)}
        let mut m1 = Vec::new();
        len_field(1, b"Temp", &mut m1);
        field(2, 0, &mut m1);
        varint(7, &mut m1);
        field(4, 0, &mut m1);
        varint(10, &mut m1);
        field(13, 1, &mut m1);
        m1.extend_from_slice(&20.5f64.to_le_bytes());
        // Metric{alias=8, datatype=Int16(2), int_value=0xFFFF_FFF6 (-10), is_null absent}
        let mut m2 = Vec::new();
        field(2, 0, &mut m2);
        varint(8, &mut m2);
        field(4, 0, &mut m2);
        varint(2, &mut m2);
        field(10, 0, &mut m2);
        varint(0xFFFF_FFF6, &mut m2);
        // Payload{timestamp=1(1), metrics(2) x2, seq=3(3)}
        let mut p = Vec::new();
        field(1, 0, &mut p);
        varint(1, &mut p);
        len_field(2, &m1, &mut p);
        len_field(2, &m2, &mut p);
        field(3, 0, &mut p);
        varint(3, &mut p);
        let d = Payload::decode(p.as_slice()).unwrap();
        assert_eq!(d.timestamp, Some(1));
        assert_eq!(d.seq, Some(3));
        assert_eq!(d.metrics[0].name.as_deref(), Some("Temp"));
        assert_eq!(d.metrics[0].alias, Some(7));
        assert_eq!(d.metrics[0].value, Some(MetricValue::Double(20.5)));
        let dt = d.metrics[1].datatype.and_then(DataType::from_code);
        assert_eq!(dt, Some(DataType::Int16));
        assert_eq!(metric_value(dt, &d.metrics[1]), Ok(Value::Int(-10)));
        // and back: prost writes the same bytes
        assert_eq!(d.encode_to_vec(), p);
    }

    #[test]
    fn signed_round_trip() {
        for (dt, v) in [
            (DataType::Int8, Value::Int(-128)),
            (DataType::Int16, Value::Int(-2)),
            (DataType::Int32, Value::Int(i32::MIN.into())),
            (DataType::Int64, Value::Int(i64::MIN)),
            (DataType::UInt32, Value::UInt(u32::MAX.into())),
            (DataType::Float, Value::Float(1.5)),
            (DataType::Boolean, Value::Bool(true)),
            (DataType::String, Value::from("x")),
        ] {
            let m = Metric {
                value: Some(encode_value(dt, &v).unwrap()),
                ..Default::default()
            };
            assert_eq!(metric_value(Some(dt), &m), Ok(v.clone()), "{dt:?}");
        }
        assert!(encode_value(DataType::Int8, &Value::Int(200)).is_err());
        assert!(encode_value(DataType::UInt16, &Value::Int(-1)).is_err());
    }

    fn metric(name: Option<&str>, alias: Option<u64>, dt: DataType, v: MetricValue) -> Metric {
        Metric {
            name: name.map(str::to_owned),
            alias,
            datatype: Some(dt.code()),
            value: Some(v),
            ..Default::default()
        }
    }

    fn payload(metrics: Vec<Metric>) -> Payload {
        Payload {
            metrics,
            ..Default::default()
        }
    }

    #[test]
    fn birth_data_death() {
        let mut s = State::default();
        let now = Instant::now();
        let t = |topic: &'static str| parse_topic(topic).unwrap();
        assert!(
            parse_topic("spBv1.0/g/DDATA/e").is_none(),
            "device type needs a device"
        );
        assert!(parse_topic("spBv1.0/g/NDATA/e/d").is_none());
        assert!(parse_topic("other/g/NDATA/e").is_none());
        // DATA before BIRTH: unmapped alias → rebirth once per period
        let data = payload(vec![metric(
            None,
            Some(1),
            DataType::Double,
            MetricValue::Double(1.0),
        )]);
        assert!(s.apply(&t("spBv1.0/g/NDATA/e"), &data, now));
        assert!(!s.apply(&t("spBv1.0/g/NDATA/e"), &data, now));
        let birth = payload(vec![
            metric(Some(BDSEQ), None, DataType::UInt64, MetricValue::Long(4)),
            metric(
                Some("Temp"),
                Some(1),
                DataType::Double,
                MetricValue::Double(20.5),
            ),
        ]);
        assert!(!s.apply(&t("spBv1.0/g/NBIRTH/e"), &birth, now));
        assert_eq!(s.value("g", "e", "", "Temp"), Some(Value::Float(20.5)));
        let data = payload(vec![metric(
            None,
            Some(1),
            DataType::Double,
            MetricValue::Double(21.0),
        )]);
        assert!(!s.apply(&t("spBv1.0/g/NDATA/e"), &data, now));
        assert_eq!(s.value("g", "e", "", "Temp"), Some(Value::Float(21.0)));
        let dbirth = payload(vec![metric(
            Some("Run"),
            Some(2),
            DataType::Boolean,
            MetricValue::Boolean(true),
        )]);
        s.apply(&t("spBv1.0/g/DBIRTH/e/d1"), &dbirth, now);
        assert_eq!(s.value("g", "e", "d1", "Run"), Some(Value::Bool(true)));
        assert_eq!(s.datatype("g", "e", "d1", "Run"), Some(DataType::Boolean));
        s.apply(&t("spBv1.0/g/DDEATH/e/d1"), &payload(vec![]), now);
        assert!(s.alive("g", "e", "d1").is_err());
        assert!(s.alive("g", "e", "").is_ok());
        // NDEATH of an older session (bdSeq 3) is ignored
        let old = payload(vec![metric(
            Some(BDSEQ),
            None,
            DataType::UInt64,
            MetricValue::Long(3),
        )]);
        s.apply(&t("spBv1.0/g/NDEATH/e"), &old, now);
        assert!(s.alive("g", "e", "").is_ok());
        let death = payload(vec![metric(
            Some(BDSEQ),
            None,
            DataType::UInt64,
            MetricValue::Long(4),
        )]);
        s.apply(&t("spBv1.0/g/NDEATH/e"), &death, now);
        assert_eq!(s.alive("g", "e", ""), Err("edge node offline (NDEATH)"));
        assert!(s.alive("g", "e", "d1").is_err());
        assert!(
            s.alive("g", "other", "").is_ok(),
            "unknown node: no verdict"
        );
    }
}
