//! The link's data (ADR 0034 "Model"): classes, watches and records, and their forms in the
//! store (CBOR of a `Value` map), in action answers and in the rows sinks take (JSON text).

use std::collections::BTreeMap;

use wyrm_core::{Status, Value};
use wyrm_link_api::{AppError, Rights};

use crate::algo::{value_text, Algorithm};
use crate::limits::{MAX_ESCALATION_S, MAX_INHIBIT_S, MAX_VALUE_TEXT};
use crate::Micros;

pub type Map = BTreeMap<String, Value>;

/// The export format of a class and the JSON form of a record.
pub const CLASS_FORMAT: &str = "wyrm-alarm-class/1";
pub const RECORD_FORMAT: &str = "wyrm-alarm/1";

pub fn invalid(field: &str, rule: impl std::fmt::Display) -> AppError {
    AppError::new(Status::InvalidParameter, format!("{field}: {rule}"))
}

// ---------- reading maps (action args and stored values) ----------

/// Text, or `None` when absent or null.
pub fn get_str(m: &Map, k: &str) -> Result<Option<String>, AppError> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.clone())),
        Some(_) => Err(invalid(k, "must be text")),
    }
}

pub fn req_str(m: &Map, k: &str) -> Result<String, AppError> {
    get_str(m, k)?.ok_or_else(|| invalid(k, "required"))
}

pub fn get_bool(m: &Map, k: &str) -> Result<Option<bool>, AppError> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Bool(b)) => Ok(Some(*b)),
        Some(_) => Err(invalid(k, "must be true or false")),
    }
}

/// A whole number, or `None` when absent or null.
pub fn get_u64(m: &Map, k: &str) -> Result<Option<u64>, AppError> {
    let bad = || invalid(k, "must be a whole number from 0");
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::UInt(n)) => Ok(Some(*n)),
        Some(Value::Int(n)) => u64::try_from(*n).map(Some).map_err(|_| bad()),
        Some(Value::Float(f)) if f.fract() == 0.0 && *f >= 0.0 && *f < 1e15 => Ok(Some(*f as u64)),
        Some(_) => Err(bad()),
    }
}

/// A finite number, or `None` when absent or null.
pub fn get_f64(m: &Map, k: &str) -> Result<Option<f64>, AppError> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(v) => v
            .as_f64()
            .filter(|f| f.is_finite())
            .map(Some)
            .ok_or_else(|| invalid(k, "must be a finite number")),
    }
}

/// An enum argument: through an action its index (the SDK checks `enum` params that way, as
/// the scheduler's `confirm`), in an import or a stored map its name; `None` when absent.
pub fn enum_arg(m: &Map, k: &str, names: &[&str]) -> Result<Option<String>, AppError> {
    wyrm_link_api::args::enum_name(m.get(k), names)
        .map(|n| n.map(str::to_owned))
        .map_err(|e| invalid(k, format!("{e} (by index)")))
}

/// An instant stored as a number (CBOR gives a positive integer back as unsigned).
fn instant(v: Option<&Value>) -> Option<Micros> {
    match v? {
        Value::Int(n) => Some(*n),
        Value::UInt(n) => Micros::try_from(*n).ok(),
        _ => None,
    }
}

fn text(v: Option<&Value>) -> Option<String> {
    match v? {
        Value::Str(s) => Some(s.clone()),
        _ => None,
    }
}

/// An RFC 3339 instant (`2026-11-04T17:00:00Z`).
pub fn rfc3339(t: Micros) -> Value {
    match jiff::Timestamp::from_microsecond(t) {
        Ok(ts) => Value::Str(ts.to_string()),
        Err(_) => Value::Null,
    }
}

fn opt_rfc3339(t: Option<Micros>) -> Value {
    t.map_or(Value::Null, rfc3339)
}

/// An RFC 3339 instant, or a date (its midnight UTC).
pub fn parse_instant(s: &str) -> Option<Micros> {
    let s = s.trim();
    if let Ok(t) = s.parse::<jiff::Timestamp>() {
        return Some(t.as_microsecond());
    }
    let d: jiff::civil::Date = s.parse().ok()?;
    d.to_zoned(jiff::tz::TimeZone::UTC)
        .ok()
        .map(|z| z.timestamp().as_microsecond())
}

/// `<from>/<to>` (or `<from>..<to>`), from before to.
pub fn parse_timerange(s: &str) -> Result<(Micros, Micros), AppError> {
    let bad = || {
        invalid(
            "timerange",
            format!("expected <from>/<to> in RFC 3339, from before to, got {s:?}"),
        )
    };
    let (a, b) = s
        .split_once("..")
        .or_else(|| s.split_once('/'))
        .ok_or_else(bad)?;
    let (from, to) = (
        parse_instant(a).ok_or_else(bad)?,
        parse_instant(b).ok_or_else(bad)?,
    );
    if from >= to {
        return Err(bad());
    }
    Ok((from, to))
}

// ---------- alarm types ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AlarmType {
    Alert,
    Warning,
    Fault,
}

impl AlarmType {
    pub const ALL: [AlarmType; 3] = [AlarmType::Alert, AlarmType::Warning, AlarmType::Fault];

    pub fn as_str(self) -> &'static str {
        match self {
            AlarmType::Alert => "alert",
            AlarmType::Warning => "warning",
            AlarmType::Fault => "fault",
        }
    }

    /// From an action's enum (its name or its index) or a stored name.
    pub fn parse(v: &Value) -> Option<Self> {
        match v {
            Value::Str(s) => Self::ALL.into_iter().find(|t| t.as_str() == s),
            Value::UInt(i) => Self::ALL.get(*i as usize).copied(),
            Value::Int(i) => usize::try_from(*i)
                .ok()
                .and_then(|i| Self::ALL.get(i).copied()),
            Value::Float(f) if f.fract() == 0.0 && *f >= 0.0 => Self::ALL.get(*f as usize).copied(),
            _ => None,
        }
    }

    pub fn from_args(m: &Map, k: &str) -> Result<Option<Self>, AppError> {
        match m.get(k) {
            None | Some(Value::Null) => Ok(None),
            Some(v) => Self::parse(v)
                .map(Some)
                .ok_or_else(|| invalid(k, "alert, warning or fault")),
        }
    }
}

// ---------- records ----------

#[derive(Debug, Clone, PartialEq)]
pub struct Note {
    pub t: Micros,
    pub by: String,
    pub text: String,
}

/// One alarm record.
#[derive(Debug, Clone, PartialEq)]
pub struct Record {
    pub id: u64,
    pub class: String,
    /// The watch that raised it; none for `raise`.
    pub watch: Option<String>,
    pub source: String,
    pub ty: AlarmType,
    pub message: String,
    /// The sample that raised it (scalars only; text cut at [`MAX_VALUE_TEXT`]).
    pub value: Value,
    pub created: Micros,
    pub normal: Option<Micros>,
    pub ack: Option<Micros>,
    pub ack_by: Option<String>,
    pub escalation: u8,
    pub notes: Vec<Note>,
    /// The subject that raised it (`raise`), none for a watch.
    pub by: Option<String>,
}

impl Record {
    pub fn is_active(&self) -> bool {
        self.normal.is_none()
    }
    pub fn is_acked(&self) -> bool {
        self.ack.is_some()
    }
    pub fn is_open(&self) -> bool {
        self.is_active() || !self.is_acked()
    }

    /// `active`, `acked`, `normal` or `closed`.
    pub fn state(&self) -> &'static str {
        match (self.is_active(), self.is_acked()) {
            (true, false) => "active",
            (true, true) => "acked",
            (false, false) => "normal",
            (false, true) => "closed",
        }
    }

    /// The record as stored (CBOR of this map) and as `get_alarm` answers it, with instants as
    /// numbers (`rfc`: as RFC 3339 text, for people).
    pub fn to_value(&self, rfc: bool) -> Value {
        let at = |t: Option<Micros>| {
            if rfc {
                opt_rfc3339(t)
            } else {
                t.map_or(Value::Null, Value::from)
            }
        };
        let mut m = Map::from([
            ("id".to_owned(), Value::UInt(self.id)),
            ("class".to_owned(), Value::Str(self.class.clone())),
            (
                "watch".to_owned(),
                self.watch.clone().map_or(Value::Null, Value::Str),
            ),
            ("source".to_owned(), Value::Str(self.source.clone())),
            ("type".to_owned(), Value::from(self.ty.as_str())),
            ("message".to_owned(), Value::Str(self.message.clone())),
            ("value".to_owned(), self.value.clone()),
            ("created".to_owned(), at(Some(self.created))),
            ("normal".to_owned(), at(self.normal)),
            ("ack".to_owned(), at(self.ack)),
            (
                "ack_by".to_owned(),
                self.ack_by.clone().map_or(Value::Null, Value::Str),
            ),
            ("escalation".to_owned(), Value::UInt(self.escalation.into())),
            ("state".to_owned(), Value::from(self.state())),
            (
                "by".to_owned(),
                self.by.clone().map_or(Value::Null, Value::Str),
            ),
        ]);
        m.insert(
            "notes".to_owned(),
            Value::Array(
                self.notes
                    .iter()
                    .map(|n| {
                        Value::Map(Map::from([
                            ("t".to_owned(), at(Some(n.t))),
                            ("by".to_owned(), Value::Str(n.by.clone())),
                            ("text".to_owned(), Value::Str(n.text.clone())),
                        ]))
                    })
                    .collect(),
            ),
        );
        Value::Map(m)
    }

    /// A row of `get_alarms` and of a class's table: the record without its notes, with their
    /// count.
    pub fn to_row(&self) -> Value {
        let mut v = self.to_value(true);
        if let Value::Map(m) = &mut v {
            m.insert("notes".to_owned(), Value::UInt(self.notes.len() as u64));
        }
        v
    }

    pub fn from_value(v: &Value) -> Option<Self> {
        let Value::Map(m) = v else { return None };
        let notes = match m.get("notes") {
            Some(Value::Array(a)) => a
                .iter()
                .map(|n| match n {
                    Value::Map(n) => Some(Note {
                        t: instant(n.get("t"))?,
                        by: text(n.get("by"))?,
                        text: text(n.get("text"))?,
                    }),
                    _ => None,
                })
                .collect::<Option<Vec<_>>>()?,
            _ => Vec::new(),
        };
        let id = match m.get("id")? {
            Value::UInt(n) => *n,
            _ => return None,
        };
        Some(Record {
            id,
            class: text(m.get("class"))?,
            watch: text(m.get("watch")),
            source: text(m.get("source"))?,
            ty: AlarmType::parse(m.get("type")?)?,
            message: text(m.get("message"))?,
            value: m.get("value").cloned().unwrap_or(Value::Null),
            created: instant(m.get("created"))?,
            normal: instant(m.get("normal")),
            ack: instant(m.get("ack")),
            ack_by: text(m.get("ack_by")),
            escalation: match m.get("escalation") {
                Some(Value::UInt(n)) => u8::try_from(*n).unwrap_or(2),
                _ => 0,
            },
            notes,
            by: text(m.get("by")),
        })
    }

    /// The record as the sync links take it: JSON text (`wyrm-alarm/1`), instants as RFC 3339.
    pub fn to_json(&self) -> String {
        let mut v = value_to_json(&self.to_value(true));
        if let serde_json::Value::Object(o) = &mut v {
            o.insert("format".into(), serde_json::Value::from(RECORD_FORMAT));
        }
        v.to_string()
    }
}

/// `Value` to JSON. Bytes become an array of numbers; a NaN or infinite float becomes null.
pub fn value_to_json(v: &Value) -> serde_json::Value {
    use serde_json::Value as J;
    match v {
        Value::Null => J::Null,
        Value::Bool(b) => J::Bool(*b),
        Value::Int(n) => J::from(*n),
        Value::UInt(n) => J::from(*n),
        Value::Float(f) => serde_json::Number::from_f64(*f).map_or(J::Null, J::Number),
        Value::Str(s) => J::String(s.clone()),
        Value::Bytes(b) => J::Array(b.iter().map(|x| J::from(*x)).collect()),
        Value::Array(a) => J::Array(a.iter().map(value_to_json).collect()),
        Value::Map(m) => J::Object(
            m.iter()
                .map(|(k, v)| (k.clone(), value_to_json(v)))
                .collect(),
        ),
    }
}

/// JSON to `Value`. Whole non-negative numbers are `UInt`, negative ones `Int`, the rest `Float`.
pub fn value_from_json(j: &serde_json::Value) -> Value {
    use serde_json::Value as J;
    match j {
        J::Null => Value::Null,
        J::Bool(b) => Value::Bool(*b),
        J::Number(n) => {
            if let Some(u) = n.as_u64() {
                Value::UInt(u)
            } else if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else {
                Value::Float(n.as_f64().unwrap_or(f64::NAN))
            }
        }
        J::String(s) => Value::Str(s.clone()),
        J::Array(a) => Value::Array(a.iter().map(value_from_json).collect()),
        J::Object(o) => Value::Map(
            o.iter()
                .map(|(k, v)| (k.clone(), value_from_json(v)))
                .collect(),
        ),
    }
}

/// A sample's value as a record keeps it: scalars as they are, text cut, the rest `null`.
pub fn record_value(v: &Value) -> Value {
    match v {
        Value::Null | Value::Bool(_) | Value::Int(_) | Value::UInt(_) => v.clone(),
        Value::Float(f) if f.is_finite() => v.clone(),
        Value::Float(_) => Value::Null,
        Value::Str(s) if s.chars().count() <= MAX_VALUE_TEXT => v.clone(),
        Value::Str(s) => Value::Str(s.chars().take(MAX_VALUE_TEXT).collect()),
        other => Value::Str(value_text(other)),
    }
}

// ---------- classes and watches ----------

#[derive(Debug, Clone, PartialEq)]
pub struct WatchDef {
    pub id: String,
    /// A key, or a prefix with `subtree` (`<prefix>/**`).
    pub source: String,
    pub subtree: bool,
    pub algorithm: Algorithm,
    pub ty: AlarmType,
    pub message: String,
    pub to_alarm_s: u64,
    pub to_normal_s: u64,
    pub enabled: bool,
    pub created_by: String,
    /// The author's rights (ADR 0029); none: a stored watch from before they were kept, which
    /// does not run.
    pub rights: Option<Rights>,
}

impl WatchDef {
    /// The key the host subscribes.
    pub fn sub_key(&self) -> String {
        if self.subtree {
            format!("{}/**", self.source)
        } else {
            self.source.clone()
        }
    }

    /// `stored`: with the author's rights.
    pub fn to_value(&self, stored: bool) -> Value {
        let mut m = Map::from([
            ("id".to_owned(), Value::Str(self.id.clone())),
            ("source".to_owned(), Value::Str(self.sub_key())),
            ("algorithm".to_owned(), Value::from(self.algorithm.name())),
            ("params".to_owned(), Value::Map(self.algorithm.params())),
            ("type".to_owned(), Value::from(self.ty.as_str())),
            ("message".to_owned(), Value::Str(self.message.clone())),
            ("to_alarm_s".to_owned(), Value::UInt(self.to_alarm_s)),
            ("to_normal_s".to_owned(), Value::UInt(self.to_normal_s)),
            ("enabled".to_owned(), Value::Bool(self.enabled)),
            ("created_by".to_owned(), Value::Str(self.created_by.clone())),
        ]);
        if stored {
            if let Some(r) = &self.rights {
                m.insert("rights".to_owned(), r.to_value());
            }
        }
        Value::Map(m)
    }

    pub fn from_value(v: &Value) -> Result<Self, AppError> {
        let Value::Map(m) = v else {
            return Err(invalid("watch", "a map"));
        };
        let id = req_str(m, "id")?;
        let (source, subtree) = parse_source(&req_str(m, "source")?)?;
        let params = match m.get("params") {
            Some(Value::Map(p)) => p.clone(),
            _ => Map::new(),
        };
        let algorithm = Algorithm::from_args(&req_str(m, "algorithm")?, &params, None)?;
        let ty = AlarmType::from_args(m, "type")?.unwrap_or(AlarmType::Alert);
        Ok(WatchDef {
            message: get_str(m, "message")?
                .unwrap_or_else(|| algorithm.default_message().to_owned()),
            to_alarm_s: inhibit(m, "to_alarm_s")?.unwrap_or(0),
            to_normal_s: inhibit(m, "to_normal_s")?.unwrap_or(0),
            enabled: get_bool(m, "enabled")?.unwrap_or(true),
            created_by: get_str(m, "created_by")?.unwrap_or_default(),
            rights: m.get("rights").and_then(Rights::from_value),
            id,
            source,
            subtree,
            algorithm,
            ty,
        })
    }
}

/// An inhibit or escalation time in seconds, at most `max`.
pub fn seconds(m: &Map, k: &str, max: u64) -> Result<Option<u64>, AppError> {
    match get_u64(m, k)? {
        Some(s) if s > max => Err(invalid(k, format!("at most {max} seconds"))),
        other => Ok(other),
    }
}

pub fn inhibit(m: &Map, k: &str) -> Result<Option<u64>, AppError> {
    seconds(m, k, MAX_INHIBIT_S)
}

pub fn escalation(m: &Map, k: &str) -> Result<Option<u64>, AppError> {
    seconds(m, k, MAX_ESCALATION_S)
}

/// A source: a key of the tree (`wy/<site>/<section>/<link>/<path…>`, no `*`, `~` or empty
/// segment) or a subtree `<prefix>/**` with at least `wy/<site>/<section>`; `(prefix, subtree)`.
pub fn parse_source(s: &str) -> Result<(String, bool), AppError> {
    let s = s.trim();
    let (prefix, subtree) = match s.strip_suffix("/**") {
        Some(p) => (p, true),
        None => (s, false),
    };
    let segs: Vec<&str> = prefix.split('/').collect();
    let least = if subtree { 3 } else { 5 };
    let ok = segs.len() >= least
        && segs[0] == wyrm_core::keyspace::ROOT
        && matches!(segs[2], "downstream" | "dataflows" | "storage")
        && segs
            .iter()
            .all(|x| wyrm_core::keyspace::validate_segment(x).is_ok() && !matches!(*x, "." | ".."));
    if !ok {
        return Err(invalid(
            "source",
            format!(
                "{s:?} is not a key wy/<site>/downstream|dataflows|storage/<link>/<path> or such \
                 a prefix with /** (no *, ~ or empty segment)"
            ),
        ));
    }
    Ok((prefix.to_owned(), subtree))
}

#[derive(Debug, Clone, PartialEq)]
pub struct ClassDef {
    pub id: String,
    pub display: String,
    pub escalation1_s: u64,
    pub escalation2_s: u64,
    pub created_by: String,
    pub watches: Vec<WatchDef>,
    /// The next `n` of a watch id `w<n>`; never goes down, so an id is never reused.
    pub next_watch: u32,
}

impl ClassDef {
    pub fn to_value(&self, stored: bool) -> Value {
        Value::Map(Map::from([
            ("format".to_owned(), Value::from(CLASS_FORMAT)),
            ("id".to_owned(), Value::Str(self.id.clone())),
            ("display".to_owned(), Value::Str(self.display.clone())),
            ("escalation1_s".to_owned(), Value::UInt(self.escalation1_s)),
            ("escalation2_s".to_owned(), Value::UInt(self.escalation2_s)),
            ("created_by".to_owned(), Value::Str(self.created_by.clone())),
            (
                "watches".to_owned(),
                Value::Array(self.watches.iter().map(|w| w.to_value(stored)).collect()),
            ),
            (
                "next_watch".to_owned(),
                Value::UInt(u64::from(self.next_watch)),
            ),
        ]))
    }

    pub fn from_value(v: &Value) -> Result<Self, AppError> {
        let Value::Map(m) = v else {
            return Err(invalid("class", "a map"));
        };
        let id = req_str(m, "id")?;
        valid_id(&id)?;
        let watches = match m.get("watches") {
            Some(Value::Array(a)) => a
                .iter()
                .map(WatchDef::from_value)
                .collect::<Result<Vec<_>, _>>()?,
            None | Some(Value::Null) => Vec::new(),
            _ => return Err(invalid("watches", "an array")),
        };
        let mut seen = std::collections::HashSet::new();
        let mut max_n = 0u32;
        for w in &watches {
            if !seen.insert(w.id.as_str()) {
                return Err(invalid("watches", format!("{} twice", w.id)));
            }
            let n: u32 =
                w.id.strip_prefix('w')
                    .and_then(|n| n.parse().ok())
                    .ok_or_else(|| invalid("watches", format!("{}: not a watch id w<n>", w.id)))?;
            max_n = max_n.max(n);
        }
        let next_watch = match get_u64(m, "next_watch")? {
            Some(n) => u32::try_from(n).map_err(|_| invalid("next_watch", "too large"))?,
            None => max_n + 1,
        };
        if next_watch <= max_n {
            return Err(invalid("next_watch", "below a watch id in use"));
        }
        Ok(ClassDef {
            display: get_str(m, "display")?.unwrap_or_else(|| id.clone()),
            escalation1_s: escalation(m, "escalation1_s")?.unwrap_or(0),
            escalation2_s: escalation(m, "escalation2_s")?.unwrap_or(0),
            created_by: get_str(m, "created_by")?.unwrap_or_default(),
            id,
            watches,
            next_watch,
        })
    }

    /// Escalation 2 comes after escalation 1 when both are set.
    pub fn validate(&self) -> Result<(), AppError> {
        valid_id(&self.id)?;
        if self.escalation1_s > 0
            && self.escalation2_s > 0
            && self.escalation2_s <= self.escalation1_s
        {
            return Err(invalid("escalation2_s", "must be after escalation1_s"));
        }
        if self.escalation1_s == 0 && self.escalation2_s > 0 {
            return Err(invalid("escalation2_s", "needs escalation1_s"));
        }
        Ok(())
    }
}

/// A class id: a key segment that is not a name the link uses itself.
pub fn valid_id(id: &str) -> Result<(), AppError> {
    wyrm_core::keyspace::validate_segment(id).map_err(|e| invalid("id", e))?;
    if matches!(id, "stats" | "sinks") || id.starts_with('.') || id.starts_with('~') {
        return Err(invalid("id", format!("{id:?} is taken")));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn record_round_trips_and_states() {
        let mut r = Record {
            id: 7,
            class: "c".into(),
            watch: Some("w1".into()),
            source: "wy/s/downstream/plc/temp".into(),
            ty: AlarmType::Fault,
            message: "hot".into(),
            value: Value::Float(99.5),
            created: 1_700_000_000_000_000,
            normal: None,
            ack: None,
            ack_by: None,
            escalation: 0,
            notes: vec![Note {
                t: 1,
                by: "user:ann".into(),
                text: "seen".into(),
            }],
            by: None,
        };
        assert_eq!(r.state(), "active");
        let bytes = wyrm_core::codec::to_vec(&r.to_value(false)).unwrap();
        let back = wyrm_core::codec::from_slice::<Value>(&bytes).unwrap();
        assert_eq!(Record::from_value(&back), Some(r.clone()));
        r.ack = Some(5);
        r.ack_by = Some("user:ann".into());
        assert_eq!(r.state(), "acked");
        r.normal = Some(6);
        assert_eq!(r.state(), "closed");
        assert!(!r.is_open());
        let j: serde_json::Value = serde_json::from_str(&r.to_json()).unwrap();
        assert_eq!(j["format"], RECORD_FORMAT);
        assert_eq!(j["created"], "2023-11-14T22:13:20Z");
        assert_eq!(j["notes"][0]["text"], "seen");
        let Value::Map(row) = r.to_row() else {
            panic!()
        };
        assert_eq!(row["notes"], Value::UInt(1));
    }

    #[test]
    fn sources_and_ids() {
        assert_eq!(
            parse_source("wy/s/downstream/plc/temp").unwrap(),
            ("wy/s/downstream/plc/temp".into(), false)
        );
        assert_eq!(
            parse_source("wy/s/downstream/plc/**").unwrap(),
            ("wy/s/downstream/plc".into(), true)
        );
        assert_eq!(
            parse_source("wy/s/downstream/**").unwrap(),
            ("wy/s/downstream".into(), true)
        );
        for bad in [
            "wy/s/downstream/plc",
            "wy/s/sys/x/y",
            "wy/s/downstream/*/t",
            "wy/s/downstream/plc/~val",
            "downstream/plc/t",
            "wy/s/**",
        ] {
            assert!(parse_source(bad).is_err(), "{bad}");
        }
        assert!(valid_id("stats").is_err());
        assert!(valid_id("line1").is_ok());
    }

    #[test]
    fn class_round_trip() {
        let m = Map::from([
            ("id".to_owned(), Value::from("c")),
            (
                "watches".to_owned(),
                Value::Array(vec![Value::Map(Map::from([
                    ("id".to_owned(), Value::from("w3")),
                    ("source".to_owned(), Value::from("wy/s/downstream/plc/**")),
                    ("algorithm".to_owned(), Value::from("quality")),
                ]))]),
            ),
        ]);
        let c = ClassDef::from_value(&Value::Map(m)).unwrap();
        assert_eq!(c.next_watch, 4);
        assert!(c.watches[0].subtree);
        assert_eq!(c.watches[0].message, "{name}: quality {quality}");
        let back = ClassDef::from_value(&c.to_value(true)).unwrap();
        assert_eq!(back, c);
    }
}
