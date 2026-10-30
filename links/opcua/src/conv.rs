//! Pure conversions: node id text, OPC UA `Variant` ↔ WYRM `Value`, scaling,
//! and the classes of OPC UA status codes ([`DriverError`]).

use opcua::types::{
    status_code::SubStatusCode, Array, ByteString, DateTime, Identifier, NamespaceMap, NodeId,
    StatusCode, UAString, Variant, VariantScalarTypeId,
};
use std::str::FromStr as _;
use wyrm_core::Value;
use wyrm_link_sdk::driver::DriverError;

/// The namespace part of a point's node id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Ns {
    /// No `ns=`/`nsu=`: the device's `namespace_uri`, or namespace 0.
    Device,
    /// `ns=<index>`: taken as it is.
    Index(u16),
    /// `nsu=<uri>`: looked up in the server's namespace array.
    Uri(String),
}

/// A node id as configured: the namespace is resolved per session, since a
/// server restart may reorder its namespace array.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeRef {
    pub ns: Ns,
    pub id: Identifier,
}

/// Parse `ns=2;s=Line1.Temp`, `ns=3;i=1001`, `nsu=<uri>;s=…`, `i=2259`,
/// `g=<guid>`, `b=<base64>`.
pub fn parse_node(s: &str) -> Result<NodeRef, String> {
    let bad = || format!("{s:?} is not a node id (ns=<n>;s=…, nsu=<uri>;i=…, i=…)");
    let s = s.trim();
    let (ns, rest) = if let Some(r) = s.strip_prefix("nsu=") {
        let (uri, rest) = r.split_once(';').ok_or_else(bad)?;
        if uri.is_empty() {
            return Err(bad());
        }
        (Ns::Uri(uri.to_owned()), rest)
    } else if let Some(r) = s.strip_prefix("ns=") {
        let (n, rest) = r.split_once(';').ok_or_else(bad)?;
        (Ns::Index(n.parse::<u16>().map_err(|_| bad())?), rest)
    } else {
        (Ns::Device, s)
    };
    let id = Identifier::from_str(rest).map_err(|_| bad())?;
    if matches!(&id, Identifier::String(u) if u.is_empty()) {
        return Err(bad());
    }
    Ok(NodeRef { ns, id })
}

impl NodeRef {
    /// The node id on a server with namespace array `nss`; `dev_ns` is the
    /// device's `namespace_uri` (empty: none).
    pub fn resolve(&self, dev_ns: &str, nss: &NamespaceMap) -> Result<NodeId, String> {
        let uri_index = |uri: &str| {
            nss.get_index(uri)
                .ok_or_else(|| format!("namespace {uri:?} is not on the server"))
        };
        let ns = match &self.ns {
            Ns::Index(n) => *n,
            Ns::Uri(u) => uri_index(u)?,
            Ns::Device if dev_ns.is_empty() => 0,
            Ns::Device => uri_index(dev_ns)?,
        };
        Ok(NodeId::new(ns, self.id.clone()))
    }
}

// ---------- status codes ----------

/// Status codes that mean the session or the connection is gone.
const TRANSPORT: [SubStatusCode; 18] = [
    SubStatusCode::BadConnectionClosed,
    SubStatusCode::BadNotConnected,
    SubStatusCode::BadSecureChannelClosed,
    SubStatusCode::BadSecureChannelIdInvalid,
    SubStatusCode::BadSecureChannelTokenUnknown,
    SubStatusCode::BadSessionClosed,
    SubStatusCode::BadSessionIdInvalid,
    SubStatusCode::BadSessionNotActivated,
    SubStatusCode::BadCommunicationError,
    SubStatusCode::BadServerHalted,
    SubStatusCode::BadServerNotConnected,
    SubStatusCode::BadTcpInternalError,
    SubStatusCode::BadConnectionRejected,
    SubStatusCode::BadDisconnect,
    SubStatusCode::BadShutdown,
    SubStatusCode::BadTcpServerTooBusy,
    SubStatusCode::BadTooManySessions,
    SubStatusCode::BadInvalidState,
];

/// A failed service request (not one item of it): timeout → `Device`,
/// session or connection lost → `Transport`, anything else (the server
/// answered with a service fault) → `Point`.
pub fn service_error(code: StatusCode, what: &str) -> DriverError {
    let sub = code.sub_code();
    let msg = format!("{what}: {}", code.sub_code().name());
    if matches!(
        sub,
        SubStatusCode::BadTimeout | SubStatusCode::BadRequestTimeout
    ) {
        DriverError::Device(msg)
    } else if TRANSPORT.contains(&sub) {
        DriverError::Transport(msg)
    } else {
        DriverError::Point(msg)
    }
}

/// The value of one read item: only a `Good` status gives a value. The
/// framework has no `uncertain` quality for a fresh value, so an
/// `Uncertain` status fails the point as a `Bad` one does (never `good`).
pub fn item_status(status: Option<StatusCode>) -> Result<(), DriverError> {
    let code = status.unwrap_or(StatusCode::Good);
    if code.is_good() {
        Ok(())
    } else if code.is_uncertain() {
        Err(DriverError::Point(format!(
            "uncertain: {}",
            code.sub_code().name()
        )))
    } else {
        Err(DriverError::Point(code.sub_code().name().to_owned()))
    }
}

// ---------- values ----------

/// An OPC UA value as a WYRM value. DateTime → RFC 3339 string, ByteString
/// → bytes, LocalizedText → its text, NodeId/Guid/QualifiedName → their
/// text form, arrays (also multi-dimensional, flattened) → arrays.
pub fn to_value(v: &Variant) -> Result<Value, String> {
    Ok(match v {
        Variant::Empty => Value::Null,
        Variant::Boolean(b) => Value::Bool(*b),
        Variant::SByte(x) => Value::from(i64::from(*x)),
        Variant::Byte(x) => Value::UInt(u64::from(*x)),
        Variant::Int16(x) => Value::from(i64::from(*x)),
        Variant::UInt16(x) => Value::UInt(u64::from(*x)),
        Variant::Int32(x) => Value::from(i64::from(*x)),
        Variant::UInt32(x) => Value::UInt(u64::from(*x)),
        Variant::Int64(x) => Value::from(*x),
        Variant::UInt64(x) => Value::UInt(*x),
        Variant::Float(x) => Value::Float(f64::from(*x)),
        Variant::Double(x) => Value::Float(*x),
        Variant::String(s) => ua_str(s).map(Value::Str).unwrap_or(Value::Null),
        Variant::DateTime(d) => Value::Str(d.to_rfc3339()),
        Variant::ByteString(b) => match &b.value {
            Some(bytes) => Value::Bytes(bytes.clone()),
            None => Value::Null,
        },
        Variant::LocalizedText(t) => ua_str(&t.text).map(Value::Str).unwrap_or(Value::Null),
        Variant::QualifiedName(q) => Value::Str(q.to_string()),
        Variant::NodeId(n) => Value::Str(n.to_string()),
        Variant::ExpandedNodeId(n) => Value::Str(n.to_string()),
        Variant::Guid(g) => Value::Str(g.to_string()),
        Variant::StatusCode(s) => Value::UInt(u64::from(s.bits())),
        Variant::Variant(inner) => to_value(inner)?,
        Variant::Array(a) => Value::Array(a.values.iter().map(to_value).collect::<Result<_, _>>()?),
        Variant::XmlElement(_) => return Err("XmlElement values are not supported".into()),
        Variant::ExtensionObject(_) => {
            return Err("structured (ExtensionObject) values are not supported".into())
        }
        Variant::DataValue(_) | Variant::DiagnosticInfo(_) => {
            return Err("DataValue/DiagnosticInfo values are not supported".into())
        }
    })
}

fn ua_str(s: &UAString) -> Option<String> {
    s.value().clone()
}

/// `raw · scale + offset` for numbers (elementwise on arrays); the identity
/// keeps integers as they are.
pub fn scale(v: Value, scale: f64, offset: f64) -> Result<Value, String> {
    if scale == 1.0 && offset == 0.0 {
        return Ok(v);
    }
    match v {
        Value::Array(items) => Ok(Value::Array(
            items
                .into_iter()
                .map(|x| scale_one(x, scale, offset))
                .collect::<Result<_, _>>()?,
        )),
        x => scale_one(x, scale, offset),
    }
}

fn scale_one(v: Value, scale: f64, offset: f64) -> Result<Value, String> {
    match v {
        Value::Int(_) | Value::UInt(_) | Value::Float(_) => {
            let x = v.as_f64().unwrap_or(0.0);
            Ok(Value::Float(x * scale + offset))
        }
        Value::Null => Ok(Value::Null),
        _ => Err("scale/offset set on a value that is not a number".into()),
    }
}

/// `(v − offset) / scale` before a write (elementwise on arrays).
pub fn unscale(v: &Value, scale: f64, offset: f64) -> Result<Value, String> {
    if scale == 1.0 && offset == 0.0 {
        return Ok(v.clone());
    }
    let one = |x: &Value| match x {
        Value::Int(_) | Value::UInt(_) | Value::Float(_) => {
            let f = x.as_f64().unwrap_or(0.0);
            Ok(Value::Float((f - offset) / scale))
        }
        _ => Err("expected a number (the point has scale/offset)".to_owned()),
    };
    match v {
        Value::Array(items) => Ok(Value::Array(
            items.iter().map(one).collect::<Result<_, _>>()?,
        )),
        x => one(x),
    }
}

/// The variant type a write needs: the node's DataType (built-in ids 1–15,
/// Duration → Double, UtcTime → DateTime) and whether it is an array.
pub fn builtin_type(data_type: &NodeId) -> Option<VariantScalarTypeId> {
    if data_type.namespace != 0 {
        return None;
    }
    let Identifier::Numeric(n) = data_type.identifier else {
        return None;
    };
    use VariantScalarTypeId as T;
    Some(match n {
        1 => T::Boolean,
        2 => T::SByte,
        3 => T::Byte,
        4 => T::Int16,
        5 => T::UInt16,
        6 => T::Int32,
        7 => T::UInt32,
        8 => T::Int64,
        9 => T::UInt64,
        10 => T::Float,
        11 | 290 => T::Double,
        12 => T::String,
        13 | 294 => T::DateTime,
        15 => T::ByteString,
        _ => return None,
    })
}

/// The name of a built-in type for people (`Double`, `Int32`, …).
pub fn type_name(t: VariantScalarTypeId) -> &'static str {
    use VariantScalarTypeId as T;
    match t {
        T::Boolean => "Boolean",
        T::SByte => "SByte",
        T::Byte => "Byte",
        T::Int16 => "Int16",
        T::UInt16 => "UInt16",
        T::Int32 => "Int32",
        T::UInt32 => "UInt32",
        T::Int64 => "Int64",
        T::UInt64 => "UInt64",
        T::Float => "Float",
        T::Double => "Double",
        T::String => "String",
        T::DateTime => "DateTime",
        T::ByteString => "ByteString",
        _ => "other",
    }
}

/// The variant to write for `v` into a node of type `t` (an array when
/// `array`). Lossy conversions are refused: a fraction into an integer, a
/// number out of the type's range, an integer a Double cannot hold exactly,
/// a number for a Boolean. A Float takes a number in its range at f32
/// precision (0.1 cannot be exact in either type), but not an integer above
/// 2^24 (it would change) or a nonzero number that would become 0.
pub fn to_variant(v: &Value, t: VariantScalarTypeId, array: bool) -> Result<Variant, String> {
    if array {
        let Value::Array(items) = v else {
            return Err(format!("expected an array of {}", type_name(t)));
        };
        let values = items
            .iter()
            .map(|x| scalar(x, t))
            .collect::<Result<Vec<_>, _>>()?;
        return Array::new(t, values)
            .map(|a| Variant::Array(Box::new(a)))
            .map_err(|e| format!("array: {e:?}"));
    }
    scalar(v, t)
}

/// An integral number in `[min, max]`; a float that differs from an
/// integer only by rounding noise (a few ulps, relative) counts as that
/// integer (a scaled write: `21.5 / 0.1 = 214.99999999999997`). A real
/// fraction is refused at any magnitude.
fn integer(v: &Value, min: i128, max: i128, name: &str) -> Result<i128, String> {
    let n: i128 = match v {
        Value::Int(i) => i128::from(*i),
        Value::UInt(u) => i128::from(*u),
        Value::Float(f) => {
            if !f.is_finite() {
                return Err(format!("{f} does not fit {name}"));
            }
            let r = f.round();
            if (f - r).abs() > 4.0 * f64::EPSILON * r.abs().max(1.0) {
                return Err(format!("{f} has a fraction; {name} takes whole numbers"));
            }
            if r < -1.8e19 || r > 1.9e19 {
                return Err(format!("{f} does not fit {name}"));
            }
            r as i128
        }
        _ => return Err(format!("expected a number for {name}")),
    };
    if n < min || n > max {
        return Err(format!("{n} is out of range for {name} ({min}..={max})"));
    }
    Ok(n)
}

fn scalar(v: &Value, t: VariantScalarTypeId) -> Result<Variant, String> {
    use VariantScalarTypeId as T;
    let name = type_name(t);
    let int = |min: i128, max: i128| integer(v, min, max, name);
    Ok(match t {
        T::Boolean => match v {
            Value::Bool(b) => Variant::Boolean(*b),
            _ => return Err("expected true or false for Boolean".into()),
        },
        T::SByte => Variant::SByte(fit(int(i8::MIN.into(), i8::MAX.into())?, name)?),
        T::Byte => Variant::Byte(fit(int(0, u8::MAX.into())?, name)?),
        T::Int16 => Variant::Int16(fit(int(i16::MIN.into(), i16::MAX.into())?, name)?),
        T::UInt16 => Variant::UInt16(fit(int(0, u16::MAX.into())?, name)?),
        T::Int32 => Variant::Int32(fit(int(i32::MIN.into(), i32::MAX.into())?, name)?),
        T::UInt32 => Variant::UInt32(fit(int(0, u32::MAX.into())?, name)?),
        T::Int64 => Variant::Int64(fit(int(i64::MIN.into(), i64::MAX.into())?, name)?),
        T::UInt64 => Variant::UInt64(fit(int(0, u64::MAX.into())?, name)?),
        T::Float => {
            const EXACT: u64 = 1 << 24;
            let f = match v {
                Value::Int(i) if i.unsigned_abs() > EXACT => {
                    return Err("integer too large for Float exactly".into())
                }
                Value::UInt(u) if *u > EXACT => {
                    return Err("integer too large for Float exactly".into())
                }
                _ => number(v, name)?,
            };
            if f.abs() > f64::from(f32::MAX) {
                return Err(format!("{f} is out of range for Float"));
            }
            // in range: the cast rounds to the nearest f32
            let x = f as f32;
            if x == 0.0 && f != 0.0 {
                return Err(format!("{f} is too small for Float (it would be 0)"));
            }
            Variant::Float(x)
        }
        T::Double => Variant::Double(number(v, name)?),
        T::String => match v {
            Value::Str(s) => Variant::String(UAString::from(s.as_str())),
            _ => return Err("expected a string for String".into()),
        },
        T::DateTime => match v {
            Value::Str(s) => Variant::DateTime(Box::new(
                DateTime::parse_from_rfc3339(s)
                    .map_err(|_| format!("{s:?} is not an RFC 3339 time"))?,
            )),
            _ => return Err("expected an RFC 3339 string for DateTime".into()),
        },
        T::ByteString => match v {
            Value::Bytes(b) => Variant::ByteString(ByteString::from(b.clone())),
            _ => return Err("expected bytes for ByteString".into()),
        },
        _ => return Err(format!("writing type {t:?} is not supported")),
    })
}

/// An integer already checked against the type's range.
fn fit<T: TryFrom<i128>>(n: i128, name: &str) -> Result<T, String> {
    T::try_from(n).map_err(|_| format!("{n} is out of range for {name}"))
}

/// A finite number; an integer beyond 2^53 does not fit a double exactly.
fn number(v: &Value, name: &str) -> Result<f64, String> {
    const EXACT: u64 = 1 << 53;
    match v {
        Value::Float(f) if f.is_finite() => Ok(*f),
        Value::Int(i) if i.unsigned_abs() <= EXACT => Ok(*i as f64),
        Value::UInt(u) if *u <= EXACT => Ok(*u as f64),
        Value::Int(_) | Value::UInt(_) => Err(format!("integer too large for {name} exactly")),
        _ => Err(format!("expected a finite number for {name}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use VariantScalarTypeId as T;

    #[test]
    fn node_ids() {
        let n = parse_node("ns=2;s=Line1.Temp").unwrap();
        assert_eq!(n.ns, Ns::Index(2));
        assert_eq!(n.id, Identifier::String("Line1.Temp".into()));
        let n = parse_node("ns=3;i=1001").unwrap();
        assert_eq!((n.ns, n.id), (Ns::Index(3), Identifier::Numeric(1001)));
        let n = parse_node("nsu=urn:x:y;s=a;b").unwrap();
        assert_eq!(n.ns, Ns::Uri("urn:x:y".into()));
        assert_eq!(n.id, Identifier::String("a;b".into()));
        let n = parse_node("i=2259").unwrap();
        assert_eq!((n.ns, n.id), (Ns::Device, Identifier::Numeric(2259)));
        for bad in [
            "",
            "x",
            "ns=;s=a",
            "ns=70000;i=1",
            "ns=2",
            "nsu=;s=a",
            "nsu=urn",
            "s=",
            "i=abc",
            "q=1",
        ] {
            assert!(parse_node(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn namespaces_resolve_by_uri() {
        let mut nss = NamespaceMap::new();
        nss.add_namespace("urn:a");
        nss.add_namespace("urn:b");
        let b = nss.get_index("urn:b").unwrap();
        let p = parse_node("s=x").unwrap();
        assert_eq!(p.resolve("", &nss).unwrap().namespace, 0);
        assert_eq!(p.resolve("urn:b", &nss).unwrap().namespace, b);
        assert!(p.resolve("urn:missing", &nss).is_err());
        let u = parse_node("nsu=urn:a;i=5").unwrap();
        assert_eq!(
            u.resolve("urn:b", &nss).unwrap(),
            NodeId::new(nss.get_index("urn:a").unwrap(), 5u32)
        );
        let i = parse_node("ns=7;i=5").unwrap();
        assert_eq!(i.resolve("urn:b", &nss).unwrap().namespace, 7);
    }

    #[test]
    fn statuses() {
        assert!(item_status(None).is_ok());
        assert!(item_status(Some(StatusCode::Good)).is_ok());
        assert!(matches!(
            item_status(Some(StatusCode::UncertainLastUsableValue)),
            Err(DriverError::Point(m)) if m.starts_with("uncertain")
        ));
        assert!(matches!(
            item_status(Some(StatusCode::BadNodeIdUnknown)),
            Err(DriverError::Point(m)) if m.contains("BadNodeIdUnknown")
        ));
        assert!(matches!(
            service_error(StatusCode::BadTimeout, "read"),
            DriverError::Device(_)
        ));
        assert!(matches!(
            service_error(StatusCode::BadRequestTimeout, "read"),
            DriverError::Device(_)
        ));
        for c in [
            StatusCode::BadConnectionClosed,
            StatusCode::BadSessionIdInvalid,
            StatusCode::BadNotConnected,
            StatusCode::BadSecureChannelClosed,
        ] {
            assert!(
                matches!(service_error(c, "read"), DriverError::Transport(_)),
                "{c}"
            );
        }
        assert!(matches!(
            service_error(StatusCode::BadTooManyOperations, "read"),
            DriverError::Point(_)
        ));
    }

    #[test]
    fn values_from_variants() {
        assert_eq!(
            to_value(&Variant::Boolean(true)).unwrap(),
            Value::Bool(true)
        );
        assert_eq!(to_value(&Variant::SByte(-3)).unwrap(), Value::Int(-3));
        assert_eq!(to_value(&Variant::Byte(3)).unwrap(), Value::UInt(3));
        assert_eq!(to_value(&Variant::Int16(-300)).unwrap(), Value::Int(-300));
        assert_eq!(to_value(&Variant::UInt16(300)).unwrap(), Value::UInt(300));
        assert_eq!(to_value(&Variant::Int32(7)).unwrap(), Value::UInt(7));
        assert_eq!(to_value(&Variant::UInt32(7)).unwrap(), Value::UInt(7));
        assert_eq!(to_value(&Variant::Int64(-1)).unwrap(), Value::Int(-1));
        assert_eq!(
            to_value(&Variant::UInt64(u64::MAX)).unwrap(),
            Value::UInt(u64::MAX)
        );
        assert_eq!(to_value(&Variant::Float(1.5)).unwrap(), Value::Float(1.5));
        assert_eq!(
            to_value(&Variant::Double(2.25)).unwrap(),
            Value::Float(2.25)
        );
        assert_eq!(
            to_value(&Variant::String("hi".into())).unwrap(),
            Value::Str("hi".into())
        );
        assert_eq!(
            to_value(&Variant::String(UAString::null())).unwrap(),
            Value::Null
        );
        let t = DateTime::parse_from_rfc3339("2026-10-30T12:00:00Z").unwrap();
        match to_value(&Variant::DateTime(Box::new(t))).unwrap() {
            Value::Str(s) => assert!(s.starts_with("2026-10-30T12:00:00"), "{s}"),
            v => panic!("{v:?}"),
        }
        assert_eq!(
            to_value(&Variant::ByteString(ByteString::from(vec![1u8, 2]))).unwrap(),
            Value::Bytes(vec![1, 2])
        );
        let a = Array::new(T::Int32, vec![Variant::Int32(1), Variant::Int32(-2)]).unwrap();
        assert_eq!(
            to_value(&Variant::Array(Box::new(a))).unwrap(),
            Value::Array(vec![Value::UInt(1), Value::Int(-2)])
        );
        assert_eq!(to_value(&Variant::Empty).unwrap(), Value::Null);
        assert!(to_value(&Variant::ExtensionObject(Default::default())).is_err());
    }

    #[test]
    fn scaling() {
        assert_eq!(scale(Value::UInt(5), 1.0, 0.0).unwrap(), Value::UInt(5));
        assert_eq!(
            scale(Value::UInt(215), 0.1, 0.0).unwrap(),
            Value::Float(215.0 * 0.1)
        );
        assert_eq!(
            scale(Value::Array(vec![Value::UInt(1), Value::Int(-1)]), 2.0, 1.0).unwrap(),
            Value::Array(vec![Value::Float(3.0), Value::Float(-1.0)])
        );
        assert!(scale(Value::Str("x".into()), 2.0, 0.0).is_err());
        assert_eq!(
            unscale(&Value::Float(21.5), 0.1, 0.0).unwrap(),
            Value::Float(21.5 / 0.1)
        );
        assert!(unscale(&Value::Bool(true), 2.0, 0.0).is_err());
        // a scaled write lands on the integer
        let raw = unscale(&Value::Float(21.5), 0.1, 0.0).unwrap();
        assert_eq!(scalar(&raw, T::Int16).unwrap(), Variant::Int16(215));
    }

    #[test]
    fn writes_refuse_lossy_conversions() {
        assert_eq!(
            to_variant(&Value::Bool(true), T::Boolean, false).unwrap(),
            Variant::Boolean(true)
        );
        assert!(to_variant(&Value::UInt(1), T::Boolean, false).is_err());
        assert_eq!(
            to_variant(&Value::UInt(42), T::Int32, false).unwrap(),
            Variant::Int32(42)
        );
        assert_eq!(
            to_variant(&Value::Float(42.0), T::Int32, false).unwrap(),
            Variant::Int32(42)
        );
        assert!(to_variant(&Value::Float(42.5), T::Int32, false).is_err());
        assert!(to_variant(&Value::UInt(40_000), T::Int16, false).is_err());
        assert!(to_variant(&Value::Int(-1), T::UInt32, false).is_err());
        assert!(to_variant(&Value::Int(-129), T::SByte, false).is_err());
        assert!(to_variant(&Value::UInt(256), T::Byte, false).is_err());
        assert_eq!(
            to_variant(&Value::UInt(u64::MAX), T::UInt64, false).unwrap(),
            Variant::UInt64(u64::MAX)
        );
        assert!(to_variant(&Value::UInt(u64::MAX), T::Int64, false).is_err());
        assert_eq!(
            to_variant(&Value::Float(1.5), T::Float, false).unwrap(),
            Variant::Float(1.5)
        );
        assert!(to_variant(&Value::Float(1e300), T::Float, false).is_err());
        assert_eq!(
            to_variant(&Value::UInt(3), T::Double, false).unwrap(),
            Variant::Double(3.0)
        );
        assert!(to_variant(&Value::UInt((1 << 53) + 1), T::Double, false).is_err());
        assert!(to_variant(&Value::Str("1".into()), T::Double, false).is_err());
        assert_eq!(
            to_variant(&Value::Str("x".into()), T::String, false).unwrap(),
            Variant::String("x".into())
        );
        assert!(to_variant(&Value::UInt(1), T::String, false).is_err());
        assert!(matches!(
            to_variant(
                &Value::Str("2026-10-30T12:00:00Z".into()),
                T::DateTime,
                false
            )
            .unwrap(),
            Variant::DateTime(_)
        ));
        assert!(to_variant(&Value::Str("yesterday".into()), T::DateTime, false).is_err());
        assert_eq!(
            to_variant(&Value::Bytes(vec![9]), T::ByteString, false).unwrap(),
            Variant::ByteString(ByteString::from(vec![9u8]))
        );
        let arr = to_variant(
            &Value::Array(vec![Value::Float(1.0), Value::UInt(2)]),
            T::Double,
            true,
        )
        .unwrap();
        assert_eq!(
            to_value(&arr).unwrap(),
            Value::Array(vec![Value::Float(1.0), Value::Float(2.0)])
        );
        assert!(to_variant(&Value::Float(1.0), T::Double, true).is_err());
        assert!(to_variant(&Value::Array(vec![Value::Float(1.5)]), T::Int32, true).is_err());
    }

    /// Only rounding noise counts as a whole number, at any magnitude.
    #[test]
    fn integers_refuse_real_fractions_at_any_size() {
        let raw = unscale(&Value::Float(2.5), 0.1, 0.0).unwrap();
        assert_eq!(scalar(&raw, T::Int16).unwrap(), Variant::Int16(25));
        let raw = unscale(&Value::Float(21.5), 0.1, 0.0).unwrap();
        assert_eq!(scalar(&raw, T::Int16).unwrap(), Variant::Int16(215));
        assert!(scalar(&Value::Float(600_000_000.4), T::Int32).is_err());
        assert!(scalar(&Value::Float(3_000_000_000.5), T::UInt32).is_err());
        assert!(scalar(&Value::Float(1_000_000.0005), T::Int64).is_err());
        assert_eq!(
            scalar(&Value::Float(600_000_000.0), T::Int32).unwrap(),
            Variant::Int32(600_000_000)
        );
    }

    /// Float follows Double's rule: an integer it cannot hold exactly and a
    /// nonzero number that becomes 0 are refused.
    #[test]
    fn floats_refuse_what_they_cannot_hold() {
        assert_eq!(
            scalar(&Value::UInt(1 << 24), T::Float).unwrap(),
            Variant::Float(16_777_216.0)
        );
        assert!(scalar(&Value::UInt((1 << 24) + 1), T::Float).is_err());
        assert!(scalar(&Value::Int(-(1 << 24) - 1), T::Float).is_err());
        assert!(scalar(&Value::Float(1e-50), T::Float).is_err());
        assert_eq!(
            scalar(&Value::Float(0.0), T::Float).unwrap(),
            Variant::Float(0.0)
        );
        assert_eq!(
            scalar(&Value::Float(0.1), T::Float).unwrap(),
            Variant::Float(0.1)
        );
    }

    #[test]
    fn builtin_types() {
        assert_eq!(builtin_type(&NodeId::new(0, 11u32)), Some(T::Double));
        assert_eq!(builtin_type(&NodeId::new(0, 290u32)), Some(T::Double));
        assert_eq!(builtin_type(&NodeId::new(0, 294u32)), Some(T::DateTime));
        assert_eq!(builtin_type(&NodeId::new(0, 6u32)), Some(T::Int32));
        assert_eq!(builtin_type(&NodeId::new(0, 26u32)), None); // Number (abstract)
        assert_eq!(builtin_type(&NodeId::new(2, 11u32)), None);
    }
}
