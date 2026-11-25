//! KNX datapoint types (DPT): the octets of a group value and the value
//! the tree shows for them.
//!
//! | Main | Octets | Value |
//! |---|---|---|
//! | 1 | 1 bit | bool |
//! | 2 | 2 bits | number 0…3 (bit 1 = control, bit 0 = value) |
//! | 3 | 4 bits | number −7…7 (sign = direction, 0 = stop) |
//! | 5, 6 | 1 | number (5.001 in %, 5.003 in °) |
//! | 7, 8 | 2 | number |
//! | 9 | 2 | number (KNX 2-octet float) |
//! | 10 | 3 | text `HH:MM:SS`, with a day `Mon HH:MM:SS` |
//! | 11 | 3 | text `YYYY-MM-DD` |
//! | 12, 13 | 4 | number |
//! | 14 | 4 | number (IEEE 754 single) |
//! | 16 | 14 | text |
//! | 17 | 1 | number 0…63 (scene) |
//! | 18 | 1 | number 0…63, +128 to learn the scene |
//! | 19 | 8 | text `YYYY-MM-DDTHH:MM:SS` |
//! | 20 | 1 | number; 20.102 an enum (HVAC mode) |
//! | 232.600 | 3 | text `#RRGGBB` |
//! | other | any | the raw octets |

use crate::cemi::{Data, MAX_DATA};
use std::fmt;
use wyrm_core::value::whole;
use wyrm_core::{TypeCode, Value};

wyrm_core::name_enum! {
    /// DPT 20.102: the operating mode of a room controller, by its code.
    pub enum HvacMode as "HVAC mode" without codec {
        Auto => "Auto",
        Comfort => "Comfort",
        Standby => "Standby",
        Economy => "Economy",
        BuildingProtection => "Building Protection",
    }
}

wyrm_core::name_enum! {
    /// Day of the week of DPT 10: 1 = Monday … 7 = Sunday.
    pub enum Weekday as "day of the week" without codec {
        Mon => "Mon",
        Tue => "Tue",
        Wed => "Wed",
        Thu => "Thu",
        Fri => "Fri",
        Sat => "Sat",
        Sun => "Sun",
    }
}

/// Why a value and a datapoint type do not fit.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum DptError {
    #[error("{0:?} is not a datapoint type (9.001, 9, DPT-9-1, DPST-9-1)")]
    Name(String),
    #[error("DPT {dpt} takes {want} octets, the telegram has {got}")]
    Length { dpt: Dpt, want: usize, got: usize },
    #[error("DPT {dpt}: expected {want}")]
    Type { dpt: Dpt, want: &'static str },
    #[error("DPT {dpt}: {value} is out of range ({min} … {max})")]
    Range {
        dpt: Dpt,
        value: f64,
        min: f64,
        max: f64,
    },
    #[error("DPT {dpt}: {why}")]
    Invalid { dpt: Dpt, why: &'static str },
}

/// A datapoint type: main number and subtype (0 = not given).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Dpt {
    pub main: u16,
    pub sub: u16,
}

impl fmt::Display for Dpt {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.sub == 0 {
            write!(f, "{}", self.main)
        } else {
            write!(f, "{}.{:03}", self.main, self.sub)
        }
    }
}

/// How the octets of a main number are read.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Bool,
    Control,
    Step,
    U8,
    I8,
    U16,
    I16,
    Float16,
    Time,
    Date,
    U32,
    I32,
    Float32,
    Text,
    Scene,
    SceneControl,
    DateTime,
    Enum,
    Rgb,
    Raw,
}

impl Dpt {
    pub const fn new(main: u16, sub: u16) -> Self {
        Dpt { main, sub }
    }

    /// `9.001`, `9`, and the forms of an ETS export: `DPT-9`, `DPST-9-1`.
    pub fn parse(text: &str) -> Result<Self, DptError> {
        let bad = || DptError::Name(text.to_owned());
        let t = text.trim();
        let upper = t.to_ascii_uppercase();
        let body = upper
            .strip_prefix("DPST")
            .or_else(|| upper.strip_prefix("DPT"))
            .unwrap_or(&upper);
        let body = body.trim_start_matches(['-', ' ', '_']);
        let mut parts = body.split(['.', '-']);
        let main: u16 = parts.next().and_then(|p| p.parse().ok()).ok_or_else(bad)?;
        let sub: u16 = match parts.next() {
            None | Some("*" | "X" | "XXX") => 0,
            Some(p) => p.parse().map_err(|_e: std::num::ParseIntError| bad())?,
        };
        if parts.next().is_some() || main == 0 {
            return Err(bad());
        }
        Ok(Dpt { main, sub })
    }

    fn kind(self) -> Kind {
        match self.main {
            1 => Kind::Bool,
            2 => Kind::Control,
            3 => Kind::Step,
            5 => Kind::U8,
            6 => Kind::I8,
            7 => Kind::U16,
            8 => Kind::I16,
            9 => Kind::Float16,
            10 => Kind::Time,
            11 => Kind::Date,
            12 => Kind::U32,
            13 => Kind::I32,
            14 => Kind::Float32,
            16 => Kind::Text,
            17 => Kind::Scene,
            18 => Kind::SceneControl,
            19 => Kind::DateTime,
            20 => Kind::Enum,
            232 if self.sub == 600 => Kind::Rgb,
            _ => Kind::Raw,
        }
    }

    /// Whether the link knows how to read this type (else: raw octets).
    pub fn known(self) -> bool {
        self.kind() != Kind::Raw
    }

    /// The value rides in the six bits beside the APCI.
    fn short(self) -> bool {
        matches!(self.kind(), Kind::Bool | Kind::Control | Kind::Step)
    }

    /// Octets of the value (1 for the six-bit types); `None`: any number.
    fn octets(self) -> Option<usize> {
        Some(match self.kind() {
            Kind::Bool
            | Kind::Control
            | Kind::Step
            | Kind::U8
            | Kind::I8
            | Kind::Scene
            | Kind::SceneControl
            | Kind::Enum => 1,
            Kind::U16 | Kind::I16 | Kind::Float16 => 2,
            Kind::Time | Kind::Date | Kind::Rgb => 3,
            Kind::U32 | Kind::I32 | Kind::Float32 => 4,
            Kind::DateTime => 8,
            Kind::Text => MAX_DATA,
            Kind::Raw => return None,
        })
    }

    /// The type of the point's value.
    pub fn type_code(self) -> TypeCode {
        match self.kind() {
            Kind::Bool => TypeCode::Bool,
            Kind::Time | Kind::Date | Kind::DateTime | Kind::Text | Kind::Rgb => TypeCode::String,
            Kind::Enum if !self.enum_values().is_empty() => TypeCode::Enum,
            Kind::Raw => TypeCode::Binary,
            _ => TypeCode::Number,
        }
    }

    /// The names of an enum type's values, by code.
    pub fn enum_values(self) -> &'static [&'static str] {
        match (self.main, self.sub) {
            (20, 102) => HvacMode::NAMES,
            _ => &[],
        }
    }

    /// `value = raw × mul / div` for the scaled integer types.
    fn scale(self) -> (u32, u32) {
        match (self.main, self.sub) {
            (5, 1) => (100, 255),
            (5, 3) => (360, 255),
            (7 | 8, 3) => (10, 1),
            (7 | 8, 4) => (100, 1),
            (8, 10) => (1, 100),
            _ => (1, 1),
        }
    }

    /// The unit of the value, empty when the subtype has none or is not
    /// in this table.
    pub fn unit(self) -> &'static str {
        match (self.main, self.sub) {
            (5, 1 | 4) | (6, 1) | (8, 10) | (9, 7) => "%",
            (5, 3) | (8, 11) => "°",
            (7, 2..=4) | (8, 2..=4) | (9, 11) => "ms",
            (7 | 8, 5) | (9, 10) | (13, 100) | (14, 74) => "s",
            (7 | 8, 6) => "min",
            (7 | 8, 7) => "h",
            (7, 11) => "mm",
            (7, 12) | (9, 21) => "mA",
            (7, 13) | (9, 4) => "lx",
            (7, 600) | (9, 2) | (14, 69) => "K",
            (8, 12) | (14, 39) => "m",
            (9, 1) | (14, 68) => "°C",
            (9, 3) => "K/h",
            (9, 5) | (14, 65) => "m/s",
            (9, 6) | (14, 58) => "Pa",
            (9, 8) => "ppm",
            (9, 20) => "mV",
            (9, 22) => "W/m²",
            (9, 23) => "K/%",
            (9, 24) => "kW",
            (9, 25) => "l/h",
            (9, 26) => "l/m²",
            (9, 27) => "°F",
            (9, 28) => "km/h",
            (12, 100) => "s",
            (13, 2) => "m³/h",
            (13, 10) => "Wh",
            (13, 11) => "VAh",
            (13, 12) => "VARh",
            (13, 13) => "kWh",
            (13, 14) => "kVAh",
            (13, 15) => "kVARh",
            (14, 19) => "A",
            (14, 27) => "V",
            (14, 31) => "J",
            (14, 33) => "Hz",
            (14, 51) => "kg",
            (14, 56) => "W",
            (14, 76) => "m³",
            (14, 77) => "m³/s",
            (14, 79) => "W",
            _ => "",
        }
    }

    fn wrong(self, want: &'static str) -> DptError {
        DptError::Type { dpt: self, want }
    }

    fn invalid(self, why: &'static str) -> DptError {
        DptError::Invalid { dpt: self, why }
    }

    /// The octets of `data` when their number fits the type.
    fn sized(self, data: &Data) -> Result<&[u8], DptError> {
        let want = self.octets();
        if want.is_some_and(|w| w != data.bytes.len()) {
            return Err(DptError::Length {
                dpt: self,
                want: want.unwrap_or(data.bytes.len() + 1),
                got: data.bytes.len(),
            });
        }
        Ok(&data.bytes)
    }

    /// The value of a telegram's octets.
    pub fn decode(self, data: &Data) -> Result<Value, DptError> {
        let b = self.sized(data)?;
        let first = b.first().copied().unwrap_or(0);
        Ok(match self.kind() {
            Kind::Bool => Value::Bool(first & 0x01 != 0),
            Kind::Control => Value::UInt(u64::from(first & 0x03)),
            Kind::Step => {
                let step = i64::from(first & 0x07);
                Value::from(if first & 0x08 != 0 { step } else { -step })
            }
            Kind::U8 => self.scaled(i64::from(first)),
            Kind::I8 => self.scaled(i64::from(i8::from_be_bytes([first]))),
            Kind::U16 => self.scaled(i64::from(u16::from_be_bytes(array(b)))),
            Kind::I16 => self.scaled(i64::from(i16::from_be_bytes(array(b)))),
            Kind::Float16 => Value::Float(self.float16(u16::from_be_bytes(array(b)))?),
            Kind::U32 => Value::UInt(u64::from(u32::from_be_bytes(array(b)))),
            Kind::I32 => Value::from(i64::from(i32::from_be_bytes(array(b)))),
            Kind::Float32 => Value::Float(f64::from(f32::from_be_bytes(array(b)))),
            Kind::Scene => Value::UInt(u64::from(first & 0x3F)),
            Kind::SceneControl => Value::UInt(u64::from(first & 0xBF)),
            Kind::Enum => Value::UInt(u64::from(first)),
            Kind::Time => Value::Str(self.time_text(array(b))?),
            Kind::Date => Value::Str(self.date_text(array(b))?),
            Kind::DateTime => Value::Str(self.date_time_text(array(b))?),
            Kind::Text => Value::Str(self.text(b)),
            Kind::Rgb => Value::Str(format!("#{}", wyrm_core::hex::encode_upper(b))),
            Kind::Raw => Value::Bytes(b.to_vec()),
        })
    }

    /// The octets of a value to write.
    pub fn encode(self, v: &Value) -> Result<Data, DptError> {
        let data = match self.kind() {
            Kind::Bool => vec![u8::from(self.truth(v)?)],
            Kind::Control => vec![self.int(v, 0, 3)?],
            Kind::Step => {
                let step: i8 = self.int(v, -7, 7)?;
                vec![step.unsigned_abs() | if step > 0 { 0x08 } else { 0 }]
            }
            Kind::U8 => vec![self.unscaled(v, 0, 255)?],
            Kind::I8 => self.unscaled::<i8>(v, -128, 127)?.to_be_bytes().to_vec(),
            Kind::U16 => self.unscaled::<u16>(v, 0, 65_535)?.to_be_bytes().to_vec(),
            Kind::I16 => self
                .unscaled::<i16>(v, -32_768, 32_767)?
                .to_be_bytes()
                .to_vec(),
            Kind::Float16 => self.to_float16(self.number(v)?)?.to_be_bytes().to_vec(),
            Kind::U32 => self
                .int::<u32>(v, 0, i64::from(u32::MAX))?
                .to_be_bytes()
                .to_vec(),
            Kind::I32 => self
                .int::<i32>(v, i64::from(i32::MIN), i64::from(i32::MAX))?
                .to_be_bytes()
                .to_vec(),
            Kind::Float32 => self.to_float32(self.number(v)?)?.to_be_bytes().to_vec(),
            Kind::Scene => vec![self.int(v, 0, 63)?],
            Kind::SceneControl => {
                let code: u8 = self.int(v, 0, 191)?;
                if code & 0x40 != 0 {
                    return Err(self.invalid("a scene is 0…63, or 128…191 to learn it"));
                }
                vec![code]
            }
            Kind::Enum => vec![self.int(v, 0, 255)?],
            Kind::Time => self.time_octets(self.string(v)?)?.to_vec(),
            Kind::Date => self.date_octets(self.string(v)?)?.to_vec(),
            Kind::DateTime => self.date_time_octets(self.string(v)?)?.to_vec(),
            Kind::Text => self.text_octets(self.string(v)?)?,
            Kind::Rgb => self.rgb_octets(self.string(v)?)?,
            Kind::Raw => self.raw_octets(v)?,
        };
        Ok(if self.short() {
            Data::short(data.first().copied().unwrap_or(0))
        } else {
            Data::long(data)
        })
    }

    fn scaled(self, raw: i64) -> Value {
        match self.scale() {
            (mul, 1) => Value::from(raw * i64::from(mul)),
            (mul, div) => Value::Float(to_f64(raw) * f64::from(mul) / f64::from(div)),
        }
    }

    /// The raw integer of a scaled value, rounded to the nearest step.
    fn unscaled<T: TryFrom<i64>>(self, v: &Value, min: i64, max: i64) -> Result<T, DptError> {
        let (mul, div) = self.scale();
        if (mul, div) == (1, 1) {
            return self.int(v, min, max);
        }
        let (mul, div) = (f64::from(mul), f64::from(div));
        let value = self.number(v)?;
        let range = DptError::Range {
            dpt: self,
            value,
            min: to_f64(min) * mul / div,
            max: to_f64(max) * mul / div,
        };
        let raw = whole((value * div / mul).round()).map_err(|_e| range.clone())?;
        if raw < min || raw > max {
            return Err(range);
        }
        T::try_from(raw).map_err(|_e| range)
    }

    fn number(self, v: &Value) -> Result<f64, DptError> {
        let n = match v {
            Value::Float(f) => *f,
            Value::Bool(b) => f64::from(u8::from(*b)),
            other => to_f64(other.to_int::<i64>().map_err(|_e| self.wrong("a number"))?),
        };
        if n.is_finite() {
            Ok(n)
        } else {
            Err(self.wrong("a finite number"))
        }
    }

    fn int<T: TryFrom<i64>>(self, v: &Value, min: i64, max: i64) -> Result<T, DptError> {
        let range = |value: f64| DptError::Range {
            dpt: self,
            value,
            min: to_f64(min),
            max: to_f64(max),
        };
        let n = match v {
            Value::Bool(b) => i64::from(*b),
            Value::Float(f) => whole(*f).map_err(|_e| self.wrong("a whole number"))?,
            other => other
                .to_int::<i64>()
                .map_err(|_e| self.wrong("a whole number"))?,
        };
        if n < min || n > max {
            return Err(range(to_f64(n)));
        }
        T::try_from(n).map_err(|_e| range(to_f64(n)))
    }

    fn truth(self, v: &Value) -> Result<bool, DptError> {
        match v {
            Value::Bool(b) => Ok(*b),
            other => Ok(self.int::<u8>(other, 0, 1)? == 1),
        }
    }

    fn string(self, v: &Value) -> Result<&str, DptError> {
        match v {
            Value::Str(s) => Ok(s),
            _ => Err(self.wrong("text")),
        }
    }

    /// `0.01 × mantissa × 2^exponent`, the mantissa a 12-bit two's
    /// complement number whose sign is bit 15.
    fn float16(self, w: u16) -> Result<f64, DptError> {
        if w == 0x7FFF {
            return Err(self.invalid("the device sent 0x7FFF: invalid data"));
        }
        let exponent = (w >> 11) & 0x0F;
        let mut mantissa = i32::from(w & 0x07FF);
        if w & 0x8000 != 0 {
            mantissa -= 2048;
        }
        Ok(f64::from(mantissa) * f64::from(1u32 << exponent) / 100.0)
    }

    fn to_float16(self, value: f64) -> Result<u16, DptError> {
        let range = DptError::Range {
            dpt: self,
            value,
            min: -671_088.64,
            max: 670_760.96,
        };
        let mut scaled = value * 100.0;
        let mut exponent = 0u16;
        while !(-2048.0..=2047.0).contains(&scaled.round()) {
            scaled /= 2.0;
            exponent += 1;
            if exponent > 15 {
                return Err(range);
            }
        }
        let mantissa = whole(scaled.round()).map_err(|_e| range.clone())?;
        let twelve = u16::try_from(mantissa.rem_euclid(4096)).map_err(|_e| range)?;
        Ok(((twelve & 0x0800) << 4) | (exponent << 11) | (twelve & 0x07FF))
    }

    fn to_float32(self, value: f64) -> Result<f32, DptError> {
        let text = format!("{value:e}");
        let single: f32 = text
            .parse()
            .map_err(|_e: std::num::ParseFloatError| self.wrong("a number"))?;
        if single.is_finite() {
            Ok(single)
        } else {
            Err(DptError::Range {
                dpt: self,
                value,
                min: f64::from(f32::MIN),
                max: f64::from(f32::MAX),
            })
        }
    }

    fn time_text(self, [d, m, s]: [u8; 3]) -> Result<String, DptError> {
        let (day, hour, minute, second) = (d >> 5, d & 0x1F, m & 0x3F, s & 0x3F);
        if hour > 23 || minute > 59 || second > 59 {
            return Err(self.invalid("not a time of day"));
        }
        let clock = format!("{hour:02}:{minute:02}:{second:02}");
        Ok(match usize::from(day).checked_sub(1) {
            None => clock,
            Some(i) => match Weekday::ALL.get(i) {
                Some(day) => format!("{day} {clock}"),
                None => clock,
            },
        })
    }

    fn time_octets(self, text: &str) -> Result<[u8; 3], DptError> {
        let bad = || self.wrong("a time as HH:MM:SS, or with a day as Mon HH:MM:SS");
        let text = text.trim();
        let (day, clock) = match text.split_once(' ') {
            Some((day, clock)) => {
                let day = Weekday::from_name(day).ok_or_else(bad)?;
                let i = Weekday::ALL
                    .iter()
                    .position(|d| *d == day)
                    .ok_or_else(bad)?;
                (u8::try_from(i + 1).map_err(|_e| bad())?, clock.trim())
            }
            None => (0, text),
        };
        let [hour, minute, second] = clock_parts(clock).ok_or_else(bad)?;
        Ok([(day << 5) | hour, minute, second])
    }

    fn date_text(self, [d, m, y]: [u8; 3]) -> Result<String, DptError> {
        let (day, month, year) = (d & 0x1F, m & 0x0F, u16::from(y & 0x7F));
        if day == 0 || month == 0 || month > 12 || year > 99 {
            return Err(self.invalid("not a date"));
        }
        // the two-digit year: 90…99 are 1990…1999, 0…89 are 2000…2089
        let year = if year >= 90 { 1900 + year } else { 2000 + year };
        Ok(format!("{year:04}-{month:02}-{day:02}"))
    }

    fn date_octets(self, text: &str) -> Result<[u8; 3], DptError> {
        let bad = || self.wrong("a date as YYYY-MM-DD, 1990…2089");
        let [year, month, day] = date_parts(text.trim()).ok_or_else(bad)?;
        let two = match year {
            1990..=1999 => year - 1900,
            2000..=2089 => year - 2000,
            _ => return Err(bad()),
        };
        Ok([
            u8::try_from(day).map_err(|_e| bad())?,
            u8::try_from(month).map_err(|_e| bad())?,
            u8::try_from(two).map_err(|_e| bad())?,
        ])
    }

    fn date_time_text(self, b: [u8; 8]) -> Result<String, DptError> {
        let [year, month, day, hour, minute, second, flags, _quality] = b;
        if flags & 0x80 != 0 {
            return Err(self.invalid("the device says its clock has a fault"));
        }
        let (month, day, hour) = (month & 0x0F, day & 0x1F, hour & 0x1F);
        let (minute, second) = (minute & 0x3F, second & 0x3F);
        if month == 0 || month > 12 || day == 0 || hour > 24 || minute > 59 || second > 59 {
            return Err(self.invalid("not a date and time"));
        }
        let year = 1900 + u16::from(year);
        Ok(format!(
            "{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}"
        ))
    }

    fn date_time_octets(self, text: &str) -> Result<[u8; 8], DptError> {
        let bad = || self.wrong("a date and time as YYYY-MM-DDTHH:MM:SS, 1900…2155");
        let text = text.trim();
        let (date, clock) = text
            .split_once('T')
            .or_else(|| text.split_once(' '))
            .ok_or_else(bad)?;
        let [year, month, day] = date_parts(date).ok_or_else(bad)?;
        let [hour, minute, second] = clock_parts(clock.trim_end_matches('Z')).ok_or_else(bad)?;
        let year = year
            .checked_sub(1900)
            .and_then(|y| u8::try_from(y).ok())
            .ok_or_else(bad)?;
        Ok([
            year,
            u8::try_from(month).map_err(|_e| bad())?,
            u8::try_from(day).map_err(|_e| bad())?,
            // no day of the week
            hour,
            minute,
            second,
            // no working-day information, no day of the week
            0x24,
            0x00,
        ])
    }

    fn text(self, b: &[u8]) -> String {
        b.iter()
            .take_while(|c| **c != 0)
            .map(|c| match (self.sub, *c) {
                // 16.000 is ASCII
                (0, 0x80..) => '?',
                (_, c) => char::from(c),
            })
            .collect()
    }

    fn text_octets(self, text: &str) -> Result<Vec<u8>, DptError> {
        let limit = if self.sub == 0 { 0x7F } else { 0xFF };
        let mut out = Vec::with_capacity(MAX_DATA);
        for ch in text.chars() {
            match u8::try_from(u32::from(ch)) {
                Ok(c) if c <= limit && c != 0 => out.push(c),
                _ => {
                    return Err(self.invalid(
                        "a character outside the type's set (16.000 ASCII, 16.001 ISO 8859-1)",
                    ))
                }
            }
        }
        if out.len() > MAX_DATA {
            return Err(self.invalid("more than 14 characters"));
        }
        out.resize(MAX_DATA, 0);
        Ok(out)
    }

    fn rgb_octets(self, text: &str) -> Result<Vec<u8>, DptError> {
        let digits = text.trim().trim_start_matches('#');
        wyrm_core::hex::decode_array::<3>(digits)
            .map(Vec::from)
            .ok_or_else(|| self.wrong("a colour as #RRGGBB"))
    }

    fn raw_octets(self, v: &Value) -> Result<Vec<u8>, DptError> {
        let want = "octets (binary, or text of hex digits), 1…14";
        let bytes = match v {
            Value::Bytes(b) => b.clone(),
            Value::Str(s) => wyrm_core::hex::decode(s.trim()).ok_or_else(|| self.wrong(want))?,
            _ => return Err(self.wrong(want)),
        };
        if bytes.is_empty() || bytes.len() > MAX_DATA {
            return Err(self.wrong(want));
        }
        Ok(bytes)
    }
}

/// `b` as an array; zeros when the length is another one (the callers
/// checked it with [`Dpt::sized`]).
fn array<const N: usize>(b: &[u8]) -> [u8; N] {
    b.try_into().unwrap_or([0; N])
}

/// An integer of a telegram (at most 32 bits) as a float, exactly.
fn to_f64(n: i64) -> f64 {
    match i32::try_from(n) {
        Ok(small) => f64::from(small),
        Err(_) => {
            let high = i32::try_from(n >> 31).map_or(0.0, f64::from);
            let low = u32::try_from(n & 0x7FFF_FFFF).map_or(0.0, f64::from);
            high * 2_147_483_648.0 + low
        }
    }
}

/// `HH:MM:SS` or `HH:MM`.
fn clock_parts(text: &str) -> Option<[u8; 3]> {
    let mut parts = text.split(':').map(|p| p.trim().parse::<u8>().ok());
    let hour = parts.next()??;
    let minute = parts.next()??;
    let second = match parts.next() {
        Some(s) => s?,
        None => 0,
    };
    (parts.next().is_none() && hour <= 23 && minute <= 59 && second <= 59)
        .then_some([hour, minute, second])
}

/// `YYYY-MM-DD` as year, month, day.
fn date_parts(text: &str) -> Option<[u16; 3]> {
    let mut parts = text.split('-').map(|p| p.trim().parse::<u16>().ok());
    let (year, month, day) = (parts.next()??, parts.next()??, parts.next()??);
    let long = matches!(month, 1 | 3 | 5 | 7 | 8 | 10 | 12);
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days = match month {
        2 if leap => 29,
        2 => 28,
        _ if long => 31,
        _ => 30,
    };
    (parts.next().is_none() && (1..=12).contains(&month) && (1..=days).contains(&day))
        .then_some([year, month, day])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dpt(text: &str) -> Dpt {
        Dpt::parse(text).unwrap()
    }

    /// `text` decodes `octets` to `value`, and `value` encodes back.
    fn both(text: &str, octets: &[u8], value: Value) {
        let d = dpt(text);
        let data = if d.short() {
            Data::short(octets[0])
        } else {
            Data::long(octets.to_vec())
        };
        assert_eq!(d.decode(&data).unwrap(), value, "decode {text}");
        assert_eq!(d.encode(&value).unwrap(), data, "encode {text}");
    }

    #[test]
    fn names() {
        assert_eq!(dpt("9.001"), Dpt::new(9, 1));
        assert_eq!(dpt("9"), Dpt::new(9, 0));
        assert_eq!(dpt("DPST-9-1"), Dpt::new(9, 1));
        assert_eq!(dpt("DPT-9"), Dpt::new(9, 0));
        assert_eq!(dpt("dpst-232-600"), Dpt::new(232, 600));
        assert_eq!(dpt(" DPT 5.001 "), Dpt::new(5, 1));
        assert_eq!(dpt("1.*"), Dpt::new(1, 0));
        assert_eq!(Dpt::new(9, 1).to_string(), "9.001");
        assert_eq!(Dpt::new(232, 600).to_string(), "232.600");
        assert_eq!(Dpt::new(14, 0).to_string(), "14");
        for bad in ["", "x", "9.a", "9.1.2", "0.1", "DPT"] {
            assert!(matches!(Dpt::parse(bad), Err(DptError::Name(_))), "{bad}");
        }
    }

    #[test]
    fn bits() {
        both("1.001", &[1], Value::Bool(true));
        both("1.008", &[0], Value::Bool(false));
        both("2.001", &[0b11], Value::UInt(3));
        // 3.007 dimming: increase by step code 5, decrease by 3, stop
        both("3.007", &[0b1101], Value::UInt(5));
        both("3.007", &[0b0011], Value::Int(-3));
        both("3.007", &[0], Value::UInt(0));
        assert_eq!(
            dpt("1.001").encode(&Value::UInt(1)).unwrap(),
            Data::short(1)
        );
        assert!(dpt("1.001").encode(&Value::UInt(2)).is_err());
        assert!(dpt("3.007").encode(&Value::Int(8)).is_err());
        // a one-bit value sent as a whole octet is taken too
        assert_eq!(
            dpt("1.001").decode(&Data::long(vec![1])).unwrap(),
            Value::Bool(true)
        );
    }

    #[test]
    fn one_octet() {
        // 5.001: 0…255 is 0…100 %
        both("5.001", &[0xFF], Value::Float(100.0));
        both("5.001", &[0x00], Value::Float(0.0));
        assert_eq!(
            dpt("5.001").encode(&Value::Float(50.0)).unwrap(),
            Data::long(vec![0x80])
        );
        // 5.003: 0…255 is 0…360°
        both("5.003", &[0xFF], Value::Float(360.0));
        assert_eq!(
            dpt("5.003").encode(&Value::UInt(180)).unwrap(),
            Data::long(vec![0x80])
        );
        both("5.010", &[0xC8], Value::UInt(200));
        both("6.010", &[0xFF], Value::Int(-1));
        both("6.001", &[0x80], Value::Int(-128));
        both("17.001", &[0x3F], Value::UInt(63));
        both("18.001", &[0x85], Value::UInt(133));
        both("20.102", &[0x03], Value::UInt(3));
        assert!(dpt("5.001").encode(&Value::Float(100.5)).is_err());
        assert!(dpt("5.010").encode(&Value::UInt(256)).is_err());
        assert!(dpt("5.010").encode(&Value::Float(1.5)).is_err());
        assert!(dpt("17.001").encode(&Value::UInt(64)).is_err());
        assert!(dpt("18.001").encode(&Value::UInt(64)).is_err());
    }

    #[test]
    fn two_octets() {
        both("7.001", &[0xFF, 0xFF], Value::UInt(65_535));
        both("7.003", &[0x00, 0x64], Value::UInt(1000));
        both("8.001", &[0x80, 0x00], Value::Int(-32_768));
        both("8.010", &[0x27, 0x10], Value::Float(100.0));
        assert!(dpt("7.001").encode(&Value::Int(-1)).is_err());
    }

    #[test]
    fn two_octet_float() {
        // examples of the KNX datapoint type document
        both("9.001", &[0x0C, 0x1A], Value::Float(21.0));
        both("9.001", &[0x8A, 0x24], Value::Float(-30.0));
        both("9.001", &[0x00, 0x00], Value::Float(0.0));
        both("9.001", &[0x00, 0x01], Value::Float(0.01));
        both("9.001", &[0x87, 0xFF], Value::Float(-0.01));
        both("9.004", &[0x7F, 0xFE], Value::Float(670_433.28));
        both("9.001", &[0xF8, 0x00], Value::Float(-671_088.64));
        let d = dpt("9.001");
        assert_eq!(
            d.encode(&Value::Float(21.5)).unwrap(),
            Data::long(vec![0x0C, 0x33])
        );
        assert_eq!(
            d.encode(&Value::UInt(1)).unwrap(),
            Data::long(vec![0x00, 0x64])
        );
        assert!(matches!(
            d.decode(&Data::long(vec![0x7F, 0xFF])),
            Err(DptError::Invalid { .. })
        ));
        assert!(matches!(
            d.encode(&Value::Float(700_000.0)),
            Err(DptError::Range { .. })
        ));
        assert!(d.encode(&Value::Float(f64::NAN)).is_err());
        assert!(d.encode(&Value::Str("21".into())).is_err());
    }

    #[test]
    fn time_and_date() {
        both("10.001", &[0x0C, 0x1E, 0x00], Value::Str("12:30:00".into()));
        // Monday 23:59:59
        both(
            "10.001",
            &[0x37, 0x3B, 0x3B],
            Value::Str("Mon 23:59:59".into()),
        );
        both(
            "11.001",
            &[0x1F, 0x0C, 0x63],
            Value::Str("1999-12-31".into()),
        );
        both(
            "11.001",
            &[0x01, 0x01, 0x00],
            Value::Str("2000-01-01".into()),
        );
        both(
            "11.001",
            &[0x1A, 0x0B, 0x1A],
            Value::Str("2026-11-26".into()),
        );
        both(
            "19.001",
            &[0x7E, 0x0B, 0x1A, 0x0D, 0x25, 0x08, 0x24, 0x00],
            Value::Str("2026-11-26T13:37:08".into()),
        );
        let t = dpt("10.001");
        assert_eq!(
            t.encode(&Value::Str("7:05".into())).unwrap(),
            Data::long(vec![7, 5, 0])
        );
        assert!(t.encode(&Value::Str("24:00:00".into())).is_err());
        assert!(t.encode(&Value::Str("Xyz 10:00:00".into())).is_err());
        assert!(t.decode(&Data::long(vec![0x18, 0, 0])).is_err());
        let d = dpt("11.001");
        assert!(d.encode(&Value::Str("2026-02-30".into())).is_err());
        assert!(d.encode(&Value::Str("1989-01-01".into())).is_err());
        assert!(d.decode(&Data::long(vec![0, 1, 0])).is_err());
        let dt = dpt("19.001");
        assert!(dt
            .decode(&Data::long(vec![
                0x7E, 0x0B, 0x1A, 0x0D, 0x25, 0x08, 0x80, 0
            ]))
            .is_err());
        assert_eq!(
            dt.encode(&Value::Str("2026-11-26 13:37:08".into()))
                .unwrap()
                .bytes[..3],
            [0x7E, 0x0B, 0x1A]
        );
    }

    #[test]
    fn four_octets() {
        both(
            "12.001",
            &[0xFF, 0xFF, 0xFF, 0xFF],
            Value::UInt(4_294_967_295),
        );
        both("13.010", &[0xFF, 0xFF, 0xFF, 0xFE], Value::Int(-2));
        both("14.056", &[0x44, 0x7A, 0x00, 0x00], Value::Float(1000.0));
        both("14.068", &[0xC1, 0xA4, 0x00, 0x00], Value::Float(-20.5));
        assert!(dpt("12.001").encode(&Value::Int(-1)).is_err());
        assert!(dpt("14.056").encode(&Value::Float(1e300)).is_err());
    }

    #[test]
    fn text_and_colour() {
        let mut hello = b"KNX is OK".to_vec();
        hello.resize(14, 0);
        both("16.000", &hello, Value::Str("KNX is OK".into()));
        let mut latin = vec![b'2', b'1', 0xB0, b'C'];
        latin.resize(14, 0);
        both("16.001", &latin, Value::Str("21°C".into()));
        assert!(dpt("16.000").encode(&Value::Str("21°C".into())).is_err());
        assert!(dpt("16.001")
            .encode(&Value::Str("fifteen letters".into()))
            .is_err());
        assert!(dpt("16.001").encode(&Value::Str("€".into())).is_err());
        both("232.600", &[0xFF, 0x80, 0x00], Value::Str("#FF8000".into()));
        assert_eq!(
            dpt("232.600").encode(&Value::Str("ff8000".into())).unwrap(),
            Data::long(vec![0xFF, 0x80, 0x00])
        );
        assert!(dpt("232.600").encode(&Value::Str("#FF80".into())).is_err());
    }

    #[test]
    fn unknown_types_are_raw() {
        let d = dpt("240.800");
        assert!(!d.known());
        assert_eq!(d.type_code(), TypeCode::Binary);
        both("240.800", &[1, 2, 3], Value::Bytes(vec![1, 2, 3]));
        assert_eq!(
            d.decode(&Data::short(0x21)).unwrap(),
            Value::Bytes(vec![0x21])
        );
        assert_eq!(
            d.encode(&Value::Str("0a0b".into())).unwrap(),
            Data::long(vec![0x0A, 0x0B])
        );
        assert!(d.encode(&Value::Bytes(vec![0; 15])).is_err());
        assert!(d.encode(&Value::UInt(1)).is_err());
    }

    #[test]
    fn lengths_are_checked() {
        assert!(matches!(
            dpt("9.001").decode(&Data::long(vec![1])),
            Err(DptError::Length {
                want: 2,
                got: 1,
                ..
            })
        ));
        assert!(matches!(
            dpt("9.001").decode(&Data::short(1)),
            Err(DptError::Length { .. })
        ));
        assert!(dpt("16.001").decode(&Data::long(vec![b'a'; 3])).is_err());
    }

    #[test]
    fn meta() {
        assert_eq!(dpt("9.001").unit(), "°C");
        assert_eq!(dpt("5.001").unit(), "%");
        assert_eq!(dpt("13.013").unit(), "kWh");
        assert_eq!(dpt("9").unit(), "");
        assert_eq!(dpt("1.001").type_code(), TypeCode::Bool);
        assert_eq!(dpt("16.001").type_code(), TypeCode::String);
        assert_eq!(dpt("20.102").type_code(), TypeCode::Enum);
        assert_eq!(dpt("20.105").type_code(), TypeCode::Number);
        assert_eq!(dpt("20.102").enum_values()[1], "Comfort");
        assert_eq!(dpt("20.102").enum_values().len(), 5);
    }
}
