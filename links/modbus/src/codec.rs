//! Modbus data types, value codec, FC22 masks and the read batch planner.
//! Pure logic (wiki "Фреймворк драйверів", section "Типи даних Modbus").
//!
//! Register words are big-endian on the wire; multi-word values put the most
//! significant word first. `_wswap` reverses the word order, `_bswap` swaps
//! the two bytes inside each word, `_wbswap` does both (DCBA: the bytes in
//! reverse order). `_m10k` types are two words read as `hi × 10 000 + lo`
//! (`lo` 0…9999). `bits16` is one register as 16 bools, bit 0 first.
//! Unscaled integers publish exactly as `UInt`/`Int` (64-bit values never
//! pass through `f64`); scaled values publish as `Float`.

use wyrm_core::{TypeCode, Value};

/// Most registers one read may return (FC3/FC4).
pub const MAX_REGISTERS: u16 = 125;
/// Most bits one read may return (FC1/FC2).
pub const MAX_BITS: u16 = 2000;
/// Most registers one write may carry (FC16). A coil point is one bit, so
/// the FC15 bound (1968 bits) is never reached.
pub const MAX_WRITE_REGISTERS: u16 = 123;

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum CodecError {
    #[error("not enough registers for the data type")]
    ShortInput,
    #[error("value out of range for the data type")]
    OutOfRange,
    #[error("invalid BCD digit")]
    BadBcd,
    #[error("text is not ASCII")]
    NotUtf8OrAscii,
    #[error("a bit in a register needs a mask write (FC22) or read-modify-write")]
    NeedsMaskWrite,
    #[error("value type does not match the data type")]
    TypeMismatch,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DType {
    Binary,
    #[default]
    U16,
    U16BSwap,
    I16,
    I16BSwap,
    U32,
    U32WSwap,
    U32BSwap,
    U32WBSwap,
    I32,
    I32WSwap,
    I32BSwap,
    I32WBSwap,
    U32M10k,
    U32M10kWSwap,
    I32M10k,
    I32M10kWSwap,
    F32,
    F32WSwap,
    F32WBSwap,
    U64,
    U64WSwap,
    I64,
    I64WSwap,
    F64,
    F64WSwap,
    Bcd16,
    Bcd32,
    Bcd32WSwap,
    Bits16,
    Char,
    VarChar,
}

const NAMES: &[(DType, &str)] = &[
    (DType::Binary, "binary"),
    (DType::U16, "u16"),
    (DType::U16BSwap, "u16_bswap"),
    (DType::I16, "i16"),
    (DType::I16BSwap, "i16_bswap"),
    (DType::U32, "u32"),
    (DType::U32WSwap, "u32_wswap"),
    (DType::U32BSwap, "u32_bswap"),
    (DType::U32WBSwap, "u32_wbswap"),
    (DType::I32, "i32"),
    (DType::I32WSwap, "i32_wswap"),
    (DType::I32BSwap, "i32_bswap"),
    (DType::I32WBSwap, "i32_wbswap"),
    (DType::U32M10k, "u32_m10k"),
    (DType::U32M10kWSwap, "u32_m10k_wswap"),
    (DType::I32M10k, "i32_m10k"),
    (DType::I32M10kWSwap, "i32_m10k_wswap"),
    (DType::F32, "f32"),
    (DType::F32WSwap, "f32_wswap"),
    (DType::F32WBSwap, "f32_wbswap"),
    (DType::U64, "u64"),
    (DType::U64WSwap, "u64_wswap"),
    (DType::I64, "i64"),
    (DType::I64WSwap, "i64_wswap"),
    (DType::F64, "f64"),
    (DType::F64WSwap, "f64_wswap"),
    (DType::Bcd16, "bcd16"),
    (DType::Bcd32, "bcd32"),
    (DType::Bcd32WSwap, "bcd32_wswap"),
    (DType::Bits16, "bits16"),
    (DType::Char, "char"),
    (DType::VarChar, "varchar"),
];

/// Word layout of an integer-like type.
#[derive(Clone, Copy)]
enum Layout {
    Normal,
    WordSwap,
    ByteSwap,
    /// Words reversed and bytes swapped: all bytes in reverse order.
    WordByteSwap,
}

impl DType {
    pub const ALL: &'static [DType] = &[
        DType::Binary,
        DType::U16,
        DType::U16BSwap,
        DType::I16,
        DType::I16BSwap,
        DType::U32,
        DType::U32WSwap,
        DType::U32BSwap,
        DType::U32WBSwap,
        DType::I32,
        DType::I32WSwap,
        DType::I32BSwap,
        DType::I32WBSwap,
        DType::U32M10k,
        DType::U32M10kWSwap,
        DType::I32M10k,
        DType::I32M10kWSwap,
        DType::F32,
        DType::F32WSwap,
        DType::F32WBSwap,
        DType::U64,
        DType::U64WSwap,
        DType::I64,
        DType::I64WSwap,
        DType::F64,
        DType::F64WSwap,
        DType::Bcd16,
        DType::Bcd32,
        DType::Bcd32WSwap,
        DType::Bits16,
        DType::Char,
        DType::VarChar,
    ];

    /// Spec name, lowercase (`"u32_wswap"`).
    pub fn parse(s: &str) -> Option<Self> {
        NAMES.iter().find(|(_, n)| *n == s).map(|(d, _)| *d)
    }

    pub fn name(self) -> &'static str {
        NAMES
            .iter()
            .find(|(d, _)| *d == self)
            .map(|(_, n)| *n)
            .unwrap_or("?")
    }

    /// Registers per value; text types use `regs`.
    pub fn words(self, regs: u8) -> u16 {
        use DType::*;
        match self {
            Binary | U16 | U16BSwap | I16 | I16BSwap | Bcd16 | Bits16 => 1,
            U32 | U32WSwap | U32BSwap | U32WBSwap | I32 | I32WSwap | I32BSwap | I32WBSwap
            | U32M10k | U32M10kWSwap | I32M10k | I32M10kWSwap | F32 | F32WSwap | F32WBSwap
            | Bcd32 | Bcd32WSwap => 2,
            U64 | U64WSwap | I64 | I64WSwap | F64 | F64WSwap => 4,
            Char | VarChar => u16::from(regs.max(1)),
        }
    }

    pub fn type_code(self) -> TypeCode {
        match self {
            DType::Binary => TypeCode::Bool,
            DType::Char | DType::VarChar => TypeCode::String,
            DType::Bits16 => TypeCode::Array,
            _ => TypeCode::Number,
        }
    }

    fn layout(self) -> Layout {
        use DType::*;
        match self {
            U32WSwap | I32WSwap | F32WSwap | U64WSwap | I64WSwap | F64WSwap | U32M10kWSwap
            | I32M10kWSwap | Bcd32WSwap => Layout::WordSwap,
            U16BSwap | I16BSwap | U32BSwap | I32BSwap => Layout::ByteSwap,
            U32WBSwap | I32WBSwap | F32WBSwap => Layout::WordByteSwap,
            _ => Layout::Normal,
        }
    }
}

fn unscaled(scale: f64, offset: f64) -> bool {
    scale == 1.0 && offset == 0.0
}

/// Raw bits of the first `n` words, most significant word first after layout.
fn gather(words: &[u16], n: usize, layout: Layout) -> Result<u64, CodecError> {
    let w = words.get(..n).ok_or(CodecError::ShortInput)?;
    let mut acc = 0u64;
    let mut push = |x: u16| acc = (acc << 16) | u64::from(x);
    match layout {
        Layout::Normal => w.iter().for_each(|x| push(*x)),
        Layout::WordSwap => w.iter().rev().for_each(|x| push(*x)),
        Layout::ByteSwap => w.iter().for_each(|x| push(x.swap_bytes())),
        Layout::WordByteSwap => w.iter().rev().for_each(|x| push(x.swap_bytes())),
    }
    Ok(acc)
}

/// Inverse of [`gather`].
fn scatter(raw: u64, n: usize, layout: Layout) -> Vec<u16> {
    let mut out: Vec<u16> = (0..n).rev().map(|i| (raw >> (16 * i)) as u16).collect();
    match layout {
        Layout::Normal => {}
        Layout::WordSwap => out.reverse(),
        Layout::ByteSwap => out.iter_mut().for_each(|x| *x = x.swap_bytes()),
        Layout::WordByteSwap => {
            out.reverse();
            out.iter_mut().for_each(|x| *x = x.swap_bytes());
        }
    }
    out
}

/// `[hi, lo]` (after layout) → `hi × 10 000 + lo`; `lo` must be 0…9999.
/// Signed types read both words as `i16`, as DSA does.
fn m10k_decode(raw: u64, signed: bool) -> Result<i128, CodecError> {
    let (hi, lo) = ((raw >> 16) as u16, raw as u16);
    let (hi, lo) = if signed {
        (i128::from(hi as i16), i128::from(lo as i16))
    } else {
        (i128::from(hi), i128::from(lo))
    };
    if lo.abs() > 9999 {
        return Err(CodecError::OutOfRange);
    }
    Ok(hi * 10_000 + lo)
}

/// Inverse of [`m10k_decode`]: truncating `/` and `%`, so a negative value
/// has two negative words.
fn m10k_encode(x: i128, signed: bool) -> Result<u64, CodecError> {
    let x = if signed {
        in_range(x, -327_689_999, 327_679_999)?
    } else {
        in_range(x, 0, 655_359_999)?
    };
    let (hi, lo) = ((x / 10_000) as i16 as u16, (x % 10_000) as i16 as u16);
    Ok((u64::from(hi) << 16) | u64::from(lo))
}

fn bcd_decode(raw: u64, digits: u32) -> Result<u64, CodecError> {
    let mut v = 0u64;
    for i in (0..digits).rev() {
        let d = (raw >> (4 * i)) & 0xF;
        if d > 9 {
            return Err(CodecError::BadBcd);
        }
        v = v * 10 + d;
    }
    Ok(v)
}

fn bcd_encode(mut v: u64, digits: u32) -> u64 {
    let mut raw = 0u64;
    for i in 0..digits {
        raw |= (v % 10) << (4 * i);
        v /= 10;
    }
    raw
}

fn text(words: &[u16], n: usize) -> Result<Vec<u8>, CodecError> {
    let w = words.get(..n).ok_or(CodecError::ShortInput)?;
    let bytes: Vec<u8> = w.iter().flat_map(|x| x.to_be_bytes()).collect();
    if !bytes.is_ascii() {
        return Err(CodecError::NotUtf8OrAscii);
    }
    Ok(bytes)
}

fn int_value(x: i128, scale: f64, offset: f64) -> Value {
    if unscaled(scale, offset) {
        if x >= 0 {
            Value::UInt(x as u64)
        } else {
            Value::Int(x as i64)
        }
    } else {
        Value::Float(x as f64 * scale + offset)
    }
}

/// Registers (or a coil word for BINARY) → published value.
pub fn decode(
    dtype: DType,
    words: &[u16],
    bit: u8,
    scale: f64,
    offset: f64,
) -> Result<Value, CodecError> {
    use DType::*;
    let n = usize::from(dtype.words(1));
    let layout = dtype.layout();
    Ok(match dtype {
        Binary => {
            if bit > 15 {
                return Err(CodecError::OutOfRange);
            }
            let w = *words.first().ok_or(CodecError::ShortInput)?;
            Value::Bool((w >> bit) & 1 == 1)
        }
        U16 | U16BSwap | U32 | U32WSwap | U32BSwap | U32WBSwap | U64 | U64WSwap => {
            int_value(i128::from(gather(words, n, layout)?), scale, offset)
        }
        I16 | I16BSwap => int_value(
            i128::from(gather(words, n, layout)? as u16 as i16),
            scale,
            offset,
        ),
        I32 | I32WSwap | I32BSwap | I32WBSwap => int_value(
            i128::from(gather(words, n, layout)? as u32 as i32),
            scale,
            offset,
        ),
        U32M10k | U32M10kWSwap => int_value(
            m10k_decode(gather(words, n, layout)?, false)?,
            scale,
            offset,
        ),
        I32M10k | I32M10kWSwap => {
            int_value(m10k_decode(gather(words, n, layout)?, true)?, scale, offset)
        }
        I64 | I64WSwap => int_value(i128::from(gather(words, n, layout)? as i64), scale, offset),
        F32 | F32WSwap | F32WBSwap => {
            let f = f64::from(f32::from_bits(gather(words, n, layout)? as u32));
            Value::Float(f * scale + offset)
        }
        F64 | F64WSwap => {
            let f = f64::from_bits(gather(words, n, layout)?);
            Value::Float(f * scale + offset)
        }
        Bcd16 => int_value(
            i128::from(bcd_decode(gather(words, 1, layout)?, 4)?),
            scale,
            offset,
        ),
        Bcd32 | Bcd32WSwap => int_value(
            i128::from(bcd_decode(gather(words, 2, layout)?, 8)?),
            scale,
            offset,
        ),
        Bits16 => {
            let w = *words.first().ok_or(CodecError::ShortInput)?;
            Value::Array((0..16).map(|i| Value::Bool((w >> i) & 1 == 1)).collect())
        }
        Char => {
            let b = text(words, words.len())?;
            let end = b
                .iter()
                .rposition(|c| *c != b' ' && *c != 0)
                .map_or(0, |i| i + 1);
            Value::Str(String::from_utf8_lossy(&b[..end]).into_owned())
        }
        VarChar => {
            let b = text(words, words.len())?;
            let end = b.iter().position(|c| *c == 0).unwrap_or(b.len());
            Value::Str(String::from_utf8_lossy(&b[..end]).into_owned())
        }
    })
}

/// Raw integer for `value` after inverse scaling, rounded.
fn raw_int(value: &Value, scale: f64, offset: f64) -> Result<i128, CodecError> {
    if unscaled(scale, offset) {
        match value {
            Value::UInt(u) => return Ok(i128::from(*u)),
            Value::Int(i) => return Ok(i128::from(*i)),
            _ => {}
        }
    }
    let f = value.as_f64().ok_or(CodecError::TypeMismatch)?;
    let raw = (f - offset) / scale;
    if !raw.is_finite() || raw.abs() > 1e38 {
        return Err(CodecError::OutOfRange);
    }
    Ok(raw.round() as i128)
}

fn raw_float(value: &Value, scale: f64, offset: f64) -> Result<f64, CodecError> {
    let f = value.as_f64().ok_or(CodecError::TypeMismatch)?;
    let raw = (f - offset) / scale;
    if raw.is_finite() {
        Ok(raw)
    } else {
        Err(CodecError::OutOfRange)
    }
}

fn in_range(x: i128, lo: i128, hi: i128) -> Result<i128, CodecError> {
    if (lo..=hi).contains(&x) {
        Ok(x)
    } else {
        Err(CodecError::OutOfRange)
    }
}

fn ascii_text(value: &Value, max: usize) -> Result<Vec<u8>, CodecError> {
    let Value::Str(s) = value else {
        return Err(CodecError::TypeMismatch);
    };
    if !s.is_ascii() {
        return Err(CodecError::NotUtf8OrAscii);
    }
    if s.len() > max {
        return Err(CodecError::OutOfRange);
    }
    Ok(s.as_bytes().to_vec())
}

fn pack(bytes: &[u8]) -> Vec<u16> {
    bytes
        .chunks(2)
        .map(|c| u16::from_be_bytes([c[0], c[1]]))
        .collect()
}

/// Published value → registers to write. `regs` sizes CHAR/VARCHAR.
pub fn encode(
    dtype: DType,
    value: &Value,
    regs: u8,
    scale: f64,
    offset: f64,
) -> Result<Vec<u16>, CodecError> {
    use DType::*;
    let n = usize::from(dtype.words(regs));
    let layout = dtype.layout();
    Ok(match dtype {
        Binary => return Err(CodecError::NeedsMaskWrite),
        U16 | U16BSwap => {
            let x = in_range(raw_int(value, scale, offset)?, 0, u16::MAX.into())?;
            scatter(x as u64, n, layout)
        }
        I16 | I16BSwap => {
            let x = in_range(
                raw_int(value, scale, offset)?,
                i16::MIN.into(),
                i16::MAX.into(),
            )?;
            scatter(u64::from(x as i16 as u16), n, layout)
        }
        U32 | U32WSwap | U32BSwap | U32WBSwap => {
            let x = in_range(raw_int(value, scale, offset)?, 0, u32::MAX.into())?;
            scatter(x as u64, n, layout)
        }
        U32M10k | U32M10kWSwap => scatter(
            m10k_encode(raw_int(value, scale, offset)?, false)?,
            n,
            layout,
        ),
        I32M10k | I32M10kWSwap => scatter(
            m10k_encode(raw_int(value, scale, offset)?, true)?,
            n,
            layout,
        ),
        I32 | I32WSwap | I32BSwap | I32WBSwap => {
            let x = in_range(
                raw_int(value, scale, offset)?,
                i32::MIN.into(),
                i32::MAX.into(),
            )?;
            scatter(u64::from(x as i32 as u32), n, layout)
        }
        U64 | U64WSwap => {
            let x = in_range(raw_int(value, scale, offset)?, 0, u64::MAX.into())?;
            scatter(x as u64, n, layout)
        }
        I64 | I64WSwap => {
            let x = in_range(
                raw_int(value, scale, offset)?,
                i64::MIN.into(),
                i64::MAX.into(),
            )?;
            scatter(x as i64 as u64, n, layout)
        }
        F32 | F32WSwap | F32WBSwap => {
            let f = raw_float(value, scale, offset)? as f32;
            if !f.is_finite() {
                return Err(CodecError::OutOfRange);
            }
            scatter(u64::from(f.to_bits()), n, layout)
        }
        F64 | F64WSwap => scatter(raw_float(value, scale, offset)?.to_bits(), n, layout),
        Bcd16 => {
            let x = in_range(raw_int(value, scale, offset)?, 0, 9999)?;
            scatter(bcd_encode(x as u64, 4), 1, layout)
        }
        Bcd32 | Bcd32WSwap => {
            let x = in_range(raw_int(value, scale, offset)?, 0, 99_999_999)?;
            scatter(bcd_encode(x as u64, 8), 2, layout)
        }
        Bits16 => {
            let Value::Array(bits) = value else {
                return Err(CodecError::TypeMismatch);
            };
            if bits.len() != 16 {
                return Err(CodecError::OutOfRange);
            }
            let mut w = 0u16;
            for (i, b) in bits.iter().enumerate() {
                match b {
                    Value::Bool(true) => w |= 1 << i,
                    Value::Bool(false) => {}
                    _ => return Err(CodecError::TypeMismatch),
                }
            }
            vec![w]
        }
        Char | VarChar => {
            let mut b = ascii_text(value, n * 2)?;
            let pad = if dtype == Char { b' ' } else { 0 };
            b.resize(n * 2, pad);
            pack(&b)
        }
    })
}

/// FC22 masks that set (`on`) or clear one `bit` (0..=15).
pub fn bit_masks(bit: u8, on: bool) -> (u16, u16) {
    let m = 1u16 << (bit & 15);
    (!m, if on { m } else { 0 })
}

/// The device's FC22 result: `(current & and) | (or & !and)`.
pub fn apply_masks(current: u16, and: u16, or: u16) -> u16 {
    (current & and) | (or & !and)
}

/// One read request covering several points.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Span {
    pub start: u16,
    pub count: u16,
    /// Indexes into the `reqs` given to [`plan`].
    pub members: Vec<usize>,
}

/// Merge `(addr, words)` requests into reads of at most `max_count` words.
/// With `contiguous_only`, requests merge only when adjacent or overlapping;
/// otherwise gaps are read too. A request longer than `max_count` gets a
/// span of its own.
pub fn plan(reqs: &[(u16, u16)], max_count: u16, contiguous_only: bool) -> Vec<Span> {
    let mut order: Vec<usize> = (0..reqs.len()).collect();
    order.sort_by_key(|&i| (reqs[i].0, reqs[i].1));
    let mut out: Vec<Span> = Vec::new();
    let mut end = 0u32; // exclusive end of the open span
    for i in order {
        let (a, n) = (u32::from(reqs[i].0), u32::from(reqs[i].1.max(1)));
        if let Some(cur) = out.last_mut() {
            let start = u32::from(cur.start);
            let new_end = end.max(a + n);
            let joins = !contiguous_only || a <= end;
            if joins && new_end - start <= u32::from(max_count) {
                cur.count = (new_end - start) as u16;
                cur.members.push(i);
                end = new_end;
                continue;
            }
        }
        out.push(Span {
            start: a as u16,
            count: n.min(u32::from(u16::MAX)) as u16,
            members: vec![i],
        });
        end = a + n;
    }
    out
}

/// The `n` words at `addr` inside the result of reading `span`.
pub fn slice<'a>(span: &Span, words: &'a [u16], addr: u16, n: u16) -> &'a [u16] {
    let from = usize::from(addr.saturating_sub(span.start));
    let to = (from + usize::from(n)).min(words.len());
    &words[from.min(to)..to]
}

#[cfg(test)]
mod tests {
    use super::DType::*;
    use super::*;

    fn rt(d: DType, v: Value) {
        let w = encode(d, &v, 4, 1.0, 0.0).unwrap();
        assert_eq!(w.len(), usize::from(d.words(4)), "{d:?}");
        assert_eq!(decode(d, &w, 0, 1.0, 0.0).unwrap(), v, "{d:?}");
    }

    #[test]
    fn names_roundtrip() {
        for d in DType::ALL {
            assert_eq!(DType::parse(d.name()), Some(*d));
        }
        assert_eq!(DType::parse("U32"), None, "lowercase only");
        assert_eq!(Binary.type_code(), TypeCode::Bool);
        assert_eq!(Char.type_code(), TypeCode::String);
        assert_eq!(F64.type_code(), TypeCode::Number);
        assert_eq!(Char.words(5), 5);
        assert_eq!(U64.words(5), 4);
    }

    #[test]
    fn integer_roundtrips_exact() {
        for d in [U16, U16BSwap] {
            rt(d, Value::UInt(0));
            rt(d, Value::UInt(65535));
            rt(d, Value::UInt(0x1234));
        }
        for d in [I16, I16BSwap] {
            rt(d, Value::Int(-32768));
            rt(d, Value::UInt(32767));
            rt(d, Value::Int(-2));
        }
        for d in [U32, U32WSwap, U32BSwap] {
            rt(d, Value::UInt(u32::MAX.into()));
            rt(d, Value::UInt(70000));
        }
        for d in [I32, I32WSwap, I32BSwap] {
            rt(d, Value::Int(i32::MIN.into()));
            rt(d, Value::Int(-70000));
        }
        for d in [U64, U64WSwap] {
            rt(d, Value::UInt(u64::MAX));
            rt(d, Value::UInt(9_007_199_254_740_993)); // 2^53 + 1, not exact in f64
        }
        for d in [I64, I64WSwap] {
            rt(d, Value::Int(i64::MIN));
            rt(d, Value::UInt(i64::MAX as u64));
        }
        for d in [Bcd16, Bcd32] {
            rt(d, Value::UInt(0));
            rt(d, Value::UInt(1234));
        }
        rt(Bcd16, Value::UInt(9999));
        rt(Bcd32, Value::UInt(99_999_999));
    }

    #[test]
    fn float_roundtrips() {
        for d in [F32, F32WSwap] {
            rt(d, Value::Float(21.5));
            rt(d, Value::Float(-0.125));
        }
        for d in [F64, F64WSwap] {
            rt(d, Value::Float(std::f64::consts::PI));
            rt(d, Value::Float(-1e300));
        }
    }

    #[test]
    fn layouts_match_hand_computed_words() {
        let v = Value::UInt(0x1234_5678);
        assert_eq!(encode(U32, &v, 0, 1.0, 0.0).unwrap(), [0x1234, 0x5678]);
        assert_eq!(encode(U32WSwap, &v, 0, 1.0, 0.0).unwrap(), [0x5678, 0x1234]);
        assert_eq!(encode(U32BSwap, &v, 0, 1.0, 0.0).unwrap(), [0x3412, 0x7856]);
        assert_eq!(
            encode(U16BSwap, &Value::UInt(0x1234), 0, 1.0, 0.0).unwrap(),
            [0x3412]
        );
        let v = Value::UInt(0x0102_0304_0506_0708);
        assert_eq!(
            encode(U64, &v, 0, 1.0, 0.0).unwrap(),
            [0x0102, 0x0304, 0x0506, 0x0708]
        );
        assert_eq!(
            encode(U64WSwap, &v, 0, 1.0, 0.0).unwrap(),
            [0x0708, 0x0506, 0x0304, 0x0102]
        );
        // 1.0f32 = 0x3F800000
        assert_eq!(
            encode(F32, &Value::Float(1.0), 0, 1.0, 0.0).unwrap(),
            [0x3F80, 0x0000]
        );
        assert_eq!(
            encode(F32WSwap, &Value::Float(1.0), 0, 1.0, 0.0).unwrap(),
            [0x0000, 0x3F80]
        );
        assert_eq!(decode(I16, &[0xFFFE], 0, 1.0, 0.0).unwrap(), Value::Int(-2));
        assert_eq!(
            encode(Bcd16, &Value::UInt(1234), 0, 1.0, 0.0).unwrap(),
            [0x1234]
        );
        assert_eq!(
            encode(Bcd32, &Value::UInt(12_345_678), 0, 1.0, 0.0).unwrap(),
            [0x1234, 0x5678]
        );
    }

    #[test]
    fn bcd_rejects_bad_input() {
        assert_eq!(
            decode(Bcd16, &[0x12A4], 0, 1.0, 0.0),
            Err(CodecError::BadBcd)
        );
        assert_eq!(
            decode(Bcd32, &[0x1234, 0x56F8], 0, 1.0, 0.0),
            Err(CodecError::BadBcd)
        );
        assert_eq!(
            encode(Bcd16, &Value::Int(-1), 0, 1.0, 0.0),
            Err(CodecError::OutOfRange)
        );
        assert_eq!(
            encode(Bcd16, &Value::UInt(10_000), 0, 1.0, 0.0),
            Err(CodecError::OutOfRange)
        );
        assert_eq!(
            encode(Bcd32, &Value::UInt(100_000_000), 0, 1.0, 0.0),
            Err(CodecError::OutOfRange)
        );
    }

    #[test]
    fn text_types() {
        let w = encode(Char, &Value::from("AB1"), 3, 1.0, 0.0).unwrap();
        assert_eq!(w, [0x4142, 0x3120, 0x2020], "space padded");
        assert_eq!(decode(Char, &w, 0, 1.0, 0.0).unwrap(), Value::from("AB1"));
        let w = encode(VarChar, &Value::from("AB1"), 3, 1.0, 0.0).unwrap();
        assert_eq!(w, [0x4142, 0x3100, 0x0000], "NUL padded");
        assert_eq!(
            decode(VarChar, &w, 0, 1.0, 0.0).unwrap(),
            Value::from("AB1")
        );
        // VARCHAR stops at the first NUL even with trailing data
        assert_eq!(
            decode(VarChar, &[0x4100, 0x4242], 0, 1.0, 0.0).unwrap(),
            Value::from("A")
        );
        // CHAR trims trailing NULs and spaces
        assert_eq!(
            decode(Char, &[0x4120, 0x0000], 0, 1.0, 0.0).unwrap(),
            Value::from("A")
        );
        // full width, no terminator
        let w = encode(VarChar, &Value::from("ABCD"), 2, 1.0, 0.0).unwrap();
        assert_eq!(
            decode(VarChar, &w, 0, 1.0, 0.0).unwrap(),
            Value::from("ABCD")
        );
        assert_eq!(
            encode(Char, &Value::from("ABCDE"), 2, 1.0, 0.0),
            Err(CodecError::OutOfRange)
        );
        assert_eq!(
            encode(Char, &Value::from("é"), 2, 1.0, 0.0),
            Err(CodecError::NotUtf8OrAscii)
        );
        assert_eq!(
            decode(Char, &[0xC3A9], 0, 1.0, 0.0),
            Err(CodecError::NotUtf8OrAscii)
        );
        assert_eq!(
            encode(Char, &Value::UInt(1), 2, 1.0, 0.0),
            Err(CodecError::TypeMismatch)
        );
    }

    #[test]
    fn binary_bits() {
        assert_eq!(
            decode(Binary, &[0b100], 2, 1.0, 0.0).unwrap(),
            Value::Bool(true)
        );
        assert_eq!(
            decode(Binary, &[0b100], 1, 1.0, 0.0).unwrap(),
            Value::Bool(false)
        );
        assert_eq!(
            decode(Binary, &[0x8000], 15, 1.0, 0.0).unwrap(),
            Value::Bool(true)
        );
        assert_eq!(
            decode(Binary, &[1], 16, 1.0, 0.0),
            Err(CodecError::OutOfRange)
        );
        assert_eq!(
            encode(Binary, &Value::Bool(true), 0, 1.0, 0.0),
            Err(CodecError::NeedsMaskWrite)
        );
    }

    #[test]
    fn scale_and_offset() {
        assert_eq!(
            decode(I16, &[215], 0, 0.1, 0.0).unwrap(),
            Value::Float(21.5)
        );
        assert_eq!(
            decode(U16, &[100], 0, 0.5, -10.0).unwrap(),
            Value::Float(40.0)
        );
        assert_eq!(
            encode(I16, &Value::Float(21.5), 0, 0.1, 0.0).unwrap(),
            [215]
        );
        assert_eq!(
            encode(U16, &Value::Float(40.0), 0, 0.5, -10.0).unwrap(),
            [100]
        );
        assert_eq!(
            decode(F32, &[0x3F80, 0], 0, 2.0, 1.0).unwrap(),
            Value::Float(3.0)
        );
        // an unscaled float rounds to the integer register
        assert_eq!(encode(U16, &Value::Float(2.6), 0, 1.0, 0.0).unwrap(), [3]);
    }

    #[test]
    fn range_and_type_errors() {
        use CodecError::*;
        let e = |d, v: Value| encode(d, &v, 0, 1.0, 0.0).unwrap_err();
        assert_eq!(e(U16, Value::Int(-1)), OutOfRange);
        assert_eq!(e(U16, Value::UInt(65536)), OutOfRange);
        assert_eq!(e(I16, Value::UInt(32768)), OutOfRange);
        assert_eq!(e(U32, Value::UInt(u64::from(u32::MAX) + 1)), OutOfRange);
        assert_eq!(e(I64, Value::UInt(u64::MAX)), OutOfRange);
        assert_eq!(e(U64, Value::Int(-1)), OutOfRange);
        assert_eq!(e(U16, Value::Float(f64::NAN)), OutOfRange);
        assert_eq!(e(F64, Value::Float(f64::INFINITY)), OutOfRange);
        assert_eq!(e(F32, Value::Float(1e300)), OutOfRange);
        assert_eq!(e(U16, Value::Bool(true)), TypeMismatch);
        assert_eq!(e(F32, Value::from("x")), TypeMismatch);
        assert_eq!(decode(U32, &[1], 0, 1.0, 0.0), Err(ShortInput));
        assert_eq!(decode(F64, &[1, 2, 3], 0, 1.0, 0.0), Err(ShortInput));
        assert_eq!(decode(Binary, &[], 0, 1.0, 0.0), Err(ShortInput));
    }

    /// Ruling 3: the DSA types missing before (INT32M10K, UINT32M10K and
    /// their SWAP forms, INT32SWAPSWAP/UINT32SWAPSWAP, FLOAT32 DCBA,
    /// BCD32SWAP) and a register as 16 bools.
    #[test]
    fn dsa_types_match_hand_computed_words() {
        let enc = |d, v: Value| encode(d, &v, 0, 1.0, 0.0);
        let dec = |d, w: &[u16]| decode(d, w, 0, 1.0, 0.0);
        // modulo 10 000: hi × 10 000 + lo
        let v = Value::UInt(12_345_678);
        assert_eq!(dec(U32M10k, &[1234, 5678]), Ok(v.clone()));
        assert_eq!(enc(U32M10k, v.clone()), Ok(vec![1234, 5678]));
        assert_eq!(dec(U32M10kWSwap, &[5678, 1234]), Ok(v.clone()));
        assert_eq!(enc(U32M10kWSwap, v.clone()), Ok(vec![5678, 1234]));
        assert_eq!(dec(I32M10k, &[1234, 5678]), Ok(v.clone()));
        assert_eq!(dec(I32M10kWSwap, &[5678, 1234]), Ok(v));
        // negative: both words negative (DSA truncating / and %)
        let neg = Value::Int(-12_345_678);
        let w = [(-1234i16) as u16, (-5678i16) as u16];
        assert_eq!(enc(I32M10k, neg.clone()), Ok(w.to_vec()));
        assert_eq!(dec(I32M10k, &w), Ok(neg.clone()));
        assert_eq!(enc(I32M10kWSwap, neg.clone()), Ok(vec![w[1], w[0]]));
        assert_eq!(dec(I32M10kWSwap, &[w[1], w[0]]), Ok(neg));
        // the high word uses its whole range
        assert_eq!(dec(U32M10k, &[65535, 9999]), Ok(Value::UInt(655_359_999)));
        assert_eq!(
            dec(I32M10k, &[(-32768i16) as u16, 0]),
            Ok(Value::Int(-327_680_000))
        );
        rt(U32M10k, Value::UInt(655_359_999));
        rt(I32M10k, Value::Int(-327_689_999));
        rt(I32M10k, Value::UInt(327_679_999));
        rt(I32M10k, Value::Int(-5));
        // words and bytes swapped (DCBA)
        let v = Value::UInt(0x1122_3344);
        assert_eq!(enc(U32WBSwap, v.clone()), Ok(vec![0x4433, 0x2211]));
        assert_eq!(dec(U32WBSwap, &[0x4433, 0x2211]), Ok(v));
        assert_eq!(
            dec(I32WBSwap, &[0xFFFF, 0xFFFE]),
            Ok(Value::Int(-16_777_217)),
            "0xFEFFFFFF"
        );
        rt(I32WBSwap, Value::Int(i32::MIN.into()));
        // 1.0f32 = 0x3F800000 → bytes 00 00 80 3F
        assert_eq!(enc(F32WBSwap, Value::Float(1.0)), Ok(vec![0x0000, 0x803F]));
        assert_eq!(dec(F32WBSwap, &[0x0000, 0x803F]), Ok(Value::Float(1.0)));
        rt(F32WBSwap, Value::Float(-1234.5625));
        // BCD with the words swapped
        let v = Value::UInt(12_345_678);
        assert_eq!(enc(Bcd32WSwap, v.clone()), Ok(vec![0x5678, 0x1234]));
        assert_eq!(dec(Bcd32WSwap, &[0x5678, 0x1234]), Ok(v));
        assert_eq!(dec(Bcd32WSwap, &[0x56F8, 0x1234]), Err(CodecError::BadBcd));
        // 16 bools, bit 0 first
        let bits: Vec<Value> = (0..16)
            .map(|i| Value::Bool(matches!(i, 0 | 2 | 15)))
            .collect();
        assert_eq!(dec(Bits16, &[0x8005]), Ok(Value::Array(bits.clone())));
        assert_eq!(enc(Bits16, Value::Array(bits)), Ok(vec![0x8005]));
        rt(Bits16, Value::Array(vec![Value::Bool(true); 16]));
        assert_eq!(Bits16.type_code(), TypeCode::Array);
        assert_eq!(Bits16.words(4), 1);
        for d in [U32M10k, I32M10kWSwap, U32WBSwap, F32WBSwap, Bcd32WSwap] {
            assert_eq!(d.words(4), 2, "{d:?}");
        }
    }

    #[test]
    fn dsa_types_refuse_bad_input() {
        use CodecError::*;
        let enc = |d, v: Value| encode(d, &v, 0, 1.0, 0.0);
        // the modulo word holds 0..=9999
        assert_eq!(decode(U32M10k, &[1, 10_000], 0, 1.0, 0.0), Err(OutOfRange));
        assert_eq!(
            decode(U32M10kWSwap, &[10_000, 1], 0, 1.0, 0.0),
            Err(OutOfRange)
        );
        assert_eq!(
            decode(I32M10k, &[1, (-10_000i16) as u16], 0, 1.0, 0.0),
            Err(OutOfRange)
        );
        assert_eq!(decode(U32M10k, &[1], 0, 1.0, 0.0), Err(ShortInput));
        assert_eq!(enc(U32M10k, Value::UInt(655_360_000)), Err(OutOfRange));
        assert_eq!(enc(U32M10k, Value::Int(-1)), Err(OutOfRange));
        assert_eq!(enc(I32M10k, Value::UInt(327_680_000)), Err(OutOfRange));
        assert_eq!(enc(I32M10k, Value::Int(-327_690_000)), Err(OutOfRange));
        assert_eq!(
            enc(U32WBSwap, Value::UInt(u64::from(u32::MAX) + 1)),
            Err(OutOfRange)
        );
        assert_eq!(enc(Bcd32WSwap, Value::UInt(100_000_000)), Err(OutOfRange));
        // exactly 16 bools
        assert_eq!(
            enc(Bits16, Value::Array(vec![Value::Bool(true); 15])),
            Err(OutOfRange)
        );
        let mut v = vec![Value::Bool(false); 16];
        v[3] = Value::UInt(1);
        assert_eq!(enc(Bits16, Value::Array(v)), Err(TypeMismatch));
        assert_eq!(enc(Bits16, Value::UInt(5)), Err(TypeMismatch));
        assert_eq!(decode(Bits16, &[], 0, 1.0, 0.0), Err(ShortInput));
    }

    /// Ruling 5: one FC16 write carries at most 123 registers.
    #[test]
    fn write_bounds() {
        assert_eq!(MAX_WRITE_REGISTERS, 123);
    }

    #[test]
    fn mask_write() {
        let (and, or) = bit_masks(3, true);
        assert_eq!(apply_masks(0b0000, and, or), 0b1000);
        assert_eq!(apply_masks(0xFFFF, and, or), 0xFFFF);
        let (and, or) = bit_masks(3, false);
        assert_eq!(apply_masks(0xFFFF, and, or), 0xFFF7);
        assert_eq!(apply_masks(0x0001, and, or), 0x0001);
        // spec example: current 0x12, and 0xF2, or 0x25 → 0x17
        assert_eq!(apply_masks(0x12, 0xF2, 0x25), 0x17);
    }

    #[test]
    fn planner() {
        // gaps allowed: one read 0..=12
        let reqs = [(10, 2), (0, 1), (5, 2)];
        let p = plan(&reqs, MAX_REGISTERS, false);
        assert_eq!(
            p,
            [Span {
                start: 0,
                count: 12,
                members: vec![1, 2, 0]
            }]
        );
        let words: Vec<u16> = (0..12).collect();
        assert_eq!(slice(&p[0], &words, 10, 2), [10, 11]);
        assert_eq!(slice(&p[0], &words, 5, 2), [5, 6]);
        // contiguous only: three reads
        let p = plan(&reqs, MAX_REGISTERS, true);
        assert_eq!(p.len(), 3);
        assert_eq!((p[0].start, p[0].count), (0, 1));
        assert_eq!((p[2].start, p[2].count), (10, 2));
        // adjacent and overlapping merge even when contiguous_only
        let p = plan(&[(0, 2), (2, 2), (3, 2)], MAX_REGISTERS, true);
        assert_eq!(
            p,
            [Span {
                start: 0,
                count: 5,
                members: vec![0, 1, 2]
            }]
        );
        // max_count splits
        let p = plan(&[(0, 2), (3, 2), (6, 2)], 5, false);
        assert_eq!(p.len(), 2);
        assert_eq!(
            (p[0].start, p[0].count, p[0].members.clone()),
            (0, 5, vec![0, 1])
        );
        assert_eq!((p[1].start, p[1].count), (6, 2));
        // a request larger than max_count stands alone
        let p = plan(&[(0, 10), (10, 1)], 4, false);
        assert_eq!(p.len(), 2);
        assert_eq!(p[0].count, 10);
        // duplicates share one span
        let p = plan(&[(7, 1), (7, 1)], MAX_BITS, true);
        assert_eq!(p.len(), 1);
        assert_eq!(p[0].members.len(), 2);
        // no requests, no spans; top of the address space does not overflow
        assert!(plan(&[], MAX_REGISTERS, false).is_empty());
        let p = plan(&[(65534, 2), (65530, 1)], MAX_REGISTERS, false);
        assert_eq!((p[0].start, p[0].count), (65530, 6));
    }
}
