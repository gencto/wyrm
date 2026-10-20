//! Zenoh attachment carried with every WYRM sample/query. Spec: 04-attachment.

use crate::status::StatusCode;
use minicbor::{decode, encode, Decode, Decoder, Encode, Encoder};

/// Permission level (spec 04 / 05): 0 none, 1 list, 2 read, 3 write, 4 config.
pub type PermLevel = u8;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Attachment {
    pub status: Option<StatusCode>,
    pub qual: Option<String>,
    pub ts: Option<u64>,
    pub refreshed: Option<bool>,
    pub ptok: Option<Vec<u8>>,
    pub maxperm: Option<PermLevel>,
    pub audit: Option<String>,
    pub err: Option<String>,
    pub rev: Option<u32>,
    pub rid: Option<u32>,
    pub seq: Option<u32>,
    pub last: Option<bool>,
    pub origin: Option<String>,
    pub trace: Option<[u8; 16]>,
    pub enc: Option<String>,
}

impl Attachment {
    pub fn ok() -> Self {
        Self {
            status: Some(crate::Status::Ok.into()),
            ..Default::default()
        }
    }
    pub fn with_status(status: impl Into<StatusCode>) -> Self {
        Self {
            status: Some(status.into()),
            ..Default::default()
        }
    }
    fn count(&self) -> u64 {
        [
            self.status.is_some(),
            self.qual.is_some(),
            self.ts.is_some(),
            self.refreshed.is_some(),
            self.ptok.is_some(),
            self.maxperm.is_some(),
            self.audit.is_some(),
            self.err.is_some(),
            self.rev.is_some(),
            self.rid.is_some(),
            self.seq.is_some(),
            self.last.is_some(),
            self.origin.is_some(),
            self.trace.is_some(),
            self.enc.is_some(),
        ]
        .iter()
        .filter(|b| **b)
        .count() as u64
    }
}

impl<C> Encode<C> for Attachment {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        _ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        e.map(self.count())?;
        if let Some(v) = self.status {
            e.u8(0)?.u8(v.code())?;
        }
        if let Some(v) = &self.qual {
            e.u8(1)?.str(v)?;
        }
        if let Some(v) = self.ts {
            e.u8(2)?.u64(v)?;
        }
        if let Some(v) = self.refreshed {
            e.u8(3)?.bool(v)?;
        }
        if let Some(v) = &self.ptok {
            e.u8(4)?.bytes(v)?;
        }
        if let Some(v) = self.maxperm {
            e.u8(5)?.u8(v)?;
        }
        if let Some(v) = &self.audit {
            e.u8(6)?.str(v)?;
        }
        if let Some(v) = &self.err {
            e.u8(7)?.str(v)?;
        }
        if let Some(v) = self.rev {
            e.u8(8)?.u32(v)?;
        }
        if let Some(v) = self.rid {
            e.u8(9)?.u32(v)?;
        }
        if let Some(v) = self.seq {
            e.u8(10)?.u32(v)?;
        }
        if let Some(v) = self.last {
            e.u8(11)?.bool(v)?;
        }
        if let Some(v) = &self.origin {
            e.u8(12)?.str(v)?;
        }
        if let Some(v) = &self.trace {
            e.u8(13)?.bytes(v)?;
        }
        if let Some(v) = &self.enc {
            e.u8(14)?.str(v)?;
        }
        Ok(())
    }
}

impl<'b, C> Decode<'b, C> for Attachment {
    fn decode(d: &mut Decoder<'b>, _ctx: &mut C) -> Result<Self, decode::Error> {
        let mut a = Attachment::default();
        let n = d
            .map()?
            .ok_or_else(|| decode::Error::message("indefinite attachment map"))?;
        for _ in 0..n {
            match d.u32()? {
                0 => a.status = Some(d.u8()?.into()),
                1 => a.qual = Some(d.str()?.to_owned()),
                2 => a.ts = Some(d.u64()?),
                3 => a.refreshed = Some(d.bool()?),
                4 => a.ptok = Some(d.bytes()?.to_vec()),
                5 => a.maxperm = Some(d.u8()?),
                6 => a.audit = Some(d.str()?.to_owned()),
                7 => a.err = Some(d.str()?.to_owned()),
                8 => a.rev = Some(d.u32()?),
                9 => a.rid = Some(d.u32()?),
                10 => a.seq = Some(d.u32()?),
                11 => a.last = Some(d.bool()?),
                12 => a.origin = Some(d.str()?.to_owned()),
                13 => {
                    let b = d.bytes()?;
                    let arr: [u8; 16] = b
                        .try_into()
                        .map_err(|_| decode::Error::message("trace must be 16 bytes"))?;
                    a.trace = Some(arr);
                }
                14 => a.enc = Some(d.str()?.to_owned()),
                _ => d.skip()?,
            }
        }
        Ok(a)
    }
}
