//! Siemens addresses (`DB10.DBX4.3`, `MW20`, `IB0`, `T5`, `C3`, with an
//! optional `:TYPE` suffix) and S7 data types: parsing, the rules between
//! an address's width letter and its type, and the conversion between the
//! bytes of a PLC area and published values. Pure: no I/O.

use std::fmt;
use wyrm_core::{TypeCode, Value};

/// The highest byte offset the 3-byte S7 address field can carry
/// (`byte << 3 | bit` in 24 bits).
pub const MAX_BYTE: u32 = 0x1F_FFFF;

/// A memory area of the PLC.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Area {
    /// Process image of the inputs (`I`, German `E`).
    Input,
    /// Process image of the outputs (`Q`, German `A`).
    Output,
    /// Bit memory (`M`).
    Marker,
    /// A data block (`DB<n>`).
    Db,
    /// S5 timers (`T<n>`).
    Timer,
    /// S5 counters (`C<n>`, German `Z`).
    Counter,
}

impl Area {
    /// The area code of a Read/Write Var item.
    pub fn code(self) -> u8 {
        match self {
            Area::Input => 0x81,
            Area::Output => 0x82,
            Area::Marker => 0x83,
            Area::Db => 0x84,
            Area::Counter => 0x1C,
            Area::Timer => 0x1D,
        }
    }

    pub fn from_code(c: u8) -> Option<Area> {
        Some(match c {
            0x81 => Area::Input,
            0x82 => Area::Output,
            0x83 => Area::Marker,
            0x84 => Area::Db,
            0x1C => Area::Counter,
            0x1D => Area::Timer,
            _ => return None,
        })
    }

    /// Timers and counters are addressed by number, 2 bytes each.
    pub fn is_tc(self) -> bool {
        matches!(self, Area::Timer | Area::Counter)
    }

    /// Bytes per addressed unit: 1 (a byte), or 2 for a timer or counter.
    pub fn unit_bytes(self) -> u32 {
        if self.is_tc() {
            2
        } else {
            1
        }
    }
}

/// The width letter of an address: `X` (bit), `B`, `W`, `D`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Width {
    Bit,
    Byte,
    Word,
    DWord,
}

/// An S7 data type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DType {
    Bool,
    Byte,
    Word,
    Dword,
    Int,
    Dint,
    Real,
    Lreal,
    /// `STRING[n]`, `n` in 1…254: max length byte, actual length byte, `n`
    /// characters (one byte each).
    String(u8),
    /// S5TIME (BCD time value and time base), in seconds.
    S5time,
    /// TIME (DINT milliseconds), in seconds.
    Time,
    /// DATE_AND_TIME (8 BCD bytes), as RFC 3339 text.
    DateAndTime,
    /// The count of an S5 counter, decoded as 3 BCD digits.
    Counter,
}

/// Names of the `dtype` param, `auto` first.
pub const DTYPE_NAMES: &[&str] = &[
    "auto",
    "bool",
    "byte",
    "word",
    "dword",
    "int",
    "dint",
    "real",
    "lreal",
    "string",
    "s5time",
    "time",
    "date_and_time",
    "counter",
];

/// The longest S7 STRING.
pub const MAX_STRING: u8 = 254;

impl DType {
    /// The `dtype` param name (`string` for every length).
    pub fn name(self) -> &'static str {
        match self {
            DType::Bool => "bool",
            DType::Byte => "byte",
            DType::Word => "word",
            DType::Dword => "dword",
            DType::Int => "int",
            DType::Dint => "dint",
            DType::Real => "real",
            DType::Lreal => "lreal",
            DType::String(_) => "string",
            DType::S5time => "s5time",
            DType::Time => "time",
            DType::DateAndTime => "date_and_time",
            DType::Counter => "counter",
        }
    }

    /// A `dtype` param value; `None` for `auto`. `string` is STRING[254].
    pub fn from_param(s: &str) -> Result<Option<DType>, String> {
        if s == "auto" {
            return Ok(None);
        }
        parse_type(&s.to_ascii_uppercase())
            .map(Some)
            .ok_or_else(|| format!("dtype: unknown {s:?}"))
    }

    /// Bytes one value occupies in the PLC.
    pub fn size(self) -> u32 {
        match self {
            DType::Bool | DType::Byte => 1,
            DType::Word | DType::Int | DType::S5time | DType::Counter => 2,
            DType::Dword | DType::Dint | DType::Real | DType::Time => 4,
            DType::Lreal | DType::DateAndTime => 8,
            DType::String(n) => u32::from(n) + 2,
        }
    }

    /// `scale` and `offset` apply (the value is a number).
    pub fn is_number(self) -> bool {
        !matches!(self, DType::Bool | DType::String(_) | DType::DateAndTime)
    }

    pub fn type_code(self) -> TypeCode {
        match self {
            DType::Bool => TypeCode::Bool,
            DType::String(_) | DType::DateAndTime => TypeCode::String,
            _ => TypeCode::Number,
        }
    }

    /// Same type, a STRING of any length.
    fn same_kind(self, other: DType) -> bool {
        self.name() == other.name()
    }
}

impl fmt::Display for DType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DType::String(n) => write!(f, "STRING[{n}]"),
            other => f.write_str(&other.name().to_ascii_uppercase()),
        }
    }
}

/// A type name of an address suffix (upper case): `REAL`, `STRING[16]`, …
fn parse_type(s: &str) -> Option<DType> {
    Some(match s {
        "BOOL" => DType::Bool,
        "BYTE" => DType::Byte,
        "WORD" => DType::Word,
        "DWORD" => DType::Dword,
        "INT" => DType::Int,
        "DINT" => DType::Dint,
        "REAL" => DType::Real,
        "LREAL" => DType::Lreal,
        "STRING" => DType::String(MAX_STRING),
        "S5TIME" => DType::S5time,
        "TIME" => DType::Time,
        "DATE_AND_TIME" | "DT" => DType::DateAndTime,
        "COUNTER" => DType::Counter,
        _ => {
            let n = s.strip_prefix("STRING[")?.strip_suffix(']')?;
            let n: u8 = digits(n)?.try_into().ok()?;
            if !(1..=MAX_STRING).contains(&n) {
                return None;
            }
            DType::String(n)
        }
    })
}

/// A parsed address.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Address {
    pub area: Area,
    /// The DB number (0 outside [`Area::Db`]).
    pub db: u16,
    /// Byte offset, or the timer/counter number.
    pub start: u32,
    /// Bit 0…7 of a bit address.
    pub bit: u8,
    pub width: Width,
    /// The type of a `:TYPE` suffix.
    pub suffix: Option<DType>,
}

fn digits(s: &str) -> Option<u32> {
    if s.is_empty() || s.len() > 7 || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

impl Address {
    /// Parse Siemens notation (case does not matter): `DB10.DBX4.3`,
    /// `DB10.DBB5`, `DB10.DBW6`, `DB10.DBD8`, `MW20`, `M1.0`, `MX1.0`, `IB0`,
    /// `E0.1`, `QX1.0`, `A1.0`, `T5`, `C3`, `Z3`, with an optional `:TYPE`
    /// (`DB10.DBD8:REAL`, `DB1.DBB0:STRING[16]`).
    pub fn parse(text: &str) -> Result<Address, String> {
        let up = text.trim().to_ascii_uppercase();
        let bad = |why: &str| format!("address {:?}: {why}", text.trim());
        if up.is_empty() {
            return Err(bad("empty"));
        }
        let (loc, suffix) = match up.split_once(':') {
            Some((l, t)) => {
                let t = parse_type(t.trim()).ok_or_else(|| {
                    bad(&format!(
                        "unknown type {:?} after ':' (BOOL, BYTE, WORD, DWORD, INT, DINT, REAL, \
                         LREAL, STRING[n], S5TIME, TIME, DATE_AND_TIME, COUNTER)",
                        t.trim()
                    ))
                })?;
                (l.trim(), Some(t))
            }
            None => (up.as_str(), None),
        };
        let mut a = if let Some(rest) = loc.strip_prefix("DB") {
            let (num, rest) = rest
                .split_once('.')
                .ok_or_else(|| bad("expected DB<n>.DBX/DBB/DBW/DBD<offset>"))?;
            let db = digits(num)
                .and_then(|n| u16::try_from(n).ok())
                .filter(|n| *n > 0)
                .ok_or_else(|| bad("the DB number must be 1…65535"))?;
            let rest = rest
                .strip_prefix("DB")
                .ok_or_else(|| bad("expected DB<n>.DBX/DBB/DBW/DBD<offset>"))?;
            let (width, start, bit) = width_offset(rest, false).map_err(|w| bad(&w))?;
            Address {
                area: Area::Db,
                db,
                start,
                bit,
                width,
                suffix,
            }
        } else {
            let mut chars = loc.chars();
            let area =
                match chars.next() {
                    Some('I' | 'E') => Area::Input,
                    Some('Q' | 'A') => Area::Output,
                    Some('M') => Area::Marker,
                    Some('T') => Area::Timer,
                    Some('C' | 'Z') => Area::Counter,
                    _ => return Err(bad(
                        "unknown area (DB<n>.…, I/E, Q/A, M, T, C/Z: e.g. DB10.DBW6, MW20, IB0, \
                         Q1.0, T5, C3)",
                    )),
                };
            let rest = chars.as_str();
            if area.is_tc() {
                let n = digits(rest)
                    .filter(|n| *n <= u32::from(u16::MAX))
                    .ok_or_else(|| bad("a timer or counter needs a number 0…65535 (T5, C3)"))?;
                Address {
                    area,
                    db: 0,
                    start: n,
                    bit: 0,
                    width: Width::Word,
                    suffix,
                }
            } else {
                let (width, start, bit) = width_offset(rest, true).map_err(|w| bad(&w))?;
                Address {
                    area,
                    db: 0,
                    start,
                    bit,
                    width,
                    suffix,
                }
            }
        };
        if a.start > MAX_BYTE {
            return Err(bad(&format!("the offset must be at most {MAX_BYTE}")));
        }
        if a.area.is_tc() {
            a.width = Width::Word;
        }
        Ok(a)
    }

    /// The type this address holds: its suffix, else `dtype`, else the
    /// width letter's (`X` BOOL, `B` BYTE, `W` WORD, `D` DWORD, `T` S5TIME,
    /// `C` WORD), checked against the width and area.
    pub fn resolve(&self, dtype: Option<DType>) -> Result<DType, String> {
        let t = match (self.suffix, dtype) {
            (Some(s), Some(d)) if !s.same_kind(d) => {
                return Err(format!(
                    "dtype: the address says {s}, dtype says {}",
                    d.name()
                ))
            }
            (Some(s), _) => s,
            (None, Some(d)) => d,
            (None, None) => match (self.area, self.width) {
                (Area::Timer, _) => DType::S5time,
                (Area::Counter, _) => DType::Word,
                (_, Width::Bit) => DType::Bool,
                (_, Width::Byte) => DType::Byte,
                (_, Width::Word) => DType::Word,
                (_, Width::DWord) => DType::Dword,
            },
        };
        let fits = match (self.area, self.width, t) {
            (Area::Timer, _, DType::S5time | DType::Word) => true,
            (Area::Counter, _, DType::Counter | DType::Word) => true,
            (Area::Timer | Area::Counter, _, _) => false,
            (_, _, DType::Counter) => false,
            (_, Width::Bit, DType::Bool) => true,
            (_, Width::Bit, _) | (_, _, DType::Bool) => false,
            (_, Width::Byte, _) => true,
            (_, Width::Word, t) => t.size() == 2,
            (_, Width::DWord, t) => t.size() == 4,
        };
        if !fits {
            let hint = match (self.area, t) {
                (Area::Timer, _) => "a timer holds S5TIME (or WORD, raw)".to_owned(),
                (Area::Counter, _) => "a counter holds COUNTER (BCD) or WORD (raw)".to_owned(),
                (_, DType::Counter) => "COUNTER is for counter addresses (C3)".to_owned(),
                (_, DType::Bool) => "BOOL needs a bit address (DB1.DBX0.0, M1.0)".to_owned(),
                _ if self.width == Width::Bit => {
                    format!("a bit address holds BOOL only, not {t}")
                }
                _ => format!(
                    "{t} takes {} bytes; use {} (or the byte form DBB/MB/IB/QB)",
                    t.size(),
                    match t.size() {
                        2 => "a W address (DBW, MW)",
                        4 => "a D address (DBD, MD)",
                        _ => "the byte form",
                    }
                ),
            };
            return Err(format!("dtype: {hint}"));
        }
        if !self.area.is_tc() && self.start + t.size() - 1 > MAX_BYTE {
            return Err(format!("address: the value runs past byte {MAX_BYTE}"));
        }
        Ok(t)
    }
}

impl fmt::Display for Address {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let w = match self.width {
            Width::Bit => 'X',
            Width::Byte => 'B',
            Width::Word => 'W',
            Width::DWord => 'D',
        };
        match self.area {
            Area::Db => write!(f, "DB{}.DB{w}{}", self.db, self.start)?,
            Area::Timer => write!(f, "T{}", self.start)?,
            Area::Counter => write!(f, "C{}", self.start)?,
            a => {
                let l = match a {
                    Area::Input => 'I',
                    Area::Output => 'Q',
                    _ => 'M',
                };
                write!(f, "{l}{w}{}", self.start)?;
            }
        }
        if self.width == Width::Bit && !self.area.is_tc() {
            write!(f, ".{}", self.bit)?;
        }
        if let Some(t) = self.suffix {
            write!(f, ":{t}")?;
        }
        Ok(())
    }
}

/// `X4.3`, `B5`, `W6`, `D8`, and with `bare_bit` also `4.3` (`M4.3`).
fn width_offset(s: &str, bare_bit: bool) -> Result<(Width, u32, u8), String> {
    let (width, rest) = match s.chars().next() {
        Some('X') => (Width::Bit, s.get(1..).unwrap_or_default()),
        Some('B') => (Width::Byte, s.get(1..).unwrap_or_default()),
        Some('W') => (Width::Word, s.get(1..).unwrap_or_default()),
        Some('D') => (Width::DWord, s.get(1..).unwrap_or_default()),
        Some(c) if bare_bit && c.is_ascii_digit() => (Width::Bit, s),
        _ => return Err("expected X, B, W or D and an offset (DBX4.3, MW20, IB0)".into()),
    };
    match (width, rest.split_once('.')) {
        (Width::Bit, Some((byte, bit))) => {
            let byte = digits(byte).ok_or("the byte offset must be a number")?;
            let bit = digits(bit)
                .filter(|b| *b <= 7)
                .ok_or("the bit number must be 0…7")?;
            Ok((width, byte, bit as u8))
        }
        (Width::Bit, None) => Err("a bit address needs a bit number (X4.3, M1.0)".into()),
        (_, Some(_)) => Err("only a bit address (X) has a bit number".into()),
        (_, None) => {
            let byte = digits(rest).ok_or("the byte offset must be a number")?;
            Ok((width, byte, 0))
        }
    }
}

/// Why a value does not convert.
#[derive(Debug, Clone, PartialEq)]
pub enum ConvError {
    Short,
    BadBcd,
    OutOfRange,
    TypeMismatch,
    NotLatin1,
    /// Not an S7 value of its type (a date that does not exist, a string
    /// longer than its maximum).
    Invalid(String),
}

impl fmt::Display for ConvError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConvError::Short => f.write_str("not enough bytes for the data type"),
            ConvError::BadBcd => f.write_str("invalid BCD digit"),
            ConvError::OutOfRange => f.write_str("value out of range for the data type"),
            ConvError::TypeMismatch => f.write_str("value type does not match the data type"),
            ConvError::NotLatin1 => {
                f.write_str("text has characters outside Latin-1 (S7 STRING is one byte each)")
            }
            ConvError::Invalid(m) => f.write_str(m),
        }
    }
}

/// How values are scaled and timestamps are zoned.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Conv {
    pub scale: f64,
    pub offset: f64,
    /// The PLC clock's offset from UTC in minutes (DATE_AND_TIME).
    pub tz_min: i32,
}

impl Conv {
    pub const RAW: Conv = Conv {
        scale: 1.0,
        offset: 0.0,
        tz_min: 0,
    };

    fn unscaled(&self) -> bool {
        self.scale == 1.0 && self.offset == 0.0
    }

    fn int(&self, x: i64) -> Value {
        if self.unscaled() {
            Value::from(x)
        } else {
            Value::Float(x as f64 * self.scale + self.offset)
        }
    }

    fn float(&self, x: f64) -> Value {
        Value::Float(x * self.scale + self.offset)
    }

    fn raw_int(&self, v: &Value, lo: i64, hi: i64) -> Result<i64, ConvError> {
        let x = if self.unscaled() {
            match v {
                Value::UInt(u) => i64::try_from(*u).map_err(|_| ConvError::OutOfRange)?,
                Value::Int(i) => *i,
                _ => round(self.raw_float(v)?)?,
            }
        } else {
            round(self.raw_float(v)?)?
        };
        if (lo..=hi).contains(&x) {
            Ok(x)
        } else {
            Err(ConvError::OutOfRange)
        }
    }

    fn raw_float(&self, v: &Value) -> Result<f64, ConvError> {
        let f = v.as_f64().ok_or(ConvError::TypeMismatch)?;
        let raw = (f - self.offset) / self.scale;
        if raw.is_finite() {
            Ok(raw)
        } else {
            Err(ConvError::OutOfRange)
        }
    }
}

fn round(f: f64) -> Result<i64, ConvError> {
    let r = f.round();
    if r.abs() < 9.0e18 {
        Ok(r as i64)
    } else {
        Err(ConvError::OutOfRange)
    }
}

/// An f32 as the shortest decimal that reads back as it (`0.1`, not
/// `0.10000000149011612`).
fn f32_value(x: f32) -> f64 {
    if !x.is_finite() {
        return f64::from(x);
    }
    x.to_string().parse().unwrap_or(f64::from(x))
}

fn be<const N: usize>(b: &[u8]) -> Result<[u8; N], ConvError> {
    b.get(..N)
        .and_then(|s| s.try_into().ok())
        .ok_or(ConvError::Short)
}

fn bcd(b: u8) -> Result<u32, ConvError> {
    let (hi, lo) = (b >> 4, b & 0x0F);
    if hi > 9 || lo > 9 {
        return Err(ConvError::BadBcd);
    }
    Ok(u32::from(hi) * 10 + u32::from(lo))
}

fn to_bcd(n: u32) -> u8 {
    ((((n / 10) % 10) << 4) | (n % 10)) as u8
}

/// Bytes of the PLC → published value. `bit` is the bit of a BOOL.
pub fn decode(t: DType, b: &[u8], bit: u8, c: &Conv) -> Result<Value, ConvError> {
    Ok(match t {
        DType::Bool => {
            let x = *b.first().ok_or(ConvError::Short)?;
            Value::Bool((x >> (bit & 7)) & 1 == 1)
        }
        DType::Byte => c.int(i64::from(*b.first().ok_or(ConvError::Short)?)),
        DType::Word => c.int(i64::from(u16::from_be_bytes(be(b)?))),
        DType::Dword => c.int(i64::from(u32::from_be_bytes(be(b)?))),
        DType::Int => c.int(i64::from(i16::from_be_bytes(be(b)?))),
        DType::Dint => c.int(i64::from(i32::from_be_bytes(be(b)?))),
        DType::Real => c.float(f32_value(f32::from_be_bytes(be(b)?))),
        DType::Lreal => c.float(f64::from_be_bytes(be(b)?)),
        DType::S5time => c.float(s5time_seconds(u16::from_be_bytes(be(b)?))?),
        DType::Time => c.float(f64::from(i32::from_be_bytes(be(b)?)) / 1000.0),
        DType::Counter => {
            let w = u16::from_be_bytes(be(b)?);
            if w >> 12 != 0 {
                return Err(ConvError::BadBcd);
            }
            let [hi, lo] = w.to_be_bytes();
            c.int(i64::from(bcd(hi)? * 100 + bcd(lo)?))
        }
        DType::String(n) => Value::Str(decode_string(b, n)?),
        DType::DateAndTime => Value::Str(decode_dt(&be::<8>(b)?, c.tz_min)?),
    })
}

/// A value → the bytes to write. A BOOL is one byte, 0 or 1 (written with
/// the bit transport size); a STRING is its actual length byte and its
/// characters, written from the second byte on (the PLC's maximum length
/// byte is left as it is).
pub fn encode(t: DType, v: &Value, c: &Conv) -> Result<Vec<u8>, ConvError> {
    Ok(match t {
        DType::Bool => match v {
            Value::Bool(on) => vec![u8::from(*on)],
            _ => return Err(ConvError::TypeMismatch),
        },
        DType::Byte => vec![c.raw_int(v, 0, 0xFF)? as u8],
        DType::Word => (c.raw_int(v, 0, 0xFFFF)? as u16).to_be_bytes().to_vec(),
        DType::Dword => (c.raw_int(v, 0, 0xFFFF_FFFF)? as u32)
            .to_be_bytes()
            .to_vec(),
        DType::Int => (c.raw_int(v, i16::MIN.into(), i16::MAX.into())? as i16)
            .to_be_bytes()
            .to_vec(),
        DType::Dint => (c.raw_int(v, i32::MIN.into(), i32::MAX.into())? as i32)
            .to_be_bytes()
            .to_vec(),
        DType::Real => {
            let f = c.raw_float(v)?;
            if f.abs() > f64::from(f32::MAX) {
                return Err(ConvError::OutOfRange);
            }
            (f as f32).to_be_bytes().to_vec()
        }
        DType::Lreal => c.raw_float(v)?.to_be_bytes().to_vec(),
        DType::S5time => s5time_word(c.raw_float(v)?)?.to_be_bytes().to_vec(),
        DType::Time => {
            let ms = round(c.raw_float(v)? * 1000.0)?;
            i32::try_from(ms)
                .map_err(|_| ConvError::OutOfRange)?
                .to_be_bytes()
                .to_vec()
        }
        DType::Counter => {
            let n = c.raw_int(v, 0, 999)? as u32;
            vec![to_bcd(n / 100), to_bcd(n % 100)]
        }
        DType::String(n) => {
            let Value::Str(s) = v else {
                return Err(ConvError::TypeMismatch);
            };
            let mut out = Vec::with_capacity(s.len() + 1);
            out.push(0);
            for ch in s.chars() {
                out.push(u8::try_from(u32::from(ch)).map_err(|_| ConvError::NotLatin1)?);
            }
            let len = out.len() - 1;
            if len > usize::from(n) {
                return Err(ConvError::Invalid(format!(
                    "text of {len} characters does not fit STRING[{n}]"
                )));
            }
            out[0] = len as u8;
            out
        }
        DType::DateAndTime => {
            let Value::Str(s) = v else {
                return Err(ConvError::TypeMismatch);
            };
            encode_dt(s, c.tz_min)?.to_vec()
        }
    })
}

const S5_BASE_MS: [u32; 4] = [10, 100, 1000, 10_000];

/// S5TIME: bits 12–13 the time base (10 ms, 100 ms, 1 s, 10 s), bits 0–11
/// three BCD digits.
pub fn s5time_seconds(w: u16) -> Result<f64, ConvError> {
    let base = S5_BASE_MS[usize::from((w >> 12) & 3)];
    let [hi, lo] = (w & 0x0FFF).to_be_bytes();
    let n = bcd(hi)? * 100 + bcd(lo)?;
    Ok(f64::from(n * base) / 1000.0)
}

/// Seconds → S5TIME with the finest time base that holds them (rounded to
/// it); 0…9990 s.
pub fn s5time_word(s: f64) -> Result<u16, ConvError> {
    if !s.is_finite() || s < 0.0 {
        return Err(ConvError::OutOfRange);
    }
    let ms = s * 1000.0;
    for (i, base) in S5_BASE_MS.iter().enumerate() {
        let n = (ms / f64::from(*base)).round();
        if n <= 999.0 {
            let n = n as u32;
            let w =
                ((i as u32) << 12) | (u32::from(to_bcd(n / 100)) << 8) | u32::from(to_bcd(n % 100));
            return Ok(w as u16);
        }
    }
    Err(ConvError::OutOfRange)
}

fn decode_string(b: &[u8], n: u8) -> Result<String, ConvError> {
    let (max, cur) = (
        *b.first().ok_or(ConvError::Short)?,
        *b.get(1).ok_or(ConvError::Short)?,
    );
    if cur > max {
        return Err(ConvError::Invalid(format!(
            "not an S7 STRING: actual length {cur} is above its maximum {max}"
        )));
    }
    let len = usize::from(cur.min(n));
    let chars = b.get(2..2 + len).ok_or(ConvError::Short)?;
    Ok(chars.iter().map(|&c| char::from(c)).collect())
}

/// Days since 1970-01-01 of a civil date (proleptic Gregorian).
pub fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = i64::from((m + 9) % 12);
    let doy = (153 * mp + 2) / 5 + i64::from(d) - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The civil date of a day count since 1970-01-01.
pub fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn offset_text(tz_min: i32) -> String {
    if tz_min == 0 {
        return "Z".into();
    }
    let sign = if tz_min < 0 { '-' } else { '+' };
    let a = tz_min.unsigned_abs();
    format!("{sign}{:02}:{:02}", a / 60, a % 60)
}

/// DATE_AND_TIME: year (BCD, 90…99 = 19xx, 00…89 = 20xx), month, day, hour,
/// minute, second, milliseconds (3 BCD digits) and the weekday (low
/// nibble). The PLC's wall time with the configured offset.
pub fn decode_dt(b: &[u8; 8], tz_min: i32) -> Result<String, ConvError> {
    let yy = bcd(b[0])?;
    let year = if yy >= 90 { 1900 + yy } else { 2000 + yy };
    let (mo, d, h, mi, s) = (bcd(b[1])?, bcd(b[2])?, bcd(b[3])?, bcd(b[4])?, bcd(b[5])?);
    if b[7] >> 4 > 9 {
        return Err(ConvError::BadBcd);
    }
    let ms = bcd(b[6])? * 10 + u32::from(b[7] >> 4);
    let days = days_from_civil(year.into(), mo, d);
    if !(1..=12).contains(&mo)
        || civil_from_days(days) != (year.into(), mo, d)
        || h > 23
        || mi > 59
        || s > 59
    {
        return Err(ConvError::Invalid(format!(
            "not a DATE_AND_TIME: {year}-{mo:02}-{d:02} {h:02}:{mi:02}:{s:02}"
        )));
    }
    Ok(format!(
        "{year:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}.{ms:03}{}",
        offset_text(tz_min)
    ))
}

/// RFC 3339 (`2026-10-30T12:34:56.789Z`, `…+02:00`; a space for `T`) →
/// DATE_AND_TIME in the PLC's zone (`tz_min`), 1990…2089.
pub fn encode_dt(s: &str, tz_min: i32) -> Result<[u8; 8], ConvError> {
    let bad = || ConvError::Invalid(format!("not an RFC 3339 time: {s:?}"));
    let s = s.trim();
    let num = |a: usize, b: usize| -> Result<u32, ConvError> {
        let part = s.get(a..b).ok_or_else(bad)?;
        if !part.bytes().all(|c| c.is_ascii_digit()) {
            return Err(bad());
        }
        part.parse().map_err(|_| bad())
    };
    let sep = |i: usize, ok: &[u8]| s.as_bytes().get(i).is_some_and(|c| ok.contains(c));
    if !(sep(4, b"-") && sep(7, b"-") && sep(10, b"Tt ") && sep(13, b":") && sep(16, b":")) {
        return Err(bad());
    }
    let (y, mo, d) = (num(0, 4)?, num(5, 7)?, num(8, 10)?);
    let (h, mi, sec) = (num(11, 13)?, num(14, 16)?, num(17, 19)?);
    let mut i = 19;
    let mut ms = 0u32;
    if sep(19, b".") {
        let start = 20;
        let mut end = start;
        while s.as_bytes().get(end).is_some_and(u8::is_ascii_digit) {
            end += 1;
        }
        if end == start {
            return Err(bad());
        }
        let frac = s.get(start..end).ok_or_else(bad)?;
        let three: String = frac.chars().chain("000".chars()).take(3).collect();
        ms = three.parse().map_err(|_| bad())?;
        i = end;
    }
    let zone = s.get(i..).ok_or_else(bad)?;
    let off_min: i64 = match zone {
        "Z" | "z" => 0,
        // `±HH:MM`, checked byte by byte (no slicing of user text)
        z => match *z.as_bytes() {
            [sign @ (b'+' | b'-'), h1, h0, b':', m1, m0]
                if [h1, h0, m1, m0].iter().all(u8::is_ascii_digit) =>
            {
                let digit = |b: u8| i64::from(b - b'0');
                let (hh, mm) = (digit(h1) * 10 + digit(h0), digit(m1) * 10 + digit(m0));
                if hh > 23 || mm > 59 {
                    return Err(bad());
                }
                let m = hh * 60 + mm;
                if sign == b'-' {
                    -m
                } else {
                    m
                }
            }
            _ => return Err(bad()),
        },
    };
    let days = days_from_civil(y.into(), mo, d);
    if !(1..=12).contains(&mo)
        || civil_from_days(days) != (y.into(), mo, d)
        || h > 23
        || mi > 59
        || sec > 59
    {
        return Err(bad());
    }
    // the instant in UTC, then the PLC's wall time
    let secs =
        days * 86_400 + i64::from(h * 3600 + mi * 60 + sec) - off_min * 60 + i64::from(tz_min) * 60;
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400) as u32);
    let (y, mo, d) = civil_from_days(days);
    if !(1990..=2089).contains(&y) {
        return Err(ConvError::Invalid(
            "DATE_AND_TIME holds the years 1990…2089 only".into(),
        ));
    }
    // weekday 1 = Sunday; 1970-01-01 was a Thursday
    let dow = (days + 4).rem_euclid(7) as u8 + 1;
    Ok([
        to_bcd((y % 100) as u32),
        to_bcd(mo),
        to_bcd(d),
        to_bcd(rem / 3600),
        to_bcd(rem / 60 % 60),
        to_bcd(rem % 60),
        to_bcd(ms / 10),
        (((ms % 10) as u8) << 4) | dow,
    ])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(s: &str) -> Address {
        Address::parse(s).unwrap_or_else(|e| panic!("{s}: {e}"))
    }

    fn ty(s: &str) -> Result<DType, String> {
        Address::parse(s)?.resolve(None)
    }

    #[test]
    fn addresses_in_siemens_notation() {
        let a = p("DB10.DBX4.3");
        assert_eq!(
            (a.area, a.db, a.start, a.bit, a.width),
            (Area::Db, 10, 4, 3, Width::Bit)
        );
        assert_eq!(p("db10.dbb5").width, Width::Byte);
        assert_eq!(p("DB10.DBW6").start, 6);
        let d = p("DB10.DBD8:REAL");
        assert_eq!((d.width, d.suffix), (Width::DWord, Some(DType::Real)));
        assert_eq!((p("MW20").area, p("MW20").start), (Area::Marker, 20));
        assert_eq!(p("IB0").area, Area::Input);
        assert_eq!(p("E0.1").area, Area::Input);
        assert_eq!(p("QX1.0").area, Area::Output);
        assert_eq!(p("A1.0").area, Area::Output);
        let m = p("M1.7");
        assert_eq!((m.width, m.start, m.bit), (Width::Bit, 1, 7));
        assert_eq!((p("T5").area, p("T5").start), (Area::Timer, 5));
        assert_eq!((p("C3").area, p("Z3").area), (Area::Counter, Area::Counter));
        assert_eq!(p("DB1.DBB0:STRING[16]").suffix, Some(DType::String(16)));
        assert_eq!(p(" db1.dbb0 : string ").suffix, Some(DType::String(254)));
        for s in [
            "DB10.DBX4.3",
            "DB1.DBD8:REAL",
            "MW20",
            "IX0.1",
            "QB3",
            "T5",
            "C3",
        ] {
            assert_eq!(p(&p(s).to_string()), p(s), "{s}");
        }
        assert_eq!(p("E0.1").to_string(), "IX0.1");
    }

    #[test]
    fn bad_addresses_say_why() {
        for (s, why) in [
            ("", "empty"),
            ("DB0.DBW0", "DB number"),
            ("DB10.DBX4", "bit number"),
            ("DB10.DBX4.8", "0…7"),
            ("DB10.DBW4.1", "only a bit address"),
            ("DB10DBW4", "expected DB<n>"),
            ("DB10.W4", "expected DB<n>"),
            ("MQ4", "expected X, B, W or D"),
            ("X4", "unknown area"),
            ("T", "timer or counter"),
            ("C70000", "timer or counter"),
            ("MW20:FLOAT", "unknown type"),
            ("DB1.DBB0:STRING[255]", "unknown type"),
            ("DB1.DBB0:STRING[0]", "unknown type"),
            ("MB2097152", "at most"),
        ] {
            let e = Address::parse(s).unwrap_err();
            assert!(e.contains(why), "{s}: {e}");
        }
    }

    /// Text from a user never panics the parser (no byte slicing).
    #[test]
    fn non_ascii_addresses_are_errors() {
        for s in [
            "DBé.DBW0",
            "DB1.DBé0",
            "DB1.DBXé.1",
            "DB1.DBX0.é",
            "Mé",
            "MWé",
            "é",
            "Té",
            "DB1.DBW0:é",
            "DB1.DBB0:STRING[é]",
            "ＭW20",
        ] {
            assert!(Address::parse(s).is_err(), "{s}");
        }
        assert!(DType::from_param("réal").is_err());
    }

    #[test]
    fn width_and_type_agree() {
        assert_eq!(ty("DB1.DBX0.0"), Ok(DType::Bool));
        assert_eq!(ty("DB1.DBB0"), Ok(DType::Byte));
        assert_eq!(ty("DB1.DBW0"), Ok(DType::Word));
        assert_eq!(ty("DB1.DBD0"), Ok(DType::Dword));
        assert_eq!(ty("DB1.DBW0:INT"), Ok(DType::Int));
        assert_eq!(ty("DB1.DBW0:S5TIME"), Ok(DType::S5time));
        assert_eq!(ty("DB1.DBD0:DINT"), Ok(DType::Dint));
        assert_eq!(ty("DB1.DBD0:TIME"), Ok(DType::Time));
        assert_eq!(ty("DB1.DBB0:LREAL"), Ok(DType::Lreal));
        assert_eq!(ty("DB1.DBB0:DT"), Ok(DType::DateAndTime));
        assert_eq!(ty("DB1.DBB0:INT"), Ok(DType::Int), "byte form takes any");
        assert_eq!(ty("T1"), Ok(DType::S5time));
        assert_eq!(ty("C1"), Ok(DType::Word));
        assert_eq!(ty("C1:COUNTER"), Ok(DType::Counter));
        for (s, why) in [
            ("DB1.DBW0:REAL", "D address"),
            ("DB1.DBD0:INT", "W address"),
            ("DB1.DBW0:LREAL", "byte form"),
            ("DB1.DBX0.0:BYTE", "BOOL only"),
            ("DB1.DBB0:BOOL", "bit address"),
            ("T1:INT", "timer"),
            ("C1:REAL", "counter"),
            ("MW0:COUNTER", "counter addresses"),
            ("DB1.DBB2097150:DINT", "runs past"),
        ] {
            let e = ty(s).unwrap_err();
            assert!(e.contains(why), "{s}: {e}");
        }
        let a = p("DB1.DBD0:REAL");
        assert_eq!(a.resolve(Some(DType::Real)), Ok(DType::Real));
        assert!(a.resolve(Some(DType::Dint)).unwrap_err().contains("says"));
        let s = p("DB1.DBB0:STRING[8]");
        assert_eq!(s.resolve(Some(DType::String(254))), Ok(DType::String(8)));
        assert_eq!(
            p("DB1.DBB0").resolve(Some(DType::String(254))),
            Ok(DType::String(254))
        );
        assert_eq!(DType::from_param("auto"), Ok(None));
        assert_eq!(DType::from_param("real"), Ok(Some(DType::Real)));
        assert!(DType::from_param("float").is_err());
    }

    fn roundtrip(t: DType, v: Value, bytes: &[u8]) {
        assert_eq!(encode(t, &v, &Conv::RAW).unwrap(), bytes, "{t} encode");
        assert_eq!(decode(t, bytes, 0, &Conv::RAW).unwrap(), v, "{t} decode");
    }

    #[test]
    fn numbers_big_endian() {
        roundtrip(DType::Byte, Value::UInt(0xAB), &[0xAB]);
        roundtrip(DType::Word, Value::UInt(0x1234), &[0x12, 0x34]);
        roundtrip(
            DType::Dword,
            Value::UInt(0xDEAD_BEEF),
            &[0xDE, 0xAD, 0xBE, 0xEF],
        );
        roundtrip(DType::Int, Value::Int(-2), &[0xFF, 0xFE]);
        roundtrip(
            DType::Dint,
            Value::Int(-70_000),
            &(-70_000i32).to_be_bytes(),
        );
        roundtrip(DType::Real, Value::Float(21.5), &21.5f32.to_be_bytes());
        roundtrip(
            DType::Lreal,
            Value::Float(-1.25e300),
            &(-1.25e300f64).to_be_bytes(),
        );
        // a REAL reads as its shortest decimal
        assert_eq!(
            decode(DType::Real, &0.1f32.to_be_bytes(), 0, &Conv::RAW),
            Ok(Value::Float(0.1))
        );
        for (t, v) in [
            (DType::Byte, Value::UInt(256)),
            (DType::Word, Value::Int(-1)),
            (DType::Int, Value::UInt(40_000)),
            (DType::Dint, Value::Float(3e9)),
            (DType::Real, Value::Float(1e39)),
        ] {
            assert_eq!(encode(t, &v, &Conv::RAW), Err(ConvError::OutOfRange), "{t}");
        }
        assert_eq!(
            encode(DType::Word, &Value::from("x"), &Conv::RAW),
            Err(ConvError::TypeMismatch)
        );
    }

    #[test]
    fn bits_and_scaling() {
        assert_eq!(
            decode(DType::Bool, &[0b1000], 3, &Conv::RAW),
            Ok(Value::Bool(true))
        );
        assert_eq!(
            decode(DType::Bool, &[0b1000], 2, &Conv::RAW),
            Ok(Value::Bool(false))
        );
        assert_eq!(
            encode(DType::Bool, &Value::Bool(true), &Conv::RAW),
            Ok(vec![1])
        );
        let c = Conv {
            scale: 0.1,
            offset: -10.0,
            tz_min: 0,
        };
        assert_eq!(
            decode(DType::Int, &315i16.to_be_bytes(), 0, &c),
            Ok(Value::Float(21.5))
        );
        assert_eq!(
            encode(DType::Int, &Value::Float(21.5), &c),
            Ok(315i16.to_be_bytes().to_vec())
        );
    }

    #[test]
    fn s5time_time_counter() {
        // 2 s: base 100 ms (1), 020 → 0x1020
        assert_eq!(s5time_seconds(0x1020), Ok(2.0));
        assert_eq!(s5time_seconds(0x0999), Ok(9.99));
        assert_eq!(s5time_seconds(0x3999), Ok(9990.0));
        assert_eq!(s5time_seconds(0x00A0), Err(ConvError::BadBcd));
        assert_eq!(s5time_word(2.0), Ok(0x0200), "finest base: 200 × 10 ms");
        assert_eq!(s5time_word(9.99), Ok(0x0999));
        assert_eq!(s5time_word(12.34), Ok(0x1123), "rounded to 100 ms");
        assert_eq!(s5time_word(9990.0), Ok(0x3999));
        assert_eq!(s5time_word(9996.0), Err(ConvError::OutOfRange));
        assert_eq!(s5time_word(-1.0), Err(ConvError::OutOfRange));
        roundtrip(DType::S5time, Value::Float(1.5), &[0x01, 0x50]);
        roundtrip(DType::Time, Value::Float(-1.5), &(-1500i32).to_be_bytes());
        roundtrip(DType::Counter, Value::UInt(42), &[0x00, 0x42]);
        roundtrip(DType::Counter, Value::UInt(999), &[0x09, 0x99]);
        assert_eq!(
            decode(DType::Counter, &[0x10, 0x00], 0, &Conv::RAW),
            Err(ConvError::BadBcd)
        );
        assert_eq!(
            encode(DType::Counter, &Value::UInt(1000), &Conv::RAW),
            Err(ConvError::OutOfRange)
        );
    }

    #[test]
    fn strings_latin1_and_bounds() {
        let b = [8, 3, b'A', 0xE9, b'C', 0, 0, 0, 0, 0];
        assert_eq!(
            decode(DType::String(8), &b, 0, &Conv::RAW),
            Ok(Value::from("AéC"))
        );
        // configured shorter than the PLC's: cut to the configured
        assert_eq!(
            decode(DType::String(2), &b, 0, &Conv::RAW),
            Ok(Value::from("Aé"))
        );
        assert!(matches!(
            decode(DType::String(8), &[2, 3, 0, 0, 0], 0, &Conv::RAW),
            Err(ConvError::Invalid(_))
        ));
        assert_eq!(
            encode(DType::String(8), &Value::from("AéC"), &Conv::RAW),
            Ok(vec![3, b'A', 0xE9, b'C'])
        );
        assert_eq!(
            encode(DType::String(8), &Value::from("€"), &Conv::RAW),
            Err(ConvError::NotLatin1)
        );
        assert!(matches!(
            encode(DType::String(2), &Value::from("abc"), &Conv::RAW),
            Err(ConvError::Invalid(_))
        ));
    }

    #[test]
    fn date_and_time() {
        // 2026-10-30 12:34:56.789, a Friday (weekday 6)
        let b = [0x26, 0x10, 0x30, 0x12, 0x34, 0x56, 0x78, 0x96];
        assert_eq!(decode_dt(&b, 0).unwrap(), "2026-10-30T12:34:56.789Z");
        assert_eq!(decode_dt(&b, 120).unwrap(), "2026-10-30T12:34:56.789+02:00");
        assert_eq!(decode_dt(&b, -90).unwrap(), "2026-10-30T12:34:56.789-01:30");
        assert_eq!(encode_dt("2026-10-30T12:34:56.789Z", 0).unwrap(), b);
        assert_eq!(encode_dt("2026-10-30T10:34:56.789Z", 120).unwrap(), b);
        assert_eq!(encode_dt("2026-10-30 14:34:56.7891+02:00", 0).unwrap(), b);
        // 1999 and a day change
        let y = encode_dt("1999-12-31T23:30:00-01:00", 0).unwrap();
        assert_eq!(&y[..6], &[0x00, 0x01, 0x01, 0x00, 0x30, 0x00]);
        assert_eq!(y[7] & 0x0F, 7, "2000-01-01 was a Saturday");
        assert_eq!(
            decode_dt(&[0x99, 0x01, 0x01, 0, 0, 0, 0, 0x06], 0).unwrap(),
            "1999-01-01T00:00:00.000Z"
        );
        for bad in [
            "2026-02-30T00:00:00Z",
            "2026-10-30T12:34:56",
            "2026-10-30",
            "x",
            "2026-10-30T25:00:00Z",
            // zones: non-ASCII, out of range, signs inside, short, long
            "2026-10-30T12:00:00+0é:0",
            "2026-10-30T12:00:00+é0:00",
            "2026-10-30T12:00:00+24:00",
            "2026-10-30T12:00:00+01:60",
            "2026-10-30T12:00:00+-1:00",
            "2026-10-30T12:00:00+01:0",
            "2026-10-30T12:00:00+01:000",
            // non-ASCII elsewhere
            "2026-10-30T12:00:00.é",
            "2026-10-30T12:00:00é",
            "é026-10-30T12:00:00Z",
            "2026-10-30T12:00:00.12é",
            "2026-1é-30T12:00:00Z",
        ] {
            assert!(encode_dt(bad, 0).is_err(), "{bad}");
        }
        assert!(encode_dt("2090-01-01T00:00:00Z", 0).is_err());
        assert!(decode_dt(&[0x26, 0x02, 0x30, 0, 0, 0, 0, 0], 0).is_err());
        assert_eq!(
            decode_dt(&[0x26, 0x1A, 0x30, 0, 0, 0, 0, 0], 0),
            Err(ConvError::BadBcd)
        );
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(civil_from_days(days_from_civil(2024, 2, 29)), (2024, 2, 29));
    }
}
