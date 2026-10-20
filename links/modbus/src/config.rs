//! Link config: one Modbus TCP device (unit) per link instance.

use std::time::Duration;
use wyrm_core::Value;
use wyrm_link_sdk::params::narrow;
use wyrm_link_sdk::{Fields, FromParams, LinkError, Result};

#[derive(Debug, Clone, PartialEq)]
pub struct ModbusConfig {
    pub host: String,
    pub port: u16,
    pub unit: u8,
    pub poll_ms: u64,
    /// Bound on every connect, read and write.
    pub timeout_ms: u64,
    /// Failed poll cycles before `uncertain/stale` becomes `bad/comm_fail`.
    pub stale_cycles: u32,
    pub points: Vec<PointConfig>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PointConfig {
    /// Node path under the link, e.g. `ahu1/supply_temp`.
    pub path: String,
    pub table: Table,
    pub address: u16,
    pub kind: DataKind,
    /// `value = raw * scale + offset`.
    pub scale: f64,
    pub offset: f64,
    pub writable: bool,
    pub unit: Option<String>,
    /// 32-bit values: low word first.
    pub word_swap: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Table {
    Coil,
    Discrete,
    Input,
    Holding,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DataKind {
    Bool,
    #[default]
    U16,
    I16,
    U32,
    I32,
    F32,
}

impl FromParams for ModbusConfig {
    /// `{host, port=502, unit=1, poll_ms=1000, timeout_ms=1000, stale_cycles=3,
    /// points: [{path, table, address, kind=u16, scale=1, offset=0,
    /// writable=false, unit?, word_swap=false}]}`
    fn from_params(v: &Value) -> Result<Self> {
        let f = Fields::new(v)?;
        f.only(&[
            "host",
            "port",
            "unit",
            "poll_ms",
            "timeout_ms",
            "stale_cycles",
            "points",
        ])?;
        let points = f
            .list("points")?
            .iter()
            .map(|p| {
                p.only(&[
                    "path",
                    "table",
                    "address",
                    "kind",
                    "scale",
                    "offset",
                    "writable",
                    "unit",
                    "word_swap",
                ])?;
                let table = match p.str("table")? {
                    "coil" => Table::Coil,
                    "discrete" => Table::Discrete,
                    "input" => Table::Input,
                    "holding" => Table::Holding,
                    other => {
                        return Err(LinkError::invalid_parameter(format!(
                            "unknown table {other}"
                        )))
                    }
                };
                let kind = match p.opt_str("kind")?.unwrap_or("u16") {
                    "bool" => DataKind::Bool,
                    "u16" => DataKind::U16,
                    "i16" => DataKind::I16,
                    "u32" => DataKind::U32,
                    "i32" => DataKind::I32,
                    "f32" => DataKind::F32,
                    other => {
                        return Err(LinkError::invalid_parameter(format!(
                            "unknown kind {other}"
                        )))
                    }
                };
                Ok(PointConfig {
                    path: p.str("path")?.to_owned(),
                    table,
                    address: narrow(p.u64_or("address", u64::MAX)?, "address")?,
                    kind,
                    scale: p.f64_or("scale", 1.0)?,
                    offset: p.f64_or("offset", 0.0)?,
                    writable: p.bool_or("writable", false)?,
                    unit: p.opt_str("unit")?.map(str::to_owned),
                    word_swap: p.bool_or("word_swap", false)?,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        let cfg = Self {
            host: f.str("host")?.to_owned(),
            port: narrow(f.u64_or("port", 502)?, "port")?,
            unit: narrow(f.u64_or("unit", 1)?, "unit")?,
            poll_ms: f.u64_or("poll_ms", 1000)?,
            timeout_ms: f.u64_or("timeout_ms", 1000)?,
            stale_cycles: narrow(f.u64_or("stale_cycles", 3)?, "stale_cycles")?,
            points,
        };
        cfg.validate()?;
        Ok(cfg)
    }
}

impl ModbusConfig {
    pub fn timeout(&self) -> Duration {
        Duration::from_millis(self.timeout_ms.max(1))
    }

    pub fn poll(&self) -> Duration {
        Duration::from_millis(self.poll_ms.max(10))
    }

    /// Reject configs the driver cannot serve honestly.
    pub fn validate(&self) -> Result<()> {
        if self.points.is_empty() {
            return Err(LinkError::invalid_parameter("no points"));
        }
        for p in &self.points {
            wyrm_core::keyspace::validate_path(&p.path)?;
            let bits = matches!(p.table, Table::Coil | Table::Discrete);
            if bits != (p.kind == DataKind::Bool) {
                return Err(LinkError::invalid_parameter(format!(
                    "{}: coil/discrete tables need kind bool, registers need a numeric kind",
                    p.path
                )));
            }
            if p.writable && !matches!(p.table, Table::Coil | Table::Holding) {
                return Err(LinkError::invalid_parameter(format!(
                    "{}: only coil and holding points can be writable",
                    p.path
                )));
            }
            if !p.scale.is_finite() || p.scale == 0.0 || !p.offset.is_finite() {
                return Err(LinkError::invalid_parameter(format!(
                    "{}: scale must be finite and non-zero, offset finite",
                    p.path
                )));
            }
            if p.address.checked_add(p.kind.words() - 1).is_none() {
                return Err(LinkError::invalid_parameter(format!(
                    "{}: address range overflows",
                    p.path
                )));
            }
        }
        Ok(())
    }
}

impl DataKind {
    /// Registers (or bits) per value.
    pub fn words(self) -> u16 {
        match self {
            DataKind::U32 | DataKind::I32 | DataKind::F32 => 2,
            _ => 1,
        }
    }

    /// Raw value from registers (big-endian words unless `swap`).
    pub fn decode(self, words: &[u16], swap: bool) -> Option<f64> {
        let w32 = || -> Option<u32> {
            let (hi, lo) = (*words.first()?, *words.get(1)?);
            let (hi, lo) = if swap { (lo, hi) } else { (hi, lo) };
            Some(((hi as u32) << 16) | lo as u32)
        };
        Some(match self {
            DataKind::Bool => return None,
            DataKind::U16 => *words.first()? as f64,
            DataKind::I16 => *words.first()? as i16 as f64,
            DataKind::U32 => w32()? as f64,
            DataKind::I32 => w32()? as i32 as f64,
            DataKind::F32 => f32::from_bits(w32()?) as f64,
        })
    }

    /// Registers for a raw value; `None` if it does not fit the kind.
    pub fn encode(self, raw: f64, swap: bool) -> Option<Vec<u16>> {
        if !raw.is_finite() {
            return None;
        }
        let int = |lo: f64, hi: f64| {
            let r = raw.round();
            (lo..=hi).contains(&r).then_some(r)
        };
        let split = |v: u32| {
            let (hi, lo) = ((v >> 16) as u16, v as u16);
            if swap {
                vec![lo, hi]
            } else {
                vec![hi, lo]
            }
        };
        Some(match self {
            DataKind::Bool => return None,
            DataKind::U16 => vec![int(0.0, u16::MAX as f64)? as u16],
            DataKind::I16 => vec![int(i16::MIN as f64, i16::MAX as f64)? as i16 as u16],
            DataKind::U32 => split(int(0.0, u32::MAX as f64)? as u32),
            DataKind::I32 => split(int(i32::MIN as f64, i32::MAX as f64)? as i32 as u32),
            DataKind::F32 => {
                let f = raw as f32;
                if !f.is_finite() {
                    return None;
                }
                split(f.to_bits())
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::DataKind::*;

    #[test]
    fn roundtrip_kinds() {
        for (k, v) in [
            (U16, 65535.0),
            (I16, -2.0),
            (U32, 70000.0),
            (I32, -70000.0),
            (F32, 21.5),
        ] {
            for swap in [false, true] {
                let w = k.encode(v, swap).unwrap();
                assert_eq!(w.len(), k.words() as usize);
                assert_eq!(k.decode(&w, swap), Some(v), "{k:?} swap={swap}");
            }
        }
        assert_eq!(I16.decode(&[0xFFFE], false), Some(-2.0));
        assert_eq!(U32.encode(70000.0, false).unwrap(), [1, 4464]);
        assert!(U16.encode(-1.0, false).is_none());
        assert!(U16.encode(65536.0, false).is_none());
        assert!(I16.encode(f64::NAN, false).is_none());
        assert!(F32.encode(1e300, false).is_none());
    }
}
