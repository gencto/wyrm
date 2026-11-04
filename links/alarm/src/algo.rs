//! The alarm algorithms of a watch (ADR 0034 "Model"): what a sample says about its key.

use std::collections::BTreeMap;

use wyrm_core::{Quality, Sample, Status, Value};
use wyrm_link_api::AppError;

use crate::limits::MAX_STALE_S;
use crate::model::{get_bool, get_f64, get_u64};

fn invalid(field: &str, rule: impl std::fmt::Display) -> AppError {
    AppError::new(Status::InvalidParameter, format!("{field}: {rule}"))
}

/// An alarm algorithm with its parameters.
#[derive(Debug, Clone, PartialEq)]
pub enum Algorithm {
    /// In alarm while the value equals `alarm_value`.
    Boolean { alarm_value: bool },
    /// In alarm while the value is below `min` or above `max`; back inside by `deadband`.
    OutOfRange {
        min: Option<f64>,
        max: Option<f64>,
        deadband: f64,
    },
    /// In alarm when no sample came for `stale_s`.
    Staleness { stale_s: u64 },
    /// In alarm while the sample's quality is `bad` (or `uncertain` too).
    Quality { include_uncertain: bool },
}

/// What a sample says.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Judged {
    Alarm,
    Normal,
    /// The sample says nothing (not a number for a range, a value between the limit and its
    /// deadband).
    Same,
}

impl Algorithm {
    pub const NAMES: [&'static str; 4] = ["boolean", "out_of_range", "staleness", "quality"];

    pub fn name(&self) -> &'static str {
        match self {
            Algorithm::Boolean { .. } => "boolean",
            Algorithm::OutOfRange { .. } => "out_of_range",
            Algorithm::Staleness { .. } => "staleness",
            Algorithm::Quality { .. } => "quality",
        }
    }

    /// The algorithm named `name` with the parameters in `m` (an action's args or a stored
    /// map); `base` (an edit) gives the parameters not named.
    pub fn from_args(
        name: &str,
        m: &BTreeMap<String, Value>,
        base: Option<&Algorithm>,
    ) -> Result<Self, AppError> {
        let same = base.filter(|b| b.name() == name);
        Ok(match name {
            "boolean" => {
                let was = match same {
                    Some(Algorithm::Boolean { alarm_value }) => *alarm_value,
                    _ => true,
                };
                Algorithm::Boolean {
                    alarm_value: get_bool(m, "alarm_value")?.unwrap_or(was),
                }
            }
            "out_of_range" => {
                let (bmin, bmax, bdead) = match same {
                    Some(Algorithm::OutOfRange { min, max, deadband }) => (*min, *max, *deadband),
                    _ => (None, None, 0.0),
                };
                let min = match m.get("min") {
                    None => bmin,
                    Some(Value::Null) => None,
                    Some(_) => Some(get_f64(m, "min")?.unwrap_or(0.0)),
                };
                let max = match m.get("max") {
                    None => bmax,
                    Some(Value::Null) => None,
                    Some(_) => Some(get_f64(m, "max")?.unwrap_or(0.0)),
                };
                let deadband = get_f64(m, "deadband")?.unwrap_or(bdead);
                if min.is_none() && max.is_none() {
                    return Err(invalid("min", "min or max is required"));
                }
                if let (Some(a), Some(b)) = (min, max) {
                    if a > b {
                        return Err(invalid("min", "must not be above max"));
                    }
                }
                if !deadband.is_finite() || deadband < 0.0 {
                    return Err(invalid("deadband", "a number from 0"));
                }
                Algorithm::OutOfRange { min, max, deadband }
            }
            "staleness" => {
                let was = match same {
                    Some(Algorithm::Staleness { stale_s }) => Some(*stale_s),
                    _ => None,
                };
                let stale_s = get_u64(m, "stale_s")?
                    .or(was)
                    .ok_or_else(|| invalid("stale_s", "required"))?;
                if !(1..=MAX_STALE_S).contains(&stale_s) {
                    return Err(invalid("stale_s", format!("1 to {MAX_STALE_S} seconds")));
                }
                Algorithm::Staleness { stale_s }
            }
            "quality" => {
                let was = match same {
                    Some(Algorithm::Quality { include_uncertain }) => *include_uncertain,
                    _ => false,
                };
                Algorithm::Quality {
                    include_uncertain: get_bool(m, "include_uncertain")?.unwrap_or(was),
                }
            }
            _ => {
                return Err(invalid(
                    "algorithm",
                    format!("one of {}", Self::NAMES.join(", ")),
                ))
            }
        })
    }

    /// The parameters as a map (an attribute, the store, the export).
    pub fn params(&self) -> BTreeMap<String, Value> {
        let mut m = BTreeMap::new();
        match self {
            Algorithm::Boolean { alarm_value } => {
                m.insert("alarm_value".to_owned(), Value::Bool(*alarm_value));
            }
            Algorithm::OutOfRange { min, max, deadband } => {
                m.insert("min".to_owned(), min.map_or(Value::Null, Value::Float));
                m.insert("max".to_owned(), max.map_or(Value::Null, Value::Float));
                m.insert("deadband".to_owned(), Value::Float(*deadband));
            }
            Algorithm::Staleness { stale_s } => {
                m.insert("stale_s".to_owned(), Value::UInt(*stale_s));
            }
            Algorithm::Quality { include_uncertain } => {
                m.insert(
                    "include_uncertain".to_owned(),
                    Value::Bool(*include_uncertain),
                );
            }
        }
        m
    }

    /// The staleness deadline, seconds, of a `staleness` watch.
    pub fn stale_s(&self) -> Option<u64> {
        match self {
            Algorithm::Staleness { stale_s } => Some(*stale_s),
            _ => None,
        }
    }

    /// What `s` says, given that the key is in alarm now (`in_alarm`: the deadband applies).
    pub fn judge(&self, s: &Sample, in_alarm: bool) -> Judged {
        match self {
            Algorithm::Boolean { alarm_value } => match truth(&s.v) {
                Some(b) if b == *alarm_value => Judged::Alarm,
                Some(_) => Judged::Normal,
                None => Judged::Same,
            },
            Algorithm::OutOfRange { min, max, deadband } => {
                let Some(x) = s.v.as_f64().filter(|x| x.is_finite()) else {
                    return Judged::Same;
                };
                let below = min.is_some_and(|m| x < m);
                let above = max.is_some_and(|m| x > m);
                if below || above {
                    return Judged::Alarm;
                }
                if in_alarm {
                    let inside = min.is_none_or(|m| x >= m + deadband)
                        && max.is_none_or(|m| x <= m - deadband);
                    if !inside {
                        return Judged::Same;
                    }
                }
                Judged::Normal
            }
            // a sample ends staleness; the deadline is the watch's wake
            Algorithm::Staleness { .. } => Judged::Normal,
            Algorithm::Quality { include_uncertain } => match s.q {
                Quality::Good => Judged::Normal,
                Quality::Uncertain if !include_uncertain => Judged::Normal,
                _ => Judged::Alarm,
            },
        }
    }

    /// The default message template of a watch on this algorithm.
    pub fn default_message(&self) -> &'static str {
        match self {
            Algorithm::Boolean { .. } | Algorithm::OutOfRange { .. } => "{name}: {value}",
            Algorithm::Staleness { .. } => "{name}: no sample for {stale_s} s",
            Algorithm::Quality { .. } => "{name}: quality {quality}",
        }
    }
}

/// A value as a truth: a bool, a number (not 0), the text `true`/`false`.
fn truth(v: &Value) -> Option<bool> {
    match v {
        Value::Bool(b) => Some(*b),
        Value::Str(s) => match s.trim().to_ascii_lowercase().as_str() {
            "true" | "on" | "1" => Some(true),
            "false" | "off" | "0" => Some(false),
            _ => None,
        },
        _ => v.as_f64().map(|x| x != 0.0),
    }
}

/// The message of a record from the watch's template: `{source}`, `{name}` (the key's last
/// segment), `{value}`, `{quality}`, `{class}`, `{watch}`, `{stale_s}`.
pub fn render(
    template: &str,
    source: &str,
    value: &Value,
    quality: Quality,
    class: &str,
    watch: &str,
    algorithm: &Algorithm,
) -> String {
    let name = source.rsplit('/').next().unwrap_or(source);
    let stale = algorithm
        .stale_s()
        .map(|s| s.to_string())
        .unwrap_or_default();
    template
        .replace("{source}", source)
        .replace("{name}", name)
        .replace("{value}", &value_text(value))
        .replace("{quality}", quality.name())
        .replace("{class}", class)
        .replace("{watch}", watch)
        .replace("{stale_s}", &stale)
}

/// A value as short text.
pub fn value_text(v: &Value) -> String {
    match v {
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Int(n) => n.to_string(),
        Value::UInt(n) => n.to_string(),
        Value::Float(f) => format!("{f}"),
        Value::Str(s) => s.clone(),
        Value::Bytes(b) => format!("{} bytes", b.len()),
        Value::Array(a) => format!("[{} items]", a.len()),
        Value::Map(m) => format!("{{{} keys}}", m.len()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(v: Value, q: Quality) -> Sample {
        Sample { v, q, t: 0 }
    }

    #[test]
    fn boolean_and_quality() {
        let b = Algorithm::Boolean { alarm_value: true };
        assert_eq!(
            b.judge(&sample(Value::Bool(true), Quality::Good), false),
            Judged::Alarm
        );
        assert_eq!(
            b.judge(&sample(Value::UInt(0), Quality::Good), true),
            Judged::Normal
        );
        assert_eq!(
            b.judge(&sample(Value::from("on"), Quality::Good), false),
            Judged::Alarm
        );
        assert_eq!(
            b.judge(&sample(Value::from("x"), Quality::Good), false),
            Judged::Same
        );
        let q = Algorithm::Quality {
            include_uncertain: false,
        };
        assert_eq!(
            q.judge(&sample(Value::Null, Quality::Bad), false),
            Judged::Alarm
        );
        assert_eq!(
            q.judge(&sample(Value::Null, Quality::Uncertain), false),
            Judged::Normal
        );
        let q = Algorithm::Quality {
            include_uncertain: true,
        };
        assert_eq!(
            q.judge(&sample(Value::Null, Quality::Uncertain), false),
            Judged::Alarm
        );
    }

    #[test]
    fn range_with_deadband() {
        let r = Algorithm::OutOfRange {
            min: Some(10.0),
            max: Some(20.0),
            deadband: 1.0,
        };
        let j = |x: f64, in_alarm: bool| r.judge(&sample(Value::Float(x), Quality::Good), in_alarm);
        assert_eq!(j(25.0, false), Judged::Alarm);
        assert_eq!(j(19.5, true), Judged::Same);
        assert_eq!(j(19.0, true), Judged::Normal);
        assert_eq!(j(19.5, false), Judged::Normal);
        assert_eq!(j(5.0, false), Judged::Alarm);
        assert_eq!(
            r.judge(&sample(Value::from("x"), Quality::Good), false),
            Judged::Same
        );
        let m = BTreeMap::from([("max".to_owned(), Value::UInt(5))]);
        let a = Algorithm::from_args("out_of_range", &m, None).unwrap();
        assert_eq!(
            a,
            Algorithm::OutOfRange {
                min: None,
                max: Some(5.0),
                deadband: 0.0
            }
        );
        // an edit keeps what it does not name and clears with null
        let m = BTreeMap::from([("min".to_owned(), Value::Float(1.0))]);
        let e = Algorithm::from_args("out_of_range", &m, Some(&a)).unwrap();
        assert_eq!(e.params()["max"], Value::Float(5.0));
        let m = BTreeMap::from([("max".to_owned(), Value::Null)]);
        assert!(Algorithm::from_args("out_of_range", &m, Some(&e)).is_ok());
        let m = BTreeMap::from([("max".to_owned(), Value::Null)]);
        assert!(Algorithm::from_args("out_of_range", &m, Some(&a)).is_err());
        assert!(Algorithm::from_args("nope", &BTreeMap::new(), None).is_err());
    }

    #[test]
    fn messages_render() {
        let a = Algorithm::Staleness { stale_s: 30 };
        let s = render(
            a.default_message(),
            "wy/s/downstream/plc/temp",
            &Value::Null,
            Quality::Good,
            "c",
            "w1",
            &a,
        );
        assert_eq!(s, "temp: no sample for 30 s");
        let b = Algorithm::Boolean { alarm_value: true };
        let s = render(
            "{class}/{watch} {source} = {value} ({quality})",
            "wy/s/downstream/plc/fault",
            &Value::Bool(true),
            Quality::Uncertain,
            "c",
            "w1",
            &b,
        );
        assert_eq!(s, "c/w1 wy/s/downstream/plc/fault = true (uncertain)");
    }
}
