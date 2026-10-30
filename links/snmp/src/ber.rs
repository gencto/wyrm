//! BER (X.690) as SNMP uses it: definite lengths only, the universal types
//! INTEGER, OCTET STRING, NULL, OBJECT IDENTIFIER and SEQUENCE, the SMIv2
//! application types (RFC 2578) and the v2 varbind exceptions (RFC 3416).
//!
//! The decoder never panics on malformed input: every length is bounded by
//! the bytes left, integers by their type's width.

use std::cmp::Ordering;
use std::fmt;

pub const INTEGER: u8 = 0x02;
pub const OCTET_STRING: u8 = 0x04;
pub const NULL: u8 = 0x05;
pub const OBJECT_ID: u8 = 0x06;
pub const SEQUENCE: u8 = 0x30;
pub const IP_ADDRESS: u8 = 0x40;
pub const COUNTER32: u8 = 0x41;
pub const GAUGE32: u8 = 0x42;
pub const TIMETICKS: u8 = 0x43;
pub const OPAQUE: u8 = 0x44;
pub const COUNTER64: u8 = 0x46;
pub const NO_SUCH_OBJECT: u8 = 0x80;
pub const NO_SUCH_INSTANCE: u8 = 0x81;
pub const END_OF_MIB_VIEW: u8 = 0x82;

/// Longest OID accepted (RFC 2578: at most 128 sub-identifiers).
pub const MAX_ARCS: usize = 128;

/// A malformed encoding.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BerError(pub &'static str);

impl fmt::Display for BerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "malformed BER: {}", self.0)
    }
}

impl std::error::Error for BerError {}

pub type Result<T> = std::result::Result<T, BerError>;

/// An OBJECT IDENTIFIER. `Ord` is the SNMP lexicographic order.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Default)]
pub struct Oid(pub Vec<u32>);

impl Oid {
    /// Parse the numeric dotted form: `1.3.6.1…`, `.1.3.6.1…` or
    /// `iso.3.6.1…`. At least two arcs; the first 0, 1 or 2, the second
    /// below 40 under 0 and 1.
    pub fn parse(s: &str) -> std::result::Result<Oid, String> {
        let t = s.trim();
        let t = t.strip_prefix('.').unwrap_or(t);
        let t = match t.strip_prefix("iso") {
            Some(rest) if rest.is_empty() || rest.starts_with('.') => {
                format!("1{rest}")
            }
            _ => t.to_owned(),
        };
        if t.is_empty() {
            return Err(format!("{s:?}: empty"));
        }
        let mut arcs = Vec::new();
        for part in t.split('.') {
            if part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()) {
                return Err(format!("{s:?}: not a numeric OID (1.3.6.1…)"));
            }
            let n: u32 = part
                .parse()
                .map_err(|_| format!("{s:?}: arc {part} is above 4294967295"))?;
            arcs.push(n);
        }
        let oid = Oid(arcs);
        oid.check().map_err(|e| format!("{s:?}: {e}"))?;
        Ok(oid)
    }

    fn check(&self) -> std::result::Result<(), &'static str> {
        match self.0.as_slice() {
            [] | [_] => Err("an OID has at least two arcs"),
            [a, _, ..] if *a > 2 => Err("the first arc is 0, 1 or 2"),
            [a, b, ..] if *a < 2 && *b >= 40 => Err("the second arc is below 40 under 0 and 1"),
            [a, b, ..] if *a == 2 && *b > u32::MAX - 80 => Err("the second arc is too large"),
            arcs if arcs.len() > MAX_ARCS => Err("more than 128 arcs"),
            _ => Ok(()),
        }
    }

    /// `self` followed by `suffix`.
    pub fn join(&self, suffix: &[u32]) -> Oid {
        let mut v = self.0.clone();
        v.extend_from_slice(suffix);
        Oid(v)
    }

    pub fn starts_with(&self, prefix: &Oid) -> bool {
        self.0.starts_with(&prefix.0)
    }

    /// The arcs after `prefix`, if `self` is under it.
    pub fn suffix(&self, prefix: &Oid) -> Option<&[u32]> {
        self.0.strip_prefix(prefix.0.as_slice())
    }

    /// Compare in SNMP order.
    pub fn cmp_snmp(&self, other: &Oid) -> Ordering {
        self.cmp(other)
    }
}

impl fmt::Display for Oid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut first = true;
        for a in &self.0 {
            if !first {
                f.write_str(".")?;
            }
            first = false;
            write!(f, "{a}")?;
        }
        Ok(())
    }
}

/// A varbind value.
#[derive(Debug, Clone, PartialEq)]
pub enum SnmpValue {
    Integer(i32),
    OctetString(Vec<u8>),
    Null,
    Oid(Oid),
    IpAddress([u8; 4]),
    Counter32(u32),
    /// Gauge32 and Unsigned32 (one tag).
    Gauge32(u32),
    TimeTicks(u32),
    Opaque(Vec<u8>),
    Counter64(u64),
    NoSuchObject,
    NoSuchInstance,
    EndOfMibView,
    /// A type this link does not know (NsapAddress, UInteger32, …): its tag.
    Unsupported(u8),
}

impl SnmpValue {
    /// SMI type name, as `walk` reports it.
    pub fn type_name(&self) -> &'static str {
        match self {
            SnmpValue::Integer(_) => "integer",
            SnmpValue::OctetString(_) => "octet_string",
            SnmpValue::Null => "null",
            SnmpValue::Oid(_) => "oid",
            SnmpValue::IpAddress(_) => "ip_address",
            SnmpValue::Counter32(_) => "counter32",
            SnmpValue::Gauge32(_) => "gauge32",
            SnmpValue::TimeTicks(_) => "timeticks",
            SnmpValue::Opaque(_) => "opaque",
            SnmpValue::Counter64(_) => "counter64",
            SnmpValue::NoSuchObject => "no_such_object",
            SnmpValue::NoSuchInstance => "no_such_instance",
            SnmpValue::EndOfMibView => "end_of_mib_view",
            SnmpValue::Unsupported(_) => "unsupported",
        }
    }

    /// `noSuchObject`, `noSuchInstance` or `endOfMibView`.
    pub fn is_exception(&self) -> bool {
        matches!(
            self,
            SnmpValue::NoSuchObject | SnmpValue::NoSuchInstance | SnmpValue::EndOfMibView
        )
    }
}

// ---------- writer ----------

/// Append the length octets of `n`.
fn put_len(out: &mut Vec<u8>, n: usize) {
    if n < 0x80 {
        out.push(u8::try_from(n).unwrap_or(0));
        return;
    }
    let bytes = n.to_be_bytes();
    let skip = bytes.iter().take_while(|b| **b == 0).count();
    let len = &bytes[skip..];
    out.push(0x80 | u8::try_from(len.len()).unwrap_or(0));
    out.extend_from_slice(len);
}

/// Append `tag`, the length and `content`.
pub fn tlv(out: &mut Vec<u8>, tag: u8, content: &[u8]) {
    out.push(tag);
    put_len(out, content.len());
    out.extend_from_slice(content);
}

/// The minimal two's complement bytes of `v`.
fn int_bytes(v: i64) -> Vec<u8> {
    let b = v.to_be_bytes();
    let mut i = 0;
    while i < 7 {
        let redundant =
            (b[i] == 0x00 && b[i + 1] & 0x80 == 0) || (b[i] == 0xFF && b[i + 1] & 0x80 != 0);
        if !redundant {
            break;
        }
        i += 1;
    }
    b[i..].to_vec()
}

/// The minimal bytes of an unsigned value (a leading 0 when the top bit is set).
fn uint_bytes(v: u64) -> Vec<u8> {
    let b = v.to_be_bytes();
    let skip = b.iter().take(7).take_while(|x| **x == 0).count();
    let mut out = Vec::with_capacity(9);
    if b[skip] & 0x80 != 0 {
        out.push(0);
    }
    out.extend_from_slice(&b[skip..]);
    out
}

pub fn put_int(out: &mut Vec<u8>, tag: u8, v: i64) {
    tlv(out, tag, &int_bytes(v));
}

pub fn put_uint(out: &mut Vec<u8>, tag: u8, v: u64) {
    tlv(out, tag, &uint_bytes(v));
}

pub fn put_oid(out: &mut Vec<u8>, oid: &Oid) {
    let mut c = Vec::with_capacity(oid.0.len() + 4);
    let (a, b) = match oid.0.as_slice() {
        [a, b, ..] => (*a, *b),
        [a] => (*a, 0),
        [] => (0, 0),
    };
    base128(&mut c, a.saturating_mul(40).saturating_add(b));
    for arc in oid.0.iter().skip(2) {
        base128(&mut c, *arc);
    }
    tlv(out, OBJECT_ID, &c);
}

fn base128(out: &mut Vec<u8>, mut v: u32) {
    let mut tmp = [0u8; 5];
    let mut i = tmp.len();
    loop {
        i -= 1;
        tmp[i] = u8::try_from(v & 0x7F).unwrap_or(0);
        v >>= 7;
        if v == 0 {
            break;
        }
    }
    let n = tmp.len();
    for (k, b) in tmp[i..].iter().enumerate() {
        out.push(if i + k + 1 < n { b | 0x80 } else { *b });
    }
}

pub fn put_value(out: &mut Vec<u8>, v: &SnmpValue) {
    match v {
        SnmpValue::Integer(i) => put_int(out, INTEGER, (*i).into()),
        SnmpValue::OctetString(b) => tlv(out, OCTET_STRING, b),
        SnmpValue::Null => tlv(out, NULL, &[]),
        SnmpValue::Oid(o) => put_oid(out, o),
        SnmpValue::IpAddress(a) => tlv(out, IP_ADDRESS, a),
        SnmpValue::Counter32(x) => put_uint(out, COUNTER32, (*x).into()),
        SnmpValue::Gauge32(x) => put_uint(out, GAUGE32, (*x).into()),
        SnmpValue::TimeTicks(x) => put_uint(out, TIMETICKS, (*x).into()),
        SnmpValue::Opaque(b) => tlv(out, OPAQUE, b),
        SnmpValue::Counter64(x) => put_uint(out, COUNTER64, *x),
        SnmpValue::NoSuchObject => tlv(out, NO_SUCH_OBJECT, &[]),
        SnmpValue::NoSuchInstance => tlv(out, NO_SUCH_INSTANCE, &[]),
        SnmpValue::EndOfMibView => tlv(out, END_OF_MIB_VIEW, &[]),
        SnmpValue::Unsupported(tag) => tlv(out, *tag, &[]),
    }
}

// ---------- reader ----------

/// Reads TLVs from a borrowed buffer.
#[derive(Debug, Clone, Copy)]
pub struct Reader<'a> {
    buf: &'a [u8],
}

impl<'a> Reader<'a> {
    pub fn new(buf: &'a [u8]) -> Self {
        Self { buf }
    }

    pub fn is_empty(&self) -> bool {
        self.buf.is_empty()
    }

    /// The next TLV: its tag and content.
    pub fn tlv(&mut self) -> Result<(u8, &'a [u8])> {
        let (&tag, rest) = self.buf.split_first().ok_or(BerError("truncated tag"))?;
        if tag & 0x1F == 0x1F {
            return Err(BerError("multi-byte tags are not used by SNMP"));
        }
        let (&first, rest) = rest.split_first().ok_or(BerError("truncated length"))?;
        let (len, rest) = if first < 0x80 {
            (usize::from(first), rest)
        } else {
            let n = usize::from(first & 0x7F);
            if n == 0 {
                return Err(BerError("indefinite length"));
            }
            if n > 4 || rest.len() < n {
                return Err(BerError("bad length"));
            }
            let len = rest[..n]
                .iter()
                .fold(0usize, |acc, b| (acc << 8) | usize::from(*b));
            (len, &rest[n..])
        };
        if rest.len() < len {
            return Err(BerError("content runs past the end"));
        }
        let (content, rest) = rest.split_at(len);
        self.buf = rest;
        Ok((tag, content))
    }

    /// The next TLV, which must have `tag`.
    pub fn expect(&mut self, tag: u8, what: &'static str) -> Result<&'a [u8]> {
        let (t, c) = self.tlv()?;
        if t != tag {
            return Err(BerError(what));
        }
        Ok(c)
    }

    pub fn int(&mut self, what: &'static str) -> Result<i64> {
        decode_int(self.expect(INTEGER, what)?)
    }

    /// An INTEGER that must fit `i32` (request ids, error status).
    pub fn int32(&mut self, what: &'static str) -> Result<i32> {
        i32::try_from(self.int(what)?).map_err(|_| BerError(what))
    }

    pub fn octets(&mut self, what: &'static str) -> Result<&'a [u8]> {
        self.expect(OCTET_STRING, what)
    }

    pub fn sequence(&mut self, what: &'static str) -> Result<Reader<'a>> {
        Ok(Reader::new(self.expect(SEQUENCE, what)?))
    }
}

pub fn decode_int(c: &[u8]) -> Result<i64> {
    if c.is_empty() || c.len() > 8 {
        return Err(BerError("integer length"));
    }
    let neg = c[0] & 0x80 != 0;
    let mut v: i64 = if neg { -1 } else { 0 };
    for b in c {
        v = (v << 8) | i64::from(*b);
    }
    Ok(v)
}

/// An unsigned value of at most `bits` bits (a leading 0 octet allowed).
pub fn decode_uint(c: &[u8], bits: u32) -> Result<u64> {
    let c = match c {
        [0, rest @ ..] if !rest.is_empty() => rest,
        _ => c,
    };
    if c.is_empty() || c.len() > 8 {
        return Err(BerError("unsigned length"));
    }
    let v = c.iter().fold(0u64, |acc, b| (acc << 8) | u64::from(*b));
    if bits < 64 && v >> bits != 0 {
        return Err(BerError("unsigned out of range"));
    }
    Ok(v)
}

pub fn decode_oid(c: &[u8]) -> Result<Oid> {
    if c.is_empty() {
        return Err(BerError("empty OID"));
    }
    let mut arcs = Vec::new();
    let mut acc: u64 = 0;
    let mut first = true;
    for (i, b) in c.iter().enumerate() {
        acc = (acc << 7) | u64::from(b & 0x7F);
        if acc > u64::from(u32::MAX) {
            return Err(BerError("OID arc out of range"));
        }
        if b & 0x80 != 0 {
            if i + 1 == c.len() {
                return Err(BerError("truncated OID arc"));
            }
            continue;
        }
        let v = u32::try_from(acc).map_err(|_| BerError("OID arc out of range"))?;
        if first {
            let (a, b) = match v {
                0..=39 => (0, v),
                40..=79 => (1, v - 40),
                _ => (2, v - 80),
            };
            arcs.push(a);
            arcs.push(b);
            first = false;
        } else {
            arcs.push(v);
        }
        if arcs.len() > MAX_ARCS {
            return Err(BerError("OID too long"));
        }
        acc = 0;
    }
    Ok(Oid(arcs))
}

pub fn decode_value(tag: u8, c: &[u8]) -> Result<SnmpValue> {
    let u32_of = |c: &[u8]| -> Result<u32> {
        u32::try_from(decode_uint(c, 32)?).map_err(|_| BerError("unsigned out of range"))
    };
    Ok(match tag {
        INTEGER => SnmpValue::Integer(
            i32::try_from(decode_int(c)?).map_err(|_| BerError("INTEGER out of range"))?,
        ),
        OCTET_STRING => SnmpValue::OctetString(c.to_vec()),
        NULL => SnmpValue::Null,
        OBJECT_ID => SnmpValue::Oid(decode_oid(c)?),
        IP_ADDRESS => SnmpValue::IpAddress(
            <[u8; 4]>::try_from(c).map_err(|_| BerError("IpAddress is 4 octets"))?,
        ),
        COUNTER32 => SnmpValue::Counter32(u32_of(c)?),
        GAUGE32 => SnmpValue::Gauge32(u32_of(c)?),
        TIMETICKS => SnmpValue::TimeTicks(u32_of(c)?),
        OPAQUE => SnmpValue::Opaque(c.to_vec()),
        COUNTER64 => SnmpValue::Counter64(decode_uint(c, 64)?),
        NO_SUCH_OBJECT => SnmpValue::NoSuchObject,
        NO_SUCH_INSTANCE => SnmpValue::NoSuchInstance,
        END_OF_MIB_VIEW => SnmpValue::EndOfMibView,
        SEQUENCE => return Err(BerError("a SEQUENCE is not a value")),
        other => SnmpValue::Unsupported(other),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(v: SnmpValue) {
        let mut out = Vec::new();
        put_value(&mut out, &v);
        let (tag, c) = Reader::new(&out).tlv().unwrap();
        assert_eq!(decode_value(tag, c).unwrap(), v);
    }

    #[test]
    fn values_roundtrip() {
        for v in [
            SnmpValue::Integer(0),
            SnmpValue::Integer(-1),
            SnmpValue::Integer(127),
            SnmpValue::Integer(128),
            SnmpValue::Integer(i32::MIN),
            SnmpValue::Integer(i32::MAX),
            SnmpValue::OctetString(b"abc".to_vec()),
            SnmpValue::Null,
            SnmpValue::Oid(Oid::parse("1.3.6.1.2.1.1.3.0").unwrap()),
            SnmpValue::Oid(Oid::parse("2.999.3").unwrap()),
            SnmpValue::IpAddress([10, 0, 0, 1]),
            SnmpValue::Counter32(u32::MAX),
            SnmpValue::Gauge32(0x80),
            SnmpValue::TimeTicks(12345),
            SnmpValue::Opaque(vec![1, 2]),
            SnmpValue::Counter64(u64::MAX),
            SnmpValue::NoSuchObject,
            SnmpValue::NoSuchInstance,
            SnmpValue::EndOfMibView,
        ] {
            roundtrip(v);
        }
    }

    #[test]
    fn known_encodings() {
        let mut out = Vec::new();
        put_uint(&mut out, COUNTER32, u64::from(u32::MAX));
        assert_eq!(out, [0x41, 0x05, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]);
        let mut out = Vec::new();
        put_int(&mut out, INTEGER, 128);
        assert_eq!(out, [0x02, 0x02, 0x00, 0x80]);
        let mut out = Vec::new();
        put_int(&mut out, INTEGER, -129);
        assert_eq!(out, [0x02, 0x02, 0xFF, 0x7F]);
        let mut out = Vec::new();
        put_oid(&mut out, &Oid::parse("1.3.6.1.4.1.311").unwrap());
        assert_eq!(out, [0x06, 0x07, 0x2B, 0x06, 0x01, 0x04, 0x01, 0x82, 0x37]);
        // long length form
        let mut out = Vec::new();
        tlv(&mut out, OCTET_STRING, &[0u8; 300]);
        assert_eq!(&out[..4], &[0x04, 0x82, 0x01, 0x2C]);
        assert_eq!(Reader::new(&out).tlv().unwrap().1.len(), 300);
    }

    #[test]
    fn oid_forms() {
        let want = Oid(vec![1, 3, 6, 1, 2, 1, 1, 3, 0]);
        for s in [
            "1.3.6.1.2.1.1.3.0",
            ".1.3.6.1.2.1.1.3.0",
            "iso.3.6.1.2.1.1.3.0",
        ] {
            assert_eq!(Oid::parse(s).unwrap(), want, "{s}");
        }
        assert_eq!(want.to_string(), "1.3.6.1.2.1.1.3.0");
        for bad in [
            "",
            "1",
            "3.1",
            "1.40",
            "1..3",
            "1.3.x",
            "1.3.4294967296",
            "isox.3",
            "1.3.",
        ] {
            assert!(Oid::parse(bad).is_err(), "{bad}");
        }
        assert!(Oid::parse(&format!("1.3{}", ".1".repeat(127))).is_err());
        assert!(Oid(vec![1, 3, 6]) < Oid(vec![1, 3, 6, 0]));
        assert!(Oid(vec![1, 3, 6, 2]) > Oid(vec![1, 3, 6, 1, 9]));
    }

    #[test]
    fn rejects_malformed() {
        for bad in [
            &[][..],
            &[0x02],
            &[0x02, 0x05, 1],
            &[0x02, 0x80],
            &[0x02, 0x85, 0, 0, 0, 0, 1],
            &[0x1F, 0x01, 0x00],
        ] {
            assert!(Reader::new(bad).tlv().is_err(), "{bad:?}");
        }
        assert!(decode_value(COUNTER32, &[0x01, 0x00, 0x00, 0x00, 0x00]).is_err());
        assert!(decode_value(INTEGER, &[0x00, 0x80, 0x00, 0x00, 0x00]).is_err());
        assert!(decode_value(IP_ADDRESS, &[1, 2, 3]).is_err());
        assert!(decode_oid(&[0x2B, 0x86]).is_err());
        assert!(decode_oid(&[0x8F, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]).is_err());
    }

    /// Random input never panics the decoder.
    #[test]
    fn random_bytes_do_not_panic() {
        let mut x: u64 = 0x9E37_79B9_7F4A_7C15;
        for _ in 0..20_000 {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let n = (x % 64) as usize;
            let bytes: Vec<u8> = (0..n)
                .map(|i| (x.rotate_left(i as u32 * 7) & 0xFF) as u8)
                .collect();
            let mut r = Reader::new(&bytes);
            while let Ok((tag, c)) = r.tlv() {
                let _ = decode_value(tag, c);
                let _ = decode_oid(c);
            }
        }
    }
}
