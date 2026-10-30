//! Varbind values → point values (`conv`), and point values → SET values.

use std::fmt::Write as _;
use wyrm_core::{TypeCode, Value};
use wyrm_link_sdk::driver::ParamEnum;
use wyrm_link_sdk::ParamEnum;

use crate::ber::{self, SnmpValue};

/// How a varbind becomes the point's value.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Conv {
    /// From the varbind type: numbers as numbers, OCTET STRING as text
    /// (hex when not UTF-8), IpAddress dotted, OBJECT IDENTIFIER dotted.
    Auto,
    /// Counter32 as it is (raw).
    Counter32,
    /// Counter64 (or Counter32) as it is (raw).
    Counter64,
    /// Difference of a counter over time, per second; Counter32 wraps.
    RatePerS,
    /// Gauge32, INTEGER, TimeTicks or a counter as a number.
    Gauge,
    /// TimeTicks (hundredths) in seconds.
    TimeticksS,
    /// Text (OCTET STRING as UTF-8 or hex, other types in their text form).
    String,
    /// IpAddress, or an OCTET STRING of 4 or 16 octets.
    Ip,
    /// An OCTET STRING of 6 octets as `aa:bb:cc:dd:ee:ff`.
    Mac,
}

/// The SMI type a SET sends.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum SetType {
    Integer,
    OctetString,
    Gauge32,
}

impl Conv {
    /// `~meta` type of a read-only point.
    pub fn type_code(self) -> TypeCode {
        match self {
            Conv::Auto => TypeCode::Dynamic,
            Conv::Counter32 | Conv::Counter64 | Conv::RatePerS | Conv::Gauge | Conv::TimeticksS => {
                TypeCode::Number
            }
            Conv::String | Conv::Ip | Conv::Mac => TypeCode::String,
        }
    }

    /// Numeric conversions take `scale` and `offset`.
    pub fn is_numeric(self) -> bool {
        self.type_code() == TypeCode::Number
    }

    /// Conversions a writable point of `set` may use.
    pub fn writable_as(self, set: SetType) -> bool {
        match set {
            SetType::Integer | SetType::Gauge32 => matches!(self, Conv::Auto | Conv::Gauge),
            SetType::OctetString => matches!(self, Conv::Auto | Conv::String),
        }
    }
}

/// Scaling of numbers: `raw × scale + offset` (raw kept as an integer when
/// both are neutral).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Linear {
    pub scale: f64,
    pub offset: f64,
}

impl Linear {
    fn neutral(self) -> bool {
        self.scale == 1.0 && self.offset == 0.0
    }

    fn int(self, raw: i64) -> Value {
        if self.neutral() {
            Value::from(raw)
        } else {
            Value::Float(raw as f64 * self.scale + self.offset)
        }
    }

    fn uint(self, raw: u64) -> Value {
        if self.neutral() {
            Value::UInt(raw)
        } else {
            Value::Float(raw as f64 * self.scale + self.offset)
        }
    }

    fn float(self, raw: f64) -> Value {
        Value::Float(raw * self.scale + self.offset)
    }
}

/// Why a varbind does not give a value (a point error).
pub fn exception(v: &SnmpValue) -> Option<&'static str> {
    match v {
        SnmpValue::NoSuchObject => Some("noSuchObject: the agent has no such object"),
        SnmpValue::NoSuchInstance => Some("noSuchInstance: the agent has no such instance"),
        SnmpValue::EndOfMibView => Some("endOfMibView: past the end of the agent's MIB view"),
        SnmpValue::Malformed(tag) => Some(malformed(*tag)),
        _ => None,
    }
}

/// The point error of a value whose encoding does not fit its type.
fn malformed(tag: u8) -> &'static str {
    match tag {
        ber::INTEGER => "malformed INTEGER encoding from the agent",
        ber::OBJECT_ID => "malformed OBJECT IDENTIFIER encoding from the agent",
        ber::IP_ADDRESS => "malformed IpAddress encoding from the agent",
        ber::COUNTER32 => "malformed Counter32 encoding from the agent",
        ber::GAUGE32 => "malformed Gauge32 encoding from the agent",
        ber::TIMETICKS => "malformed TimeTicks encoding from the agent",
        ber::COUNTER64 => "malformed Counter64 encoding from the agent",
        _ => "malformed value encoding from the agent",
    }
}

fn mismatch(conv: Conv, v: &SnmpValue) -> String {
    format!("conv {}: cannot convert a {}", conv.name(), v.type_name())
}

/// OCTET STRING as text: UTF-8 without trailing NULs, else hex pairs.
pub fn octets_text(b: &[u8]) -> String {
    let trimmed = match b.iter().rposition(|x| *x != 0) {
        Some(i) => &b[..=i],
        None => &b[..0],
    };
    match std::str::from_utf8(trimmed) {
        Ok(s)
            if !s
                .chars()
                .any(|c| c.is_control() && c != '\n' && c != '\r' && c != '\t') =>
        {
            s.to_owned()
        }
        _ => hex_colon(b),
    }
}

fn hex_colon(b: &[u8]) -> String {
    let mut s = String::with_capacity(b.len() * 3);
    for (i, x) in b.iter().enumerate() {
        if i > 0 {
            s.push(':');
        }
        let _ = write!(s, "{x:02x}");
    }
    s
}

fn ip_text(b: &[u8]) -> Option<String> {
    match b.len() {
        4 => Some(std::net::Ipv4Addr::new(b[0], b[1], b[2], b[3]).to_string()),
        16 => <[u8; 16]>::try_from(b)
            .ok()
            .map(|a| std::net::Ipv6Addr::from(a).to_string()),
        _ => None,
    }
}

/// The value as text (`string`, and `auto` for non-numbers).
fn text(v: &SnmpValue) -> Option<String> {
    Some(match v {
        SnmpValue::Integer(i) => i.to_string(),
        SnmpValue::OctetString(b) => octets_text(b),
        SnmpValue::Oid(o) => o.to_string(),
        SnmpValue::IpAddress(a) => ip_text(a)?,
        SnmpValue::Counter32(x) | SnmpValue::Gauge32(x) | SnmpValue::TimeTicks(x) => x.to_string(),
        SnmpValue::Counter64(x) => x.to_string(),
        SnmpValue::Opaque(b) => hex_colon(b),
        SnmpValue::Null
        | SnmpValue::NoSuchObject
        | SnmpValue::NoSuchInstance
        | SnmpValue::EndOfMibView
        | SnmpValue::Unsupported(_)
        | SnmpValue::Malformed(_) => return None,
    })
}

/// A counter's raw value and width (bits), for `rate_per_s`.
pub fn counter(v: &SnmpValue) -> Result<(u64, u32), String> {
    match v {
        SnmpValue::Counter32(x) => Ok((u64::from(*x), 32)),
        SnmpValue::Counter64(x) => Ok((*x, 64)),
        other => Err(mismatch(Conv::RatePerS, other)),
    }
}

/// The rate from `old` to `new` over `secs`: Counter32 wraps once; a
/// Counter64 that goes down was reset (`None`: no sample).
pub fn rate(old: u64, new: u64, bits: u32, secs: f64, lin: Linear) -> Option<Value> {
    if secs <= 0.0 {
        return None;
    }
    let delta = if new >= old {
        new - old
    } else if bits == 32 {
        new + (1u64 << 32) - old
    } else {
        return None;
    };
    Some(lin.float(delta as f64 / secs))
}

/// Convert one varbind (not `rate_per_s`, which needs two samples).
pub fn convert(conv: Conv, v: &SnmpValue, lin: Linear) -> Result<Value, String> {
    if let Some(e) = exception(v) {
        return Err(e.to_owned());
    }
    let bad = || mismatch(conv, v);
    match conv {
        Conv::Auto => Ok(match v {
            SnmpValue::Integer(i) => lin.int((*i).into()),
            SnmpValue::Counter32(x) | SnmpValue::Gauge32(x) | SnmpValue::TimeTicks(x) => {
                lin.uint((*x).into())
            }
            SnmpValue::Counter64(x) => lin.uint(*x),
            SnmpValue::Opaque(b) => Value::Bytes(b.clone()),
            other => Value::Str(text(other).ok_or_else(bad)?),
        }),
        Conv::Counter32 => match v {
            SnmpValue::Counter32(x) => Ok(lin.uint((*x).into())),
            _ => Err(bad()),
        },
        Conv::Counter64 => match v {
            SnmpValue::Counter64(x) => Ok(lin.uint(*x)),
            SnmpValue::Counter32(x) => Ok(lin.uint((*x).into())),
            _ => Err(bad()),
        },
        Conv::Gauge => match v {
            SnmpValue::Integer(i) => Ok(lin.int((*i).into())),
            SnmpValue::Counter32(x) | SnmpValue::Gauge32(x) | SnmpValue::TimeTicks(x) => {
                Ok(lin.uint((*x).into()))
            }
            SnmpValue::Counter64(x) => Ok(lin.uint(*x)),
            _ => Err(bad()),
        },
        Conv::TimeticksS => match v {
            SnmpValue::TimeTicks(x) => Ok(lin.float(f64::from(*x) / 100.0)),
            _ => Err(bad()),
        },
        Conv::String => text(v).map(Value::Str).ok_or_else(bad),
        Conv::Ip => match v {
            SnmpValue::IpAddress(a) => ip_text(a).map(Value::Str).ok_or_else(bad),
            SnmpValue::OctetString(b) => ip_text(b).map(Value::Str).ok_or_else(bad),
            _ => Err(bad()),
        },
        Conv::Mac => match v {
            SnmpValue::OctetString(b) if b.len() == 6 => Ok(Value::Str(hex_colon(b))),
            _ => Err(bad()),
        },
        // Needs two samples: see [`rate`].
        Conv::RatePerS => Err(bad()),
    }
}

/// The SET value for `v`: numbers are scaled back (`(v − offset) / scale`,
/// rounded) and must fit the type.
pub fn encode_set(set: SetType, v: &Value, lin: Linear) -> Result<SnmpValue, String> {
    match set {
        SetType::OctetString => match v {
            Value::Str(s) => Ok(SnmpValue::OctetString(s.as_bytes().to_vec())),
            Value::Bytes(b) => Ok(SnmpValue::OctetString(b.clone())),
            _ => Err("expected a string".into()),
        },
        SetType::Integer | SetType::Gauge32 => {
            let x = v.as_f64().ok_or("expected a number")?;
            if !x.is_finite() {
                return Err("expected a finite number".into());
            }
            let raw = ((x - lin.offset) / lin.scale).round();
            match set {
                SetType::Integer => {
                    if raw < f64::from(i32::MIN) || raw > f64::from(i32::MAX) {
                        return Err(format!("{raw} does not fit an INTEGER (32 bits)"));
                    }
                    Ok(SnmpValue::Integer(raw as i32))
                }
                _ => {
                    if raw < 0.0 || raw > f64::from(u32::MAX) {
                        return Err(format!("{raw} does not fit a Gauge32"));
                    }
                    Ok(SnmpValue::Gauge32(raw as u32))
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ber::Oid;

    const ONE: Linear = Linear {
        scale: 1.0,
        offset: 0.0,
    };

    #[test]
    fn every_conversion() {
        let c = |conv, v: SnmpValue| convert(conv, &v, ONE);
        assert_eq!(c(Conv::Auto, SnmpValue::Integer(-5)), Ok(Value::Int(-5)));
        assert_eq!(c(Conv::Auto, SnmpValue::Gauge32(7)), Ok(Value::UInt(7)));
        assert_eq!(
            c(Conv::Auto, SnmpValue::Counter64(u64::MAX)),
            Ok(Value::UInt(u64::MAX))
        );
        assert_eq!(
            c(Conv::Auto, SnmpValue::OctetString(b"eth0\0".to_vec())),
            Ok(Value::from("eth0"))
        );
        assert_eq!(
            c(Conv::Auto, SnmpValue::OctetString(vec![0, 1, 0xFF])),
            Ok(Value::from("00:01:ff"))
        );
        assert_eq!(
            c(Conv::Auto, SnmpValue::IpAddress([192, 0, 2, 1])),
            Ok(Value::from("192.0.2.1"))
        );
        assert_eq!(
            c(Conv::Auto, SnmpValue::Oid(Oid(vec![1, 3, 6, 1]))),
            Ok(Value::from("1.3.6.1"))
        );
        assert_eq!(
            c(Conv::Auto, SnmpValue::Opaque(vec![1])),
            Ok(Value::Bytes(vec![1]))
        );
        assert!(c(Conv::Auto, SnmpValue::Null).is_err());
        assert!(c(Conv::Auto, SnmpValue::Unsupported(0x47)).is_err());
        for conv in [Conv::Auto, Conv::String, Conv::Gauge] {
            let e = c(conv, SnmpValue::Malformed(ber::INTEGER)).unwrap_err();
            assert_eq!(e, "malformed INTEGER encoding from the agent");
        }
        assert!(exception(&SnmpValue::Malformed(ber::COUNTER32)).is_some());
        assert_eq!(
            c(Conv::Counter32, SnmpValue::Counter32(9)),
            Ok(Value::UInt(9))
        );
        assert!(c(Conv::Counter32, SnmpValue::Gauge32(9)).is_err());
        assert_eq!(
            c(Conv::Counter64, SnmpValue::Counter32(9)),
            Ok(Value::UInt(9))
        );
        assert_eq!(c(Conv::Gauge, SnmpValue::Integer(-2)), Ok(Value::Int(-2)));
        assert!(c(Conv::Gauge, SnmpValue::OctetString(vec![])).is_err());
        assert_eq!(
            c(Conv::TimeticksS, SnmpValue::TimeTicks(12345)),
            Ok(Value::Float(123.45))
        );
        assert!(c(Conv::TimeticksS, SnmpValue::Integer(1)).is_err());
        assert_eq!(c(Conv::String, SnmpValue::Integer(3)), Ok(Value::from("3")));
        assert_eq!(
            c(Conv::Ip, SnmpValue::OctetString(vec![10, 0, 0, 9])),
            Ok(Value::from("10.0.0.9"))
        );
        let v6 = std::net::Ipv6Addr::LOCALHOST.octets().to_vec();
        assert_eq!(
            c(Conv::Ip, SnmpValue::OctetString(v6)),
            Ok(Value::from("::1"))
        );
        assert!(c(Conv::Ip, SnmpValue::OctetString(vec![1, 2])).is_err());
        assert_eq!(
            c(
                Conv::Mac,
                SnmpValue::OctetString(vec![0, 0x1b, 0x21, 0xa, 0xb, 0xc])
            ),
            Ok(Value::from("00:1b:21:0a:0b:0c"))
        );
        assert!(c(Conv::Mac, SnmpValue::OctetString(vec![1; 5])).is_err());
        for e in [
            SnmpValue::NoSuchObject,
            SnmpValue::NoSuchInstance,
            SnmpValue::EndOfMibView,
        ] {
            let err = c(Conv::Auto, e).unwrap_err();
            assert!(err.starts_with("no") || err.starts_with("end"), "{err}");
        }
    }

    #[test]
    fn scaling() {
        let lin = Linear {
            scale: 0.1,
            offset: -40.0,
        };
        assert_eq!(
            convert(Conv::Gauge, &SnmpValue::Gauge32(650), lin),
            Ok(Value::Float(25.0))
        );
        assert_eq!(
            encode_set(SetType::Integer, &Value::Float(25.0), lin),
            Ok(SnmpValue::Integer(650))
        );
        assert_eq!(
            encode_set(SetType::Gauge32, &Value::UInt(7), ONE),
            Ok(SnmpValue::Gauge32(7))
        );
        assert!(encode_set(SetType::Gauge32, &Value::Int(-1), ONE).is_err());
        assert!(encode_set(SetType::Integer, &Value::Float(3e10), ONE).is_err());
        assert!(encode_set(SetType::Integer, &Value::from("x"), ONE).is_err());
        assert_eq!(
            encode_set(SetType::OctetString, &Value::from("ops"), ONE),
            Ok(SnmpValue::OctetString(b"ops".to_vec()))
        );
        assert!(encode_set(SetType::OctetString, &Value::UInt(1), ONE).is_err());
    }

    #[test]
    fn rates_wrap_and_reset() {
        assert_eq!(rate(100, 300, 32, 2.0, ONE), Some(Value::Float(100.0)));
        // Counter32 wrap: 2^32 - 10 → 90 is +100
        assert_eq!(
            rate(u64::from(u32::MAX) - 9, 90, 32, 1.0, ONE),
            Some(Value::Float(100.0))
        );
        // Counter64 reset: no sample
        assert_eq!(rate(500, 10, 64, 1.0, ONE), None);
        assert_eq!(rate(1, 2, 32, 0.0, ONE), None);
        let bits = Linear {
            scale: 8.0,
            offset: 0.0,
        };
        assert_eq!(rate(0, 125, 64, 1.0, bits), Some(Value::Float(1000.0)));
    }

    #[test]
    fn writable_conversions() {
        assert!(Conv::Gauge.writable_as(SetType::Integer));
        assert!(Conv::Auto.writable_as(SetType::OctetString));
        assert!(!Conv::RatePerS.writable_as(SetType::Integer));
        assert!(!Conv::Mac.writable_as(SetType::OctetString));
        assert!(!Conv::String.writable_as(SetType::Gauge32));
    }
}
