//! BACnet/IP wire codec (ASHRAE 135): BVLC (Annex J), NPDU (clause 6),
//! APDU headers (clause 20.1) and the application-tag codec (clause 20.2),
//! with the services this link uses: Who-Is / I-Am, ReadProperty,
//! ReadPropertyMultiple and WriteProperty, and the Error, Reject and Abort
//! PDUs. No segmentation: a segmented reply is refused by the caller.
//!
//! Pure functions over byte slices; every decoder checks lengths and
//! returns [`CodecError`] instead of panicking on short or bad input.

use std::fmt;
use std::net::{Ipv4Addr, SocketAddrV4};

/// BACnet/IP UDP port (0xBAC0).
pub const DEFAULT_PORT: u16 = 47808;
/// Largest APDU on BACnet/IP without segmentation.
pub const MAX_APDU: u16 = 1476;
/// Instance numbers: 0…4194302; 4194303 is the "any device" wildcard.
pub const MAX_INSTANCE: u32 = 0x3F_FFFE;
pub const WILDCARD_INSTANCE: u32 = 0x3F_FFFF;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CodecError(pub String);

impl fmt::Display for CodecError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for CodecError {}

fn err<T>(m: impl Into<String>) -> Result<T> {
    Err(CodecError(m.into()))
}

pub type Result<T> = std::result::Result<T, CodecError>;

// ---------------------------------------------------------------- object ids

/// A BACnet object identifier: 10-bit type, 22-bit instance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ObjectId {
    pub ty: u16,
    pub instance: u32,
}

impl ObjectId {
    pub const DEVICE: u16 = 8;

    pub fn new(ty: u16, instance: u32) -> Self {
        Self { ty, instance }
    }

    pub fn raw(self) -> u32 {
        (u32::from(self.ty & 0x3FF) << 22) | (self.instance & 0x3F_FFFF)
    }

    pub fn from_raw(v: u32) -> Self {
        Self {
            ty: (v >> 22) as u16,
            instance: v & 0x3F_FFFF,
        }
    }
}

impl fmt::Display for ObjectId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match object_type_name(self.ty) {
            Some(n) => write!(f, "{n}:{}", self.instance),
            None => write!(f, "{}:{}", self.ty, self.instance),
        }
    }
}

// ---------------------------------------------------------------- app values

/// A decoded application-tagged value (clause 20.2).
#[derive(Debug, Clone, PartialEq)]
pub enum AppValue {
    Null,
    Boolean(bool),
    Unsigned(u64),
    Signed(i64),
    Real(f32),
    Double(f64),
    OctetString(Vec<u8>),
    CharString(String),
    /// Bits in order (bit 0 first).
    BitString(Vec<bool>),
    Enumerated(u32),
    /// `(year, month, day, weekday)`; 255 = unspecified (year as 1900 + octet).
    Date(u8, u8, u8, u8),
    /// `(hour, minute, second, hundredths)`; 255 = unspecified.
    Time(u8, u8, u8, u8),
    ObjectId(ObjectId),
    /// A context-tagged primitive inside a constructed value (raw content).
    Context(u8, Vec<u8>),
    /// A constructed value: the items between an opening and a closing
    /// context tag.
    Constructed(u8, Vec<AppValue>),
}

impl AppValue {
    /// Name of the application tag, for error texts.
    pub fn tag_name(&self) -> &'static str {
        match self {
            AppValue::Null => "NULL",
            AppValue::Boolean(_) => "BOOLEAN",
            AppValue::Unsigned(_) => "UNSIGNED",
            AppValue::Signed(_) => "SIGNED",
            AppValue::Real(_) => "REAL",
            AppValue::Double(_) => "DOUBLE",
            AppValue::OctetString(_) => "OCTET STRING",
            AppValue::CharString(_) => "CHARACTER STRING",
            AppValue::BitString(_) => "BIT STRING",
            AppValue::Enumerated(_) => "ENUMERATED",
            AppValue::Date(..) => "DATE",
            AppValue::Time(..) => "TIME",
            AppValue::ObjectId(_) => "OBJECT IDENTIFIER",
            AppValue::Context(..) => "context-tagged value",
            AppValue::Constructed(..) => "constructed value",
        }
    }
}

// ---------------------------------------------------------------- tag codec

/// Application tag numbers.
pub mod tag {
    pub const NULL: u8 = 0;
    pub const BOOLEAN: u8 = 1;
    pub const UNSIGNED: u8 = 2;
    pub const SIGNED: u8 = 3;
    pub const REAL: u8 = 4;
    pub const DOUBLE: u8 = 5;
    pub const OCTET_STRING: u8 = 6;
    pub const CHAR_STRING: u8 = 7;
    pub const BIT_STRING: u8 = 8;
    pub const ENUMERATED: u8 = 9;
    pub const DATE: u8 = 10;
    pub const TIME: u8 = 11;
    pub const OBJECT_ID: u8 = 12;
}

/// A tag header as read from the wire.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tag {
    /// Application tag `number` with `len` content octets (for BOOLEAN,
    /// `len` is the value and there is no content).
    App {
        number: u8,
        len: usize,
    },
    /// Context tag `number` with `len` content octets.
    Context {
        number: u8,
        len: usize,
    },
    Open(u8),
    Close(u8),
}

fn put_header(out: &mut Vec<u8>, number: u8, context: bool, lvt: usize) {
    let class = if context { 0x08 } else { 0x00 };
    let (first_num, ext_num) = if number <= 14 {
        (number << 4, None)
    } else {
        (0xF0, Some(number))
    };
    if lvt <= 4 {
        out.push(first_num | class | lvt as u8);
        out.extend(ext_num);
    } else {
        out.push(first_num | class | 5);
        out.extend(ext_num);
        if lvt <= 253 {
            out.push(lvt as u8);
        } else if lvt <= 0xFFFF {
            out.push(254);
            out.extend_from_slice(&(lvt as u16).to_be_bytes());
        } else {
            out.push(255);
            out.extend_from_slice(&(lvt as u32).to_be_bytes());
        }
    }
}

fn unsigned_bytes(v: u64) -> Vec<u8> {
    let b = v.to_be_bytes();
    let skip = b.iter().take(7).take_while(|x| **x == 0).count();
    b[skip..].to_vec()
}

fn signed_bytes(v: i64) -> Vec<u8> {
    let b = v.to_be_bytes();
    let mut skip = 0;
    // Drop leading octets that only repeat the sign of the next one.
    while skip < 7 {
        let (cur, next) = (b[skip], b[skip + 1]);
        if (cur == 0x00 && next & 0x80 == 0) || (cur == 0xFF && next & 0x80 != 0) {
            skip += 1;
        } else {
            break;
        }
    }
    b[skip..].to_vec()
}

/// Encode an application-tagged value.
pub fn encode_app(out: &mut Vec<u8>, v: &AppValue) {
    match v {
        AppValue::Null => out.push(0x00),
        AppValue::Boolean(b) => out.push(0x10 | u8::from(*b)),
        AppValue::Unsigned(u) => {
            let b = unsigned_bytes(*u);
            put_header(out, tag::UNSIGNED, false, b.len());
            out.extend(b);
        }
        AppValue::Signed(i) => {
            let b = signed_bytes(*i);
            put_header(out, tag::SIGNED, false, b.len());
            out.extend(b);
        }
        AppValue::Real(f) => {
            put_header(out, tag::REAL, false, 4);
            out.extend_from_slice(&f.to_be_bytes());
        }
        AppValue::Double(f) => {
            put_header(out, tag::DOUBLE, false, 8);
            out.extend_from_slice(&f.to_be_bytes());
        }
        AppValue::OctetString(b) => {
            put_header(out, tag::OCTET_STRING, false, b.len());
            out.extend_from_slice(b);
        }
        AppValue::CharString(s) => {
            put_header(out, tag::CHAR_STRING, false, s.len() + 1);
            out.push(0); // ISO 10646 UTF-8
            out.extend_from_slice(s.as_bytes());
        }
        AppValue::BitString(bits) => {
            let bytes = bits.len().div_ceil(8);
            let unused = (bytes * 8 - bits.len()) as u8;
            put_header(out, tag::BIT_STRING, false, bytes + 1);
            out.push(unused);
            for chunk in bits.chunks(8) {
                let mut b = 0u8;
                for (i, on) in chunk.iter().enumerate() {
                    if *on {
                        b |= 0x80 >> i;
                    }
                }
                out.push(b);
            }
        }
        AppValue::Enumerated(e) => {
            let b = unsigned_bytes((*e).into());
            put_header(out, tag::ENUMERATED, false, b.len());
            out.extend(b);
        }
        AppValue::Date(y, m, d, w) => {
            put_header(out, tag::DATE, false, 4);
            out.extend_from_slice(&[*y, *m, *d, *w]);
        }
        AppValue::Time(h, m, s, c) => {
            put_header(out, tag::TIME, false, 4);
            out.extend_from_slice(&[*h, *m, *s, *c]);
        }
        AppValue::ObjectId(o) => {
            put_header(out, tag::OBJECT_ID, false, 4);
            out.extend_from_slice(&o.raw().to_be_bytes());
        }
        AppValue::Context(n, b) => {
            put_header(out, *n, true, b.len());
            out.extend_from_slice(b);
        }
        AppValue::Constructed(n, items) => {
            open(out, *n);
            for i in items {
                encode_app(out, i);
            }
            close(out, *n);
        }
    }
}

/// A context-tagged unsigned (also used for enumerations and property ids).
pub fn ctx_unsigned(out: &mut Vec<u8>, number: u8, v: u64) {
    let b = unsigned_bytes(v);
    put_header(out, number, true, b.len());
    out.extend(b);
}

pub fn ctx_object_id(out: &mut Vec<u8>, number: u8, o: ObjectId) {
    put_header(out, number, true, 4);
    out.extend_from_slice(&o.raw().to_be_bytes());
}

pub fn open(out: &mut Vec<u8>, number: u8) {
    if number <= 14 {
        out.push((number << 4) | 0x0E);
    } else {
        out.extend_from_slice(&[0xFE, number]);
    }
}

pub fn close(out: &mut Vec<u8>, number: u8) {
    if number <= 14 {
        out.push((number << 4) | 0x0F);
    } else {
        out.extend_from_slice(&[0xFF, number]);
    }
}

/// A cursor over tagged data.
#[derive(Debug, Clone)]
pub struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
    /// Constructed values open around the cursor ([`MAX_DEPTH`] at most).
    depth: usize,
}

/// How deep constructed values may nest. BACnet data needs a few levels; a
/// frame nested deeper is refused instead of growing the stack.
pub const MAX_DEPTH: usize = 16;

impl<'a> Reader<'a> {
    pub fn new(buf: &'a [u8]) -> Self {
        Self {
            buf,
            pos: 0,
            depth: 0,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.pos >= self.buf.len()
    }

    fn byte(&mut self) -> Result<u8> {
        let b = *self
            .buf
            .get(self.pos)
            .ok_or_else(|| CodecError("truncated tag".into()))?;
        self.pos += 1;
        Ok(b)
    }

    fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self
            .pos
            .checked_add(n)
            .filter(|e| *e <= self.buf.len())
            .ok_or_else(|| CodecError(format!("truncated value ({n} octets)")))?;
        let s = &self.buf[self.pos..end];
        self.pos = end;
        Ok(s)
    }

    /// Read the next tag header (without its content).
    pub fn tag(&mut self) -> Result<Tag> {
        let first = self.byte()?;
        let mut number = first >> 4;
        if number == 15 {
            number = self.byte()?;
        }
        let context = first & 0x08 != 0;
        let lvt = first & 0x07;
        if context && lvt == 6 {
            return Ok(Tag::Open(number));
        }
        if context && lvt == 7 {
            return Ok(Tag::Close(number));
        }
        // application tags: length 0–4 or extended (5); 6 and 7 do not exist
        if !context && lvt > 5 {
            return err(format!("application tag {number} with L/V/T {lvt}"));
        }
        let len = if lvt == 5 {
            match self.byte()? {
                254 => {
                    let b = self.take(2)?;
                    usize::from(u16::from_be_bytes([b[0], b[1]]))
                }
                255 => {
                    let b = self.take(4)?;
                    u32::from_be_bytes([b[0], b[1], b[2], b[3]]) as usize
                }
                n => usize::from(n),
            }
        } else {
            usize::from(lvt)
        };
        Ok(if context {
            Tag::Context { number, len }
        } else {
            Tag::App { number, len }
        })
    }

    /// The next tag without consuming it.
    pub fn peek(&self) -> Result<Tag> {
        self.clone().tag()
    }

    /// Content octets of a primitive tag just read.
    pub fn content(&mut self, len: usize) -> Result<&'a [u8]> {
        self.take(len)
    }

    /// A context-tagged unsigned with tag `number`.
    pub fn ctx_unsigned(&mut self, number: u8) -> Result<u64> {
        match self.tag()? {
            Tag::Context { number: n, len } if n == number => be_unsigned(self.take(len)?),
            t => err(format!("expected context tag {number}, got {t:?}")),
        }
    }

    /// An optional context-tagged unsigned with tag `number`.
    pub fn opt_ctx_unsigned(&mut self, number: u8) -> Result<Option<u64>> {
        if self.is_empty() {
            return Ok(None);
        }
        match self.peek()? {
            Tag::Context { number: n, .. } if n == number => self.ctx_unsigned(number).map(Some),
            _ => Ok(None),
        }
    }

    pub fn ctx_object_id(&mut self, number: u8) -> Result<ObjectId> {
        match self.tag()? {
            Tag::Context { number: n, len: 4 } if n == number => {
                let b = self.take(4)?;
                Ok(ObjectId::from_raw(u32::from_be_bytes([
                    b[0], b[1], b[2], b[3],
                ])))
            }
            t => err(format!("expected object identifier [{number}], got {t:?}")),
        }
    }

    pub fn expect_open(&mut self, number: u8) -> Result<()> {
        match self.tag()? {
            Tag::Open(n) if n == number => Ok(()),
            t => err(format!("expected opening tag {number}, got {t:?}")),
        }
    }

    pub fn expect_close(&mut self, number: u8) -> Result<()> {
        match self.tag()? {
            Tag::Close(n) if n == number => Ok(()),
            t => err(format!("expected closing tag {number}, got {t:?}")),
        }
    }

    /// Whether the next tag is the closing tag `number` (not consumed).
    pub fn at_close(&self, number: u8) -> bool {
        matches!(self.peek(), Ok(Tag::Close(n)) if n == number)
    }

    /// One application-tagged value, or a constructed value of context tags.
    pub fn value(&mut self) -> Result<AppValue> {
        match self.tag()? {
            Tag::App { number, len } => app_content(number, len, self),
            Tag::Context { number, len } => Ok(AppValue::Context(number, self.take(len)?.to_vec())),
            Tag::Open(n) => {
                if self.depth >= MAX_DEPTH {
                    return err(format!("values nested deeper than {MAX_DEPTH}"));
                }
                self.depth += 1;
                let mut items = Vec::new();
                let r = loop {
                    if self.at_close(n) {
                        break self.expect_close(n);
                    }
                    if self.is_empty() {
                        break err(format!("missing closing tag {n}"));
                    }
                    match self.value() {
                        Ok(v) => items.push(v),
                        Err(e) => break Err(e),
                    }
                };
                self.depth -= 1;
                r.map(|()| AppValue::Constructed(n, items))
            }
            Tag::Close(n) => err(format!("unexpected closing tag {n}")),
        }
    }

    /// Values up to the closing tag `number` (consumed).
    pub fn values_until_close(&mut self, number: u8) -> Result<Vec<AppValue>> {
        let mut out = Vec::new();
        loop {
            if self.is_empty() {
                return err(format!("missing closing tag {number}"));
            }
            if self.at_close(number) {
                self.expect_close(number)?;
                return Ok(out);
            }
            out.push(self.value()?);
        }
    }

    /// An application-tagged ENUMERATED.
    /// An application-tagged ENUMERATED, read directly (no nesting).
    pub fn app_enumerated(&mut self) -> Result<u32> {
        match self.tag()? {
            Tag::App {
                number: tag::ENUMERATED,
                len,
            } => u32::try_from(be_unsigned(self.take(len)?)?)
                .map_err(|_| CodecError("ENUMERATED above 32 bits".into())),
            t => err(format!("expected ENUMERATED, got {t:?}")),
        }
    }

    /// An application-tagged UNSIGNED, read directly (no nesting).
    pub fn app_unsigned(&mut self) -> Result<u64> {
        match self.tag()? {
            Tag::App {
                number: tag::UNSIGNED,
                len,
            } => be_unsigned(self.take(len)?),
            t => err(format!("expected UNSIGNED, got {t:?}")),
        }
    }
}

fn be_unsigned(b: &[u8]) -> Result<u64> {
    if b.is_empty() || b.len() > 8 {
        return err(format!("unsigned of {} octets", b.len()));
    }
    Ok(b.iter().fold(0u64, |a, x| (a << 8) | u64::from(*x)))
}

fn be_signed(b: &[u8]) -> Result<i64> {
    if b.is_empty() || b.len() > 8 {
        return err(format!("signed of {} octets", b.len()));
    }
    let neg = b[0] & 0x80 != 0;
    let mut v: i64 = if neg { -1 } else { 0 };
    for x in b {
        v = (v << 8) | i64::from(*x);
    }
    Ok(v)
}

fn app_content(number: u8, len: usize, r: &mut Reader<'_>) -> Result<AppValue> {
    let four = |b: &[u8]| -> Result<[u8; 4]> {
        b.try_into()
            .map_err(|_| CodecError(format!("expected 4 octets, got {}", b.len())))
    };
    Ok(match number {
        tag::NULL if len == 0 => AppValue::Null,
        tag::NULL => return err(format!("NULL with {len} content octets")),
        tag::BOOLEAN => match len {
            0 => AppValue::Boolean(false),
            1 => AppValue::Boolean(true),
            n => return err(format!("BOOLEAN with value {n}")),
        },
        tag::UNSIGNED => AppValue::Unsigned(be_unsigned(r.take(len)?)?),
        tag::SIGNED => AppValue::Signed(be_signed(r.take(len)?)?),
        tag::REAL => AppValue::Real(f32::from_be_bytes(four(r.take(len)?)?)),
        tag::DOUBLE => {
            let b: [u8; 8] = r
                .take(len)?
                .try_into()
                .map_err(|_| CodecError("DOUBLE of other than 8 octets".into()))?;
            AppValue::Double(f64::from_be_bytes(b))
        }
        tag::OCTET_STRING => AppValue::OctetString(r.take(len)?.to_vec()),
        tag::CHAR_STRING => AppValue::CharString(char_string(r.take(len)?)?),
        tag::BIT_STRING => {
            let b = r.take(len)?;
            let Some((&unused, data)) = b.split_first() else {
                return err("empty BIT STRING");
            };
            if unused > 7 || (data.is_empty() && unused != 0) {
                return err(format!("BIT STRING with {unused} unused bits"));
            }
            let n = data.len() * 8 - usize::from(unused);
            AppValue::BitString(
                (0..n)
                    .map(|i| data[i / 8] & (0x80 >> (i % 8)) != 0)
                    .collect(),
            )
        }
        tag::ENUMERATED => {
            let v = be_unsigned(r.take(len)?)?;
            AppValue::Enumerated(
                u32::try_from(v).map_err(|_| CodecError("ENUMERATED above 32 bits".into()))?,
            )
        }
        tag::DATE => {
            let b = four(r.take(len)?)?;
            AppValue::Date(b[0], b[1], b[2], b[3])
        }
        tag::TIME => {
            let b = four(r.take(len)?)?;
            AppValue::Time(b[0], b[1], b[2], b[3])
        }
        tag::OBJECT_ID => {
            AppValue::ObjectId(ObjectId::from_raw(u32::from_be_bytes(four(r.take(len)?)?)))
        }
        n => return err(format!("reserved application tag {n}")),
    })
}

/// A CHARACTER STRING's content: character set octet, then the text.
fn char_string(b: &[u8]) -> Result<String> {
    let Some((&set, text)) = b.split_first() else {
        return err("empty CHARACTER STRING");
    };
    match set {
        // ISO 10646 (UTF-8); ANSI X3.4 is its ASCII subset.
        0 => Ok(String::from_utf8_lossy(text).into_owned()),
        // ISO 10646 UCS-4
        3 => {
            if !text.len().is_multiple_of(4) {
                return err("UCS-4 string of odd length");
            }
            Ok(text
                .chunks(4)
                .map(|c| {
                    char::from_u32(u32::from_be_bytes([c[0], c[1], c[2], c[3]]))
                        .unwrap_or(char::REPLACEMENT_CHARACTER)
                })
                .collect())
        }
        // ISO 10646 UCS-2
        4 => {
            if !text.len().is_multiple_of(2) {
                return err("UCS-2 string of odd length");
            }
            let units: Vec<u16> = text
                .chunks(2)
                .map(|c| u16::from_be_bytes([c[0], c[1]]))
                .collect();
            Ok(String::from_utf16_lossy(&units))
        }
        // ISO 8859-1
        5 => Ok(text.iter().map(|b| char::from(*b)).collect()),
        n => err(format!("character set {n} is not supported")),
    }
}

// ---------------------------------------------------------------- BVLC

pub mod bvlc {
    pub const TYPE: u8 = 0x81;
    pub const RESULT: u8 = 0x00;
    pub const FORWARDED_NPDU: u8 = 0x04;
    pub const REGISTER_FOREIGN_DEVICE: u8 = 0x05;
    pub const DISTRIBUTE_BROADCAST: u8 = 0x09;
    pub const ORIGINAL_UNICAST: u8 = 0x0A;
    pub const ORIGINAL_BROADCAST: u8 = 0x0B;
    /// BVLC-Result code of a refused registration.
    pub const REGISTER_NAK: u16 = 0x0030;
}

/// One BVLC message.
#[derive(Debug, Clone, PartialEq)]
pub enum Bvlc<'a> {
    Result(u16),
    RegisterForeignDevice(u16),
    /// An NPDU; `origin` is the original source of a Forwarded-NPDU.
    Npdu {
        function: u8,
        origin: Option<SocketAddrV4>,
        npdu: &'a [u8],
    },
    Other(u8),
}

pub fn bvlc_wrap(function: u8, payload: &[u8]) -> Vec<u8> {
    let len = (payload.len() + 4) as u16;
    let mut out = Vec::with_capacity(payload.len() + 4);
    out.extend_from_slice(&[bvlc::TYPE, function]);
    out.extend_from_slice(&len.to_be_bytes());
    out.extend_from_slice(payload);
    out
}

/// A Forwarded-NPDU from `origin` (what a BBMD sends; the simulator too).
pub fn bvlc_forwarded(origin: SocketAddrV4, npdu: &[u8]) -> Vec<u8> {
    let mut p = Vec::with_capacity(npdu.len() + 6);
    p.extend_from_slice(&origin.ip().octets());
    p.extend_from_slice(&origin.port().to_be_bytes());
    p.extend_from_slice(npdu);
    bvlc_wrap(bvlc::FORWARDED_NPDU, &p)
}

pub fn bvlc_register(ttl_s: u16) -> Vec<u8> {
    bvlc_wrap(bvlc::REGISTER_FOREIGN_DEVICE, &ttl_s.to_be_bytes())
}

pub fn bvlc_result(code: u16) -> Vec<u8> {
    bvlc_wrap(bvlc::RESULT, &code.to_be_bytes())
}

pub fn parse_bvlc(b: &[u8]) -> Result<Bvlc<'_>> {
    if b.len() < 4 || b[0] != bvlc::TYPE {
        return err("not a BACnet/IP frame");
    }
    let len = usize::from(u16::from_be_bytes([b[2], b[3]]));
    if len != b.len() {
        return err(format!("BVLC length {len}, frame {}", b.len()));
    }
    let body = &b[4..];
    let u16_at = |i: usize| -> Result<u16> {
        body.get(i..i + 2)
            .map(|s| u16::from_be_bytes([s[0], s[1]]))
            .ok_or_else(|| CodecError("short BVLC".into()))
    };
    Ok(match b[1] {
        bvlc::RESULT => Bvlc::Result(u16_at(0)?),
        bvlc::REGISTER_FOREIGN_DEVICE => Bvlc::RegisterForeignDevice(u16_at(0)?),
        bvlc::FORWARDED_NPDU => {
            if body.len() < 6 {
                return err("short Forwarded-NPDU");
            }
            let ip = Ipv4Addr::new(body[0], body[1], body[2], body[3]);
            let port = u16::from_be_bytes([body[4], body[5]]);
            Bvlc::Npdu {
                function: b[1],
                origin: Some(SocketAddrV4::new(ip, port)),
                npdu: &body[6..],
            }
        }
        f @ (bvlc::ORIGINAL_UNICAST | bvlc::ORIGINAL_BROADCAST | bvlc::DISTRIBUTE_BROADCAST) => {
            Bvlc::Npdu {
                function: f,
                origin: None,
                npdu: body,
            }
        }
        f => Bvlc::Other(f),
    })
}

// ---------------------------------------------------------------- NPDU

/// A remote BACnet network address (behind a router): network number and
/// MAC (empty MAC = broadcast on that network).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct NetAddr {
    pub net: u16,
    pub mac: Vec<u8>,
}

/// Global broadcast network number.
pub const GLOBAL_NET: u16 = 0xFFFF;

/// NPDU header fields this link uses.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Npdu<'a> {
    pub dest: Option<NetAddr>,
    pub source: Option<NetAddr>,
    pub expecting_reply: bool,
    /// A network-layer message (not an APDU): ignored by this link.
    pub network_message: bool,
    pub apdu: &'a [u8],
}

/// NPDU header: version 1, control, optional DNET/DADR and hop count.
pub fn npdu_header(out: &mut Vec<u8>, dest: Option<&NetAddr>, expecting_reply: bool) {
    let mut control = 0u8;
    if dest.is_some() {
        control |= 0x20;
    }
    if expecting_reply {
        control |= 0x04;
    }
    out.extend_from_slice(&[0x01, control]);
    if let Some(d) = dest {
        out.extend_from_slice(&d.net.to_be_bytes());
        out.push(d.mac.len() as u8);
        out.extend_from_slice(&d.mac);
        out.push(0xFF); // hop count
    }
}

/// NPDU with a source network (what a router puts on a reply; the
/// simulator uses it for a routed device).
pub fn npdu_header_from(out: &mut Vec<u8>, source: &NetAddr) {
    out.extend_from_slice(&[0x01, 0x08]);
    out.extend_from_slice(&source.net.to_be_bytes());
    out.push(source.mac.len() as u8);
    out.extend_from_slice(&source.mac);
}

pub fn parse_npdu(b: &[u8]) -> Result<Npdu<'_>> {
    if b.len() < 2 || b[0] != 0x01 {
        return err("not an NPDU (version)");
    }
    let control = b[1];
    let mut i = 2;
    let addr = |i: &mut usize| -> Result<NetAddr> {
        let h = b
            .get(*i..*i + 3)
            .ok_or_else(|| CodecError("short NPDU address".into()))?;
        let net = u16::from_be_bytes([h[0], h[1]]);
        let len = usize::from(h[2]);
        let mac = b
            .get(*i + 3..*i + 3 + len)
            .ok_or_else(|| CodecError("short NPDU MAC".into()))?
            .to_vec();
        *i += 3 + len;
        Ok(NetAddr { net, mac })
    };
    let dest = if control & 0x20 != 0 {
        Some(addr(&mut i)?)
    } else {
        None
    };
    let source = if control & 0x08 != 0 {
        Some(addr(&mut i)?)
    } else {
        None
    };
    if dest.is_some() {
        i += 1; // hop count
    }
    let network_message = control & 0x80 != 0;
    if i > b.len() {
        return err("short NPDU");
    }
    Ok(Npdu {
        dest,
        source,
        expecting_reply: control & 0x04 != 0,
        network_message,
        apdu: &b[i..],
    })
}

// ---------------------------------------------------------------- APDU

pub mod service {
    // confirmed
    pub const READ_PROPERTY: u8 = 12;
    pub const READ_PROPERTY_MULTIPLE: u8 = 14;
    pub const WRITE_PROPERTY: u8 = 15;
    // unconfirmed
    pub const I_AM: u8 = 0;
    pub const WHO_IS: u8 = 8;
}

/// Max-APDU-length-accepted codes (clause 20.1.2.5).
const APDU_SIZES: [u16; 6] = [50, 128, 206, 480, 1024, 1476];

/// The largest size code that fits `max` octets.
pub fn max_apdu_code(max: u16) -> u8 {
    APDU_SIZES.iter().rposition(|s| *s <= max).unwrap_or(0) as u8
}

pub fn apdu_size(code: u8) -> u16 {
    APDU_SIZES
        .get(usize::from(code & 0x0F))
        .copied()
        .unwrap_or(MAX_APDU)
}

/// A confirmed request: not segmented, segmented reply not accepted.
pub fn confirmed_request(invoke_id: u8, service: u8, max_apdu: u16, data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() + 4);
    out.extend_from_slice(&[0x00, max_apdu_code(max_apdu), invoke_id, service]);
    out.extend_from_slice(data);
    out
}

pub fn unconfirmed_request(service: u8, data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() + 2);
    out.extend_from_slice(&[0x10, service]);
    out.extend_from_slice(data);
    out
}

/// A decoded APDU.
#[derive(Debug, Clone, PartialEq)]
pub enum Apdu<'a> {
    ConfirmedRequest {
        invoke_id: u8,
        service: u8,
        segmented: bool,
        max_apdu: u16,
        data: &'a [u8],
    },
    Unconfirmed {
        service: u8,
        data: &'a [u8],
    },
    SimpleAck {
        invoke_id: u8,
        service: u8,
    },
    ComplexAck {
        invoke_id: u8,
        service: u8,
        segmented: bool,
        data: &'a [u8],
    },
    SegmentAck {
        invoke_id: u8,
    },
    Error {
        invoke_id: u8,
        service: u8,
        class: u32,
        code: u32,
    },
    Reject {
        invoke_id: u8,
        reason: u8,
    },
    Abort {
        invoke_id: u8,
        server: bool,
        reason: u8,
    },
}

impl Apdu<'_> {
    /// The invoke id of a reply to a confirmed request.
    pub fn reply_invoke_id(&self) -> Option<u8> {
        match self {
            Apdu::SimpleAck { invoke_id, .. }
            | Apdu::ComplexAck { invoke_id, .. }
            | Apdu::SegmentAck { invoke_id }
            | Apdu::Error { invoke_id, .. }
            | Apdu::Reject { invoke_id, .. } => Some(*invoke_id),
            Apdu::Abort {
                invoke_id, server, ..
            } => server.then_some(*invoke_id),
            Apdu::ConfirmedRequest { .. } | Apdu::Unconfirmed { .. } => None,
        }
    }
}

/// Error class and code of an Error PDU or an RPM property error:
/// application-tagged ENUMERATED twice (some devices wrap them in context
/// tag 0, as the newer error types do; that is accepted).
pub fn read_error(r: &mut Reader<'_>) -> Result<(u32, u32)> {
    let wrapped = matches!(r.peek(), Ok(Tag::Open(0)));
    if wrapped {
        r.expect_open(0)?;
    }
    let class = r.app_enumerated()?;
    let code = r.app_enumerated()?;
    if wrapped {
        r.expect_close(0)?;
    }
    Ok((class, code))
}

pub fn parse_apdu(b: &[u8]) -> Result<Apdu<'_>> {
    let first = *b.first().ok_or_else(|| CodecError("empty APDU".into()))?;
    let at = |i: usize| -> Result<u8> {
        b.get(i)
            .copied()
            .ok_or_else(|| CodecError("short APDU".into()))
    };
    Ok(match first >> 4 {
        0 => {
            let segmented = first & 0x08 != 0;
            let head = if segmented { 6 } else { 4 };
            if b.len() < head {
                return err("short confirmed request");
            }
            Apdu::ConfirmedRequest {
                invoke_id: b[2],
                service: b[head - 1],
                segmented,
                max_apdu: apdu_size(b[1]),
                data: &b[head..],
            }
        }
        1 => Apdu::Unconfirmed {
            service: at(1)?,
            data: &b[2..],
        },
        2 => Apdu::SimpleAck {
            invoke_id: at(1)?,
            service: at(2)?,
        },
        3 => {
            let segmented = first & 0x08 != 0;
            let head = if segmented { 5 } else { 3 };
            if b.len() < head {
                return err("short ComplexACK");
            }
            Apdu::ComplexAck {
                invoke_id: b[1],
                service: b[head - 1],
                segmented,
                data: &b[head..],
            }
        }
        // [type|flags, original invoke id, sequence number, window size]
        4 => Apdu::SegmentAck { invoke_id: at(1)? },
        5 => {
            let invoke_id = at(1)?;
            let service = at(2)?;
            let (class, code) = read_error(&mut Reader::new(&b[3..]))?;
            Apdu::Error {
                invoke_id,
                service,
                class,
                code,
            }
        }
        6 => Apdu::Reject {
            invoke_id: at(1)?,
            reason: at(2)?,
        },
        7 => Apdu::Abort {
            invoke_id: at(1)?,
            server: first & 0x01 != 0,
            reason: at(2)?,
        },
        t => return err(format!("unknown APDU type {t}")),
    })
}

/// Encoders of APDU replies, for the simulator and tests.
pub fn simple_ack(invoke_id: u8, service: u8) -> Vec<u8> {
    vec![0x20, invoke_id, service]
}

pub fn complex_ack(invoke_id: u8, service: u8, data: &[u8]) -> Vec<u8> {
    let mut out = vec![0x30, invoke_id, service];
    out.extend_from_slice(data);
    out
}

pub fn error_pdu(invoke_id: u8, service: u8, class: u32, code: u32) -> Vec<u8> {
    let mut out = vec![0x50, invoke_id, service];
    encode_app(&mut out, &AppValue::Enumerated(class));
    encode_app(&mut out, &AppValue::Enumerated(code));
    out
}

pub fn reject_pdu(invoke_id: u8, reason: u8) -> Vec<u8> {
    vec![0x60, invoke_id, reason]
}

pub fn abort_pdu(invoke_id: u8, reason: u8) -> Vec<u8> {
    vec![0x71, invoke_id, reason]
}

// ---------------------------------------------------------------- services

/// Who-Is with an optional instance range.
pub fn who_is(range: Option<(u32, u32)>) -> Vec<u8> {
    let mut d = Vec::new();
    if let Some((lo, hi)) = range {
        ctx_unsigned(&mut d, 0, lo.into());
        ctx_unsigned(&mut d, 1, hi.into());
    }
    unconfirmed_request(service::WHO_IS, &d)
}

/// The range of a Who-Is (`None` = every device).
pub fn parse_who_is(data: &[u8]) -> Result<Option<(u32, u32)>> {
    if data.is_empty() {
        return Ok(None);
    }
    let mut r = Reader::new(data);
    let lo = r.ctx_unsigned(0)?;
    let hi = r.ctx_unsigned(1)?;
    let fit = |v: u64| u32::try_from(v).map_err(|_| CodecError("Who-Is limit".into()));
    Ok(Some((fit(lo)?, fit(hi)?)))
}

/// What an I-Am says.
#[derive(Debug, Clone, PartialEq)]
pub struct IAm {
    pub device: ObjectId,
    pub max_apdu: u16,
    /// 0 both, 1 transmit, 2 receive, 3 none.
    pub segmentation: u32,
    pub vendor_id: u32,
}

pub fn i_am(a: &IAm) -> Vec<u8> {
    let mut d = Vec::new();
    encode_app(&mut d, &AppValue::ObjectId(a.device));
    encode_app(&mut d, &AppValue::Unsigned(a.max_apdu.into()));
    encode_app(&mut d, &AppValue::Enumerated(a.segmentation));
    encode_app(&mut d, &AppValue::Unsigned(a.vendor_id.into()));
    unconfirmed_request(service::I_AM, &d)
}

pub fn parse_i_am(data: &[u8]) -> Result<IAm> {
    let mut r = Reader::new(data);
    let device = match r.value()? {
        AppValue::ObjectId(o) if o.ty == ObjectId::DEVICE => o,
        v => return err(format!("I-Am: expected a device id, got {}", v.tag_name())),
    };
    let max_apdu = r.app_unsigned()?;
    let segmentation = r.app_enumerated()?;
    let vendor_id = r.app_unsigned()?;
    Ok(IAm {
        device,
        max_apdu: u16::try_from(max_apdu).unwrap_or(u16::MAX),
        segmentation,
        vendor_id: u32::try_from(vendor_id).unwrap_or(u32::MAX),
    })
}

/// One property reference: id and optional array index.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct PropRef {
    pub id: u32,
    pub index: Option<u32>,
}

/// ReadProperty request data.
pub fn read_property(obj: ObjectId, prop: PropRef) -> Vec<u8> {
    let mut d = Vec::new();
    ctx_object_id(&mut d, 0, obj);
    ctx_unsigned(&mut d, 1, prop.id.into());
    if let Some(i) = prop.index {
        ctx_unsigned(&mut d, 2, i.into());
    }
    d
}

fn u32_of(v: u64, what: &str) -> Result<u32> {
    u32::try_from(v).map_err(|_| CodecError(format!("{what} above 32 bits")))
}

/// A ReadProperty request (simulator side).
pub fn parse_read_property(data: &[u8]) -> Result<(ObjectId, PropRef)> {
    let mut r = Reader::new(data);
    let obj = r.ctx_object_id(0)?;
    let id = u32_of(r.ctx_unsigned(1)?, "property id")?;
    let index = r
        .opt_ctx_unsigned(2)?
        .map(|i| u32_of(i, "array index"))
        .transpose()?;
    Ok((obj, PropRef { id, index }))
}

/// ReadProperty-ACK data.
pub fn read_property_ack(obj: ObjectId, prop: PropRef, values: &[AppValue]) -> Vec<u8> {
    let mut d = read_property(obj, prop);
    open(&mut d, 3);
    for v in values {
        encode_app(&mut d, v);
    }
    close(&mut d, 3);
    d
}

/// A ReadProperty-ACK: the object, property and value(s).
pub fn parse_read_property_ack(data: &[u8]) -> Result<(ObjectId, PropRef, Vec<AppValue>)> {
    let mut r = Reader::new(data);
    let obj = r.ctx_object_id(0)?;
    let id = u32_of(r.ctx_unsigned(1)?, "property id")?;
    let index = r
        .opt_ctx_unsigned(2)?
        .map(|i| u32_of(i, "array index"))
        .transpose()?;
    r.expect_open(3)?;
    let values = r.values_until_close(3)?;
    Ok((obj, PropRef { id, index }, values))
}

/// ReadPropertyMultiple request data: per object, its property references.
pub fn read_property_multiple(specs: &[(ObjectId, Vec<PropRef>)]) -> Vec<u8> {
    let mut d = Vec::new();
    for (obj, props) in specs {
        ctx_object_id(&mut d, 0, *obj);
        open(&mut d, 1);
        for p in props {
            ctx_unsigned(&mut d, 0, p.id.into());
            if let Some(i) = p.index {
                ctx_unsigned(&mut d, 1, i.into());
            }
        }
        close(&mut d, 1);
    }
    d
}

/// Size of the request data [`read_property_multiple`] makes.
pub fn rpm_request_size(specs: &[(ObjectId, Vec<PropRef>)]) -> usize {
    read_property_multiple(specs).len()
}

pub fn parse_read_property_multiple(data: &[u8]) -> Result<Vec<(ObjectId, Vec<PropRef>)>> {
    let mut r = Reader::new(data);
    let mut out = Vec::new();
    while !r.is_empty() {
        let obj = r.ctx_object_id(0)?;
        r.expect_open(1)?;
        let mut props = Vec::new();
        while !r.at_close(1) {
            if r.is_empty() {
                return err("RPM: missing closing tag 1");
            }
            let id = u32_of(r.ctx_unsigned(0)?, "property id")?;
            let index = r
                .opt_ctx_unsigned(1)?
                .map(|i| u32_of(i, "array index"))
                .transpose()?;
            props.push(PropRef { id, index });
        }
        r.expect_close(1)?;
        out.push((obj, props));
    }
    Ok(out)
}

/// One result of an RPM-ACK: the values, or the error class and code.
pub type PropResult = std::result::Result<Vec<AppValue>, (u32, u32)>;

/// ReadPropertyMultiple-ACK data (simulator side).
pub fn read_property_multiple_ack(results: &[(ObjectId, Vec<(PropRef, PropResult)>)]) -> Vec<u8> {
    let mut d = Vec::new();
    for (obj, props) in results {
        ctx_object_id(&mut d, 0, *obj);
        open(&mut d, 1);
        for (p, res) in props {
            ctx_unsigned(&mut d, 2, p.id.into());
            if let Some(i) = p.index {
                ctx_unsigned(&mut d, 3, i.into());
            }
            match res {
                Ok(values) => {
                    open(&mut d, 4);
                    for v in values {
                        encode_app(&mut d, v);
                    }
                    close(&mut d, 4);
                }
                Err((class, code)) => {
                    open(&mut d, 5);
                    encode_app(&mut d, &AppValue::Enumerated(*class));
                    encode_app(&mut d, &AppValue::Enumerated(*code));
                    close(&mut d, 5);
                }
            }
        }
        close(&mut d, 1);
    }
    d
}

pub fn parse_read_property_multiple_ack(
    data: &[u8],
) -> Result<Vec<(ObjectId, PropRef, PropResult)>> {
    let mut r = Reader::new(data);
    let mut out = Vec::new();
    while !r.is_empty() {
        let obj = r.ctx_object_id(0)?;
        r.expect_open(1)?;
        while !r.at_close(1) {
            if r.is_empty() {
                return err("RPM-ACK: missing closing tag 1");
            }
            let id = u32_of(r.ctx_unsigned(2)?, "property id")?;
            let index = r
                .opt_ctx_unsigned(3)?
                .map(|i| u32_of(i, "array index"))
                .transpose()?;
            let res = match r.tag()? {
                Tag::Open(4) => Ok(r.values_until_close(4)?),
                Tag::Open(5) => {
                    let e = read_error(&mut r)?;
                    r.expect_close(5)?;
                    Err(e)
                }
                t => return err(format!("RPM-ACK: expected a value or an error, got {t:?}")),
            };
            out.push((obj, PropRef { id, index }, res));
        }
        r.expect_close(1)?;
    }
    Ok(out)
}

/// WriteProperty request data; `priority` 1…16 (`None`: not sent).
pub fn write_property(
    obj: ObjectId,
    prop: PropRef,
    value: &AppValue,
    priority: Option<u8>,
) -> Vec<u8> {
    let mut d = read_property(obj, prop);
    open(&mut d, 3);
    encode_app(&mut d, value);
    close(&mut d, 3);
    if let Some(p) = priority {
        ctx_unsigned(&mut d, 4, p.into());
    }
    d
}

/// A WriteProperty request (simulator side).
pub fn parse_write_property(data: &[u8]) -> Result<(ObjectId, PropRef, AppValue, Option<u8>)> {
    let mut r = Reader::new(data);
    let obj = r.ctx_object_id(0)?;
    let id = u32_of(r.ctx_unsigned(1)?, "property id")?;
    let index = r
        .opt_ctx_unsigned(2)?
        .map(|i| u32_of(i, "array index"))
        .transpose()?;
    r.expect_open(3)?;
    let mut values = r.values_until_close(3)?;
    if values.len() != 1 {
        return err(format!("WriteProperty with {} values", values.len()));
    }
    let priority = r
        .opt_ctx_unsigned(4)?
        .map(|p| u8::try_from(p).map_err(|_| CodecError("priority".into())))
        .transpose()?;
    Ok((obj, PropRef { id, index }, values.remove(0), priority))
}

// ---------------------------------------------------------------- names

/// Property identifiers this link names.
pub mod prop {
    pub const DESCRIPTION: u32 = 28;
    pub const EVENT_STATE: u32 = 36;
    pub const HIGH_LIMIT: u32 = 45;
    pub const LOW_LIMIT: u32 = 59;
    pub const MAX_APDU_LENGTH_ACCEPTED: u32 = 62;
    pub const MAX_PRES_VALUE: u32 = 65;
    pub const MIN_PRES_VALUE: u32 = 69;
    pub const COV_INCREMENT: u32 = 22;
    pub const NUMBER_OF_STATES: u32 = 74;
    pub const OBJECT_IDENTIFIER: u32 = 75;
    pub const OBJECT_LIST: u32 = 76;
    pub const OBJECT_NAME: u32 = 77;
    pub const OBJECT_TYPE: u32 = 79;
    pub const OUT_OF_SERVICE: u32 = 81;
    pub const PRESENT_VALUE: u32 = 85;
    pub const PRIORITY_ARRAY: u32 = 87;
    pub const RELIABILITY: u32 = 103;
    pub const RELINQUISH_DEFAULT: u32 = 104;
    pub const SEGMENTATION_SUPPORTED: u32 = 107;
    pub const STATUS_FLAGS: u32 = 111;
    pub const SYSTEM_STATUS: u32 = 112;
    pub const UNITS: u32 = 117;
    pub const VENDOR_IDENTIFIER: u32 = 120;
}

/// BACnetObjectType names (clause 21), snake_case as this link's params.
const OBJECT_TYPES: [&str; 57] = [
    "analog_input",
    "analog_output",
    "analog_value",
    "binary_input",
    "binary_output",
    "binary_value",
    "calendar",
    "command",
    "device",
    "event_enrollment",
    "file",
    "group",
    "loop",
    "multi_state_input",
    "multi_state_output",
    "notification_class",
    "program",
    "schedule",
    "averaging",
    "multi_state_value",
    "trend_log",
    "life_safety_point",
    "life_safety_zone",
    "accumulator",
    "pulse_converter",
    "event_log",
    "global_group",
    "trend_log_multiple",
    "load_control",
    "structured_view",
    "access_door",
    "timer",
    "access_credential",
    "access_point",
    "access_rights",
    "access_user",
    "access_zone",
    "credential_data_input",
    "network_security",
    "bitstring_value",
    "characterstring_value",
    "date_pattern_value",
    "date_value",
    "datetime_pattern_value",
    "datetime_value",
    "integer_value",
    "large_analog_value",
    "octetstring_value",
    "positive_integer_value",
    "time_pattern_value",
    "time_value",
    "notification_forwarder",
    "alert_enrollment",
    "channel",
    "lighting_output",
    "binary_lighting_output",
    "network_port",
];

pub fn object_type_name(ty: u16) -> Option<&'static str> {
    OBJECT_TYPES.get(usize::from(ty)).copied()
}

const ERROR_CLASSES: [&str; 8] = [
    "device",
    "object",
    "property",
    "resources",
    "security",
    "services",
    "vt",
    "communication",
];

const ERROR_CODES: [&str; 51] = [
    "other",
    "authentication-failed",
    "configuration-in-progress",
    "device-busy",
    "dynamic-creation-not-supported",
    "file-access-denied",
    "incompatible-security-levels",
    "inconsistent-parameters",
    "inconsistent-selection-criterion",
    "invalid-data-type",
    "invalid-file-access-method",
    "invalid-file-start-position",
    "invalid-operator-name",
    "invalid-parameter-data-type",
    "invalid-time-stamp",
    "key-generation-error",
    "missing-required-parameter",
    "no-objects-of-specified-type",
    "no-space-for-object",
    "no-space-to-add-list-element",
    "no-space-to-write-property",
    "no-vt-sessions-available",
    "property-is-not-a-list",
    "object-deletion-not-permitted",
    "object-identifier-already-exists",
    "operational-problem",
    "password-failure",
    "read-access-denied",
    "security-not-supported",
    "service-request-denied",
    "timeout",
    "unknown-object",
    "unknown-property",
    "code-33",
    "unknown-vt-class",
    "unknown-vt-session",
    "unsupported-object-type",
    "value-out-of-range",
    "vt-session-already-closed",
    "vt-session-termination-failure",
    "write-access-denied",
    "character-set-not-supported",
    "invalid-array-index",
    "cov-subscription-failed",
    "not-cov-property",
    "optional-functionality-not-supported",
    "invalid-configuration-data",
    "datatype-not-supported",
    "duplicate-name",
    "duplicate-object-id",
    "property-is-not-an-array",
];

/// Error class codes and error codes this link reacts to.
pub mod error {
    pub const CLASS_OBJECT: u32 = 1;
    pub const CLASS_PROPERTY: u32 = 2;
    pub const CLASS_SERVICES: u32 = 5;
    pub const CODE_OTHER: u32 = 0;
    pub const CODE_SERVICE_REQUEST_DENIED: u32 = 29;
    pub const CODE_UNKNOWN_OBJECT: u32 = 31;
    pub const CODE_UNKNOWN_PROPERTY: u32 = 32;
    pub const CODE_VALUE_OUT_OF_RANGE: u32 = 37;
    pub const CODE_WRITE_ACCESS_DENIED: u32 = 40;
    pub const CODE_INVALID_ARRAY_INDEX: u32 = 42;
    pub const CODE_OPTIONAL_FUNCTIONALITY_NOT_SUPPORTED: u32 = 45;
    pub const CODE_INVALID_DATA_TYPE: u32 = 9;
}

/// `"object: unknown-object"`.
pub fn error_text(class: u32, code: u32) -> String {
    let class = ERROR_CLASSES
        .get(class as usize)
        .map_or_else(|| format!("class-{class}"), |s| (*s).to_owned());
    let code = ERROR_CODES
        .get(code as usize)
        .map_or_else(|| format!("code-{code}"), |s| (*s).to_owned());
    format!("{class}: {code}")
}

const REJECT_REASONS: [&str; 10] = [
    "other",
    "buffer-overflow",
    "inconsistent-parameters",
    "invalid-parameter-data-type",
    "invalid-tag",
    "missing-required-parameter",
    "parameter-out-of-range",
    "too-many-arguments",
    "undefined-enumeration",
    "unrecognized-service",
];

pub mod reject {
    pub const BUFFER_OVERFLOW: u8 = 1;
    pub const UNRECOGNIZED_SERVICE: u8 = 9;
}

pub fn reject_text(reason: u8) -> String {
    REJECT_REASONS
        .get(usize::from(reason))
        .map_or_else(|| format!("reason-{reason}"), |s| (*s).to_owned())
}

const ABORT_REASONS: [&str; 12] = [
    "other",
    "buffer-overflow",
    "invalid-apdu-in-this-state",
    "preempted-by-higher-priority-task",
    "segmentation-not-supported",
    "security-error",
    "insufficient-security",
    "window-size-out-of-range",
    "application-exceeded-reply-time",
    "out-of-resources",
    "tsm-timeout",
    "apdu-too-long",
];

pub mod abort {
    pub const BUFFER_OVERFLOW: u8 = 1;
    pub const SEGMENTATION_NOT_SUPPORTED: u8 = 4;
    pub const APDU_TOO_LONG: u8 = 11;
}

pub fn abort_text(reason: u8) -> String {
    ABORT_REASONS
        .get(usize::from(reason))
        .map_or_else(|| format!("reason-{reason}"), |s| (*s).to_owned())
}

/// BACnetEngineeringUnits: `(code, name, symbol)` for the common units
/// (the names as in clause 21; the symbol is what the link suggests as a
/// point's `unit`).
const UNITS: &[(u32, &str, &str)] = &[
    (0, "square-meters", "m²"),
    (1, "square-feet", "ft²"),
    (2, "milliamperes", "mA"),
    (3, "amperes", "A"),
    (4, "ohms", "Ω"),
    (5, "volts", "V"),
    (6, "kilovolts", "kV"),
    (7, "megavolts", "MV"),
    (8, "volt-amperes", "VA"),
    (9, "kilovolt-amperes", "kVA"),
    (10, "megavolt-amperes", "MVA"),
    (11, "volt-amperes-reactive", "var"),
    (12, "kilovolt-amperes-reactive", "kvar"),
    (13, "megavolt-amperes-reactive", "Mvar"),
    (14, "degrees-phase", "°"),
    (15, "power-factor", "PF"),
    (16, "joules", "J"),
    (17, "kilojoules", "kJ"),
    (18, "watt-hours", "Wh"),
    (19, "kilowatt-hours", "kWh"),
    (20, "btus", "BTU"),
    (21, "therms", "thm"),
    (22, "ton-hours", "ton·h"),
    (27, "hertz", "Hz"),
    (29, "percent-relative-humidity", "%RH"),
    (30, "millimeters", "mm"),
    (31, "meters", "m"),
    (32, "inches", "in"),
    (33, "feet", "ft"),
    (36, "lumens", "lm"),
    (37, "luxes", "lx"),
    (38, "foot-candles", "fc"),
    (39, "kilograms", "kg"),
    (40, "pounds-mass", "lb"),
    (47, "watts", "W"),
    (48, "kilowatts", "kW"),
    (49, "megawatts", "MW"),
    (50, "btus-per-hour", "BTU/h"),
    (51, "horsepower", "hp"),
    (52, "tons-refrigeration", "TR"),
    (53, "pascals", "Pa"),
    (54, "kilopascals", "kPa"),
    (55, "bars", "bar"),
    (56, "pounds-force-per-square-inch", "psi"),
    (57, "centimeters-of-water", "cmH₂O"),
    (58, "inches-of-water", "inH₂O"),
    (59, "millimeters-of-mercury", "mmHg"),
    (62, "degrees-celsius", "°C"),
    (63, "degrees-kelvin", "K"),
    (64, "degrees-fahrenheit", "°F"),
    (67, "years", "a"),
    (68, "months", "mo"),
    (69, "weeks", "wk"),
    (70, "days", "d"),
    (71, "hours", "h"),
    (72, "minutes", "min"),
    (73, "seconds", "s"),
    (74, "meters-per-second", "m/s"),
    (75, "kilometers-per-hour", "km/h"),
    (76, "feet-per-second", "ft/s"),
    (77, "feet-per-minute", "ft/min"),
    (78, "miles-per-hour", "mph"),
    (79, "cubic-feet", "ft³"),
    (80, "cubic-meters", "m³"),
    (81, "imperial-gallons", "imp gal"),
    (82, "liters", "l"),
    (83, "us-gallons", "gal"),
    (84, "cubic-feet-per-minute", "cfm"),
    (85, "cubic-meters-per-second", "m³/s"),
    (87, "liters-per-second", "l/s"),
    (88, "liters-per-minute", "l/min"),
    (89, "us-gallons-per-minute", "gpm"),
    (90, "degrees-angular", "°"),
    (95, "no-units", ""),
    (96, "parts-per-million", "ppm"),
    (97, "parts-per-billion", "ppb"),
    (98, "percent", "%"),
    (104, "revolutions-per-minute", "rpm"),
    (118, "centimeters", "cm"),
    (122, "kilohms", "kΩ"),
    (123, "megohms", "MΩ"),
    (124, "millivolts", "mV"),
    (132, "milliwatts", "mW"),
    (133, "hectopascals", "hPa"),
    (134, "millibars", "mbar"),
    (135, "cubic-meters-per-hour", "m³/h"),
    (136, "liters-per-hour", "l/h"),
    (146, "megawatt-hours", "MWh"),
    (159, "milliseconds", "ms"),
];

/// Name and suggested symbol of an engineering unit (`units-<n>` and an
/// empty symbol for one this link does not know).
pub fn unit(code: u32) -> (String, &'static str) {
    match UNITS.iter().find(|(c, _, _)| *c == code) {
        Some((_, name, sym)) => ((*name).to_owned(), sym),
        None => (format!("units-{code}"), ""),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> Vec<u8> {
        let s: String = s.split_whitespace().collect();
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    fn enc(v: &AppValue) -> Vec<u8> {
        let mut out = Vec::new();
        encode_app(&mut out, v);
        out
    }

    fn dec(b: &[u8]) -> AppValue {
        let mut r = Reader::new(b);
        let v = r.value().unwrap();
        assert!(r.is_empty(), "left over: {b:02X?}");
        v
    }

    /// Clause 20.2 examples of application-tagged values, both ways.
    #[test]
    fn application_tags_from_the_standard() {
        let cases: Vec<(AppValue, &str)> = vec![
            (AppValue::Null, "00"),
            (AppValue::Boolean(false), "10"),
            (AppValue::Boolean(true), "11"),
            (AppValue::Unsigned(72), "21 48"),
            (AppValue::Unsigned(0), "21 00"),
            (AppValue::Unsigned(256), "22 01 00"),
            (AppValue::Unsigned(0x1_0000), "23 01 00 00"),
            (AppValue::Unsigned(u64::from(u32::MAX)), "24 FF FF FF FF"),
            (AppValue::Signed(72), "31 48"),
            (AppValue::Signed(-72), "31 B8"),
            (AppValue::Signed(-129), "32 FF 7F"),
            (AppValue::Signed(128), "32 00 80"),
            (AppValue::Real(72.0), "44 42 90 00 00"),
            (AppValue::Double(72.0), "55 08 40 52 00 00 00 00 00 00"),
            (AppValue::OctetString(vec![0x12, 0x34, 0xFF]), "63 12 34 FF"),
            (
                AppValue::BitString(vec![true, false, true, false, true]),
                "82 03 A8",
            ),
            (AppValue::Enumerated(0), "91 00"),
            (AppValue::Enumerated(300), "92 01 2C"),
            (AppValue::Date(91, 1, 24, 4), "A4 5B 01 18 04"),
            (AppValue::Time(17, 35, 45, 17), "B4 11 23 2D 11"),
            (AppValue::ObjectId(ObjectId::new(0, 15)), "C4 00 00 00 0F"),
        ];
        for (v, h) in cases {
            assert_eq!(enc(&v), hex(h), "{v:?}");
            assert_eq!(dec(&hex(h)), v, "{h}");
        }
        // "This is a BACnet string!" (20.2.9): UTF-8, extended length
        let s = "This is a BACnet string!";
        let mut want = hex("75 19 00");
        want.extend_from_slice(s.as_bytes());
        assert_eq!(enc(&AppValue::CharString(s.into())), want);
        assert_eq!(dec(&want), AppValue::CharString(s.into()));
    }

    #[test]
    fn character_sets() {
        // UCS-2 "Aé"
        assert_eq!(
            dec(&hex("75 05 04 00 41 00 E9")),
            AppValue::CharString("Aé".into())
        );
        // ISO 8859-1 "é"
        assert_eq!(dec(&hex("72 05 E9")), AppValue::CharString("é".into()));
        let mut r = Reader::new(&[0x72, 0x02, 0x41]);
        assert!(r.value().unwrap_err().0.contains("character set 2"));
    }

    /// A crafted frame of deeply nested opening tags is refused with an
    /// error, not a stack overflow; nesting within the limit decodes.
    #[test]
    fn deep_nesting_is_refused() {
        for depth in [MAX_DEPTH + 1, 1000, 100_000] {
            let mut b = vec![0x0E; depth];
            b.extend(std::iter::repeat_n(0x0F, depth));
            let e = Reader::new(&b).value().unwrap_err();
            assert!(e.0.contains("nested deeper"), "{depth}: {e}");
            // also inside a ReadProperty-ACK and an RPM-ACK
            let mut ack = hex("0C 00 00 00 05 19 55 3E");
            ack.extend(&b);
            ack.push(0x3F);
            assert!(parse_read_property_ack(&ack).is_err());
            let mut multi = hex("0C 00 00 00 05 1E 29 55 4E");
            multi.extend(&b);
            multi.extend(hex("4F 1F"));
            assert!(parse_read_property_multiple_ack(&multi).is_err());
        }
        let mut ok = vec![0x0E; MAX_DEPTH];
        ok.push(0x21);
        ok.push(0x05);
        ok.extend(std::iter::repeat_n(0x0F, MAX_DEPTH));
        let mut v = Reader::new(&ok).value().unwrap();
        for _ in 1..MAX_DEPTH {
            let AppValue::Constructed(0, mut items) = v else {
                panic!()
            };
            v = items.remove(0);
        }
        assert_eq!(v, AppValue::Constructed(0, vec![AppValue::Unsigned(5)]));
        // an Error PDU's class and code are read directly: an opening tag
        // there is an error, not a nested read
        assert!(parse_apdu(&hex("50 01 0C 1E 1E 1E")).is_err());
        assert!(read_error(&mut Reader::new(&hex("91 01 4E 4E"))).is_err());
    }

    /// Random bytes never panic any decoder (a cheap fuzz).
    #[test]
    fn random_frames_do_not_panic() {
        let mut x: u64 = 0x9E37_79B9_7F4A_7C15;
        let mut next = move || {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x
        };
        for _ in 0..20_000 {
            let n = (next() % 64) as usize;
            let b: Vec<u8> = (0..n)
                .map(|_| {
                    let r = next();
                    // biased towards opening and closing tags
                    match r % 4 {
                        0 => 0x0E,
                        1 => 0x0F,
                        _ => (r >> 8) as u8,
                    }
                })
                .collect();
            let _ = Reader::new(&b).value();
            let _ = parse_apdu(&b);
            let _ = parse_npdu(&b);
            let _ = parse_bvlc(&b);
            let _ = parse_read_property_ack(&b);
            let _ = parse_read_property_multiple_ack(&b);
            let _ = parse_read_property_multiple(&b);
            let _ = parse_write_property(&b);
            let _ = parse_i_am(&b);
        }
    }

    #[test]
    fn long_lengths_and_extended_tag_numbers() {
        let long = vec![7u8; 300];
        let b = enc(&AppValue::OctetString(long.clone()));
        assert_eq!(&b[..4], &[0x65, 254, 0x01, 0x2C]);
        assert_eq!(dec(&b), AppValue::OctetString(long));
        // context tag 20 holding unsigned 5
        let mut out = Vec::new();
        ctx_unsigned(&mut out, 20, 5);
        assert_eq!(out, hex("F9 14 05"));
        let mut r = Reader::new(&out);
        assert_eq!(r.ctx_unsigned(20).unwrap(), 5);
    }

    #[test]
    fn truncated_input_is_an_error_not_a_panic() {
        for b in [
            &[][..],
            &[0x44, 0x42],
            &[0x75, 0x19, 0x00],
            &[0x65, 254],
            &[0x82, 0x09, 0x00],
            &[0x82, 0x01],
            &[0x0E],
            // NULL with a length: its content would be read as tags
            &[0x01, 0x21],
            // application tags with L/V/T 6 and 7 (no such length)
            &[0x46, 0, 0, 0, 0, 0, 0],
            &[0x27, 0, 0, 0, 0, 0, 0, 0],
            &[0x16],
        ] {
            assert!(Reader::new(b).value().is_err(), "{b:02X?}");
        }
        // Segment-ACK: [type, original invoke id, sequence number, window]
        assert_eq!(
            parse_apdu(&[0x40, 7, 3, 1]).unwrap().reply_invoke_id(),
            Some(7)
        );
        assert!(parse_apdu(&[0x50, 0x01]).is_err());
        assert!(parse_npdu(&[0x01, 0x20, 0x00]).is_err());
        assert!(parse_bvlc(&[0x81, 0x0A, 0x00, 0x09, 0x01]).is_err());
    }

    /// Annex F (ReadProperty example): ReadProperty of analog-input 5 present-value; the ACK
    /// carries REAL 72.0.
    #[test]
    fn read_property_example() {
        let req = confirmed_request(
            1,
            service::READ_PROPERTY,
            206,
            &read_property(
                ObjectId::new(0, 5),
                PropRef {
                    id: 85,
                    index: None,
                },
            ),
        );
        assert_eq!(req, hex("00 02 01 0C 0C 00 00 00 05 19 55"));
        let Apdu::ConfirmedRequest {
            invoke_id: 1,
            service: 12,
            max_apdu: 206,
            data,
            ..
        } = parse_apdu(&req).unwrap()
        else {
            panic!()
        };
        assert_eq!(
            parse_read_property(data).unwrap(),
            (
                ObjectId::new(0, 5),
                PropRef {
                    id: 85,
                    index: None
                }
            )
        );
        let ack = hex("30 01 0C 0C 00 00 00 05 19 55 3E 44 42 90 00 00 3F");
        let Apdu::ComplexAck {
            invoke_id: 1,
            service: 12,
            segmented: false,
            data,
        } = parse_apdu(&ack).unwrap()
        else {
            panic!()
        };
        let (obj, p, values) = parse_read_property_ack(data).unwrap();
        assert_eq!((obj, p.id), (ObjectId::new(0, 5), 85));
        assert_eq!(values, vec![AppValue::Real(72.0)]);
        assert_eq!(
            complex_ack(1, 12, &read_property_ack(obj, p, &[AppValue::Real(72.0)])),
            ack
        );
    }

    /// Annex F (ReadPropertyMultiple example): of analog-input 16 present-value
    /// and reliability.
    #[test]
    fn read_property_multiple_example() {
        let specs = vec![(
            ObjectId::new(0, 16),
            vec![
                PropRef {
                    id: 85,
                    index: None,
                },
                PropRef {
                    id: 103,
                    index: None,
                },
            ],
        )];
        let req = confirmed_request(
            0xF1,
            service::READ_PROPERTY_MULTIPLE,
            1024,
            &read_property_multiple(&specs),
        );
        assert_eq!(req, hex("00 04 F1 0E 0C 00 00 00 10 1E 09 55 09 67 1F"));
        assert_eq!(parse_read_property_multiple(&req[4..]).unwrap(), specs);
        let ack = hex("30 F1 0E 0C 00 00 00 10 1E 29 55 4E 44 42 90 00 00 4F 29 67 4E 91 00 4F 1F");
        let Apdu::ComplexAck { data, .. } = parse_apdu(&ack).unwrap() else {
            panic!()
        };
        let r = parse_read_property_multiple_ack(data).unwrap();
        assert_eq!(
            r,
            vec![
                (
                    ObjectId::new(0, 16),
                    PropRef {
                        id: 85,
                        index: None
                    },
                    Ok(vec![AppValue::Real(72.0)])
                ),
                (
                    ObjectId::new(0, 16),
                    PropRef {
                        id: 103,
                        index: None
                    },
                    Ok(vec![AppValue::Enumerated(0)])
                ),
            ]
        );
        // a property error inside the ACK
        let results = vec![(
            ObjectId::new(2, 9),
            vec![
                (
                    PropRef {
                        id: 85,
                        index: Some(3),
                    },
                    Ok(vec![AppValue::Real(1.5)]),
                ),
                (
                    PropRef {
                        id: 117,
                        index: None,
                    },
                    Err((2, 32)),
                ),
            ],
        )];
        let enc = read_property_multiple_ack(&results);
        let back = parse_read_property_multiple_ack(&enc).unwrap();
        assert_eq!(back[1].2, Err((2, 32)));
        assert_eq!(back[0].1.index, Some(3));
    }

    /// Annex F (WriteProperty example): of analog-value 1 present-value 180.0.
    #[test]
    fn write_property_example() {
        let obj = ObjectId::new(2, 1);
        let d = write_property(
            obj,
            PropRef {
                id: 85,
                index: None,
            },
            &AppValue::Real(180.0),
            None,
        );
        let req = confirmed_request(0x59, service::WRITE_PROPERTY, 1024, &d);
        assert_eq!(
            req,
            hex("00 04 59 0F 0C 00 80 00 01 19 55 3E 44 43 34 00 00 3F")
        );
        assert_eq!(simple_ack(0x59, 15), hex("20 59 0F"));
        let with_prio = write_property(
            obj,
            PropRef {
                id: 85,
                index: None,
            },
            &AppValue::Null,
            Some(8),
        );
        assert_eq!(
            parse_write_property(&with_prio).unwrap(),
            (
                obj,
                PropRef {
                    id: 85,
                    index: None
                },
                AppValue::Null,
                Some(8)
            )
        );
    }

    #[test]
    fn who_is_and_i_am() {
        assert_eq!(who_is(None), hex("10 08"));
        assert_eq!(who_is(Some((3, 3))), hex("10 08 09 03 19 03"));
        assert_eq!(parse_who_is(&hex("09 03 19 03")).unwrap(), Some((3, 3)));
        // I-Am of device 3, max APDU 480, segmented both, vendor 99
        let b = hex("10 00 C4 02 00 00 03 22 01 E0 91 00 21 63");
        let Apdu::Unconfirmed { service: 0, data } = parse_apdu(&b).unwrap() else {
            panic!()
        };
        let a = parse_i_am(data).unwrap();
        assert_eq!(
            a,
            IAm {
                device: ObjectId::new(8, 3),
                max_apdu: 480,
                segmentation: 0,
                vendor_id: 99
            }
        );
        assert_eq!(i_am(&a), b);
    }

    #[test]
    fn error_reject_abort() {
        let e = error_pdu(7, 12, 1, 31);
        assert_eq!(e, hex("50 07 0C 91 01 91 1F"));
        assert_eq!(
            parse_apdu(&e).unwrap(),
            Apdu::Error {
                invoke_id: 7,
                service: 12,
                class: 1,
                code: 31
            }
        );
        assert_eq!(error_text(1, 31), "object: unknown-object");
        assert_eq!(error_text(9, 99), "class-9: code-99");
        // wrapped in [0] as the newer error types are
        let w = hex("50 07 0E 0E 91 02 91 20 0F");
        assert!(matches!(
            parse_apdu(&w).unwrap(),
            Apdu::Error {
                class: 2,
                code: 32,
                ..
            }
        ));
        assert_eq!(
            parse_apdu(&reject_pdu(3, 9)).unwrap(),
            Apdu::Reject {
                invoke_id: 3,
                reason: 9
            }
        );
        assert_eq!(reject_text(9), "unrecognized-service");
        let ab = abort_pdu(4, 4);
        let a = parse_apdu(&ab).unwrap();
        assert_eq!(
            a,
            Apdu::Abort {
                invoke_id: 4,
                server: true,
                reason: 4
            }
        );
        assert_eq!(a.reply_invoke_id(), Some(4));
        assert_eq!(abort_text(4), "segmentation-not-supported");
        // an abort from a client is not a reply
        assert_eq!(parse_apdu(&[0x70, 4, 4]).unwrap().reply_invoke_id(), None);
    }

    #[test]
    fn bvlc_and_npdu() {
        // Original-Unicast-NPDU around a confirmed request, local
        let mut npdu = Vec::new();
        npdu_header(&mut npdu, None, true);
        npdu.extend_from_slice(&hex("00 05 01 0C 0C 00 00 00 05 19 55"));
        let frame = bvlc_wrap(bvlc::ORIGINAL_UNICAST, &npdu);
        assert_eq!(&frame[..6], &hex("81 0A 00 11 01 04")[..]);
        let Bvlc::Npdu {
            function: bvlc::ORIGINAL_UNICAST,
            origin: None,
            npdu: n,
        } = parse_bvlc(&frame).unwrap()
        else {
            panic!()
        };
        let n = parse_npdu(n).unwrap();
        assert!(n.expecting_reply && n.dest.is_none() && n.source.is_none());
        assert_eq!(n.apdu[0], 0x00);
        // routed: DNET 5, DADR 07
        let dest = NetAddr {
            net: 5,
            mac: vec![7],
        };
        let mut r = Vec::new();
        npdu_header(&mut r, Some(&dest), true);
        assert_eq!(r, hex("01 24 00 05 01 07 FF"));
        r.extend_from_slice(&[0x10, 0x08]);
        let n = parse_npdu(&r).unwrap();
        assert_eq!(n.dest, Some(dest.clone()));
        assert_eq!(n.apdu, &[0x10, 0x08]);
        // a reply from it: SNET 5, SADR 07
        let mut s = Vec::new();
        npdu_header_from(&mut s, &dest);
        assert_eq!(s, hex("01 08 00 05 01 07"));
        s.extend_from_slice(&[0x20, 1, 15]);
        let n = parse_npdu(&s).unwrap();
        assert_eq!(n.source, Some(dest));
        assert_eq!(n.apdu, &[0x20, 1, 15]);
        // Forwarded-NPDU from 192.168.1.10:47808
        let origin = SocketAddrV4::new(Ipv4Addr::new(192, 168, 1, 10), 47808);
        let f = bvlc_forwarded(origin, &hex("01 00 10 08"));
        assert_eq!(f, hex("81 04 00 0E C0 A8 01 0A BA C0 01 00 10 08"));
        assert!(matches!(
            parse_bvlc(&f).unwrap(),
            Bvlc::Npdu { origin: Some(o), .. } if o == origin
        ));
        // Register-Foreign-Device TTL 300, BVLC-Result NAK
        assert_eq!(bvlc_register(300), hex("81 05 00 06 01 2C"));
        assert_eq!(
            parse_bvlc(&bvlc_result(bvlc::REGISTER_NAK)).unwrap(),
            Bvlc::Result(0x30)
        );
    }

    #[test]
    fn apdu_size_codes() {
        assert_eq!(max_apdu_code(1476), 5);
        assert_eq!(max_apdu_code(1000), 3);
        assert_eq!(max_apdu_code(50), 0);
        assert_eq!(apdu_size(2), 206);
        assert_eq!(apdu_size(15), MAX_APDU);
    }

    #[test]
    fn object_ids_and_names() {
        let o = ObjectId::new(8, MAX_INSTANCE);
        assert_eq!(ObjectId::from_raw(o.raw()), o);
        assert_eq!(o.to_string(), "device:4194302");
        assert_eq!(ObjectId::new(300, 1).to_string(), "300:1");
        assert_eq!(object_type_name(19), Some("multi_state_value"));
        assert_eq!(object_type_name(46), Some("large_analog_value"));
        assert_eq!(unit(62), ("degrees-celsius".into(), "°C"));
        assert_eq!(unit(9999).0, "units-9999");
    }
}
