//! S7comm on ISO-on-TCP, in-crate: TPKT (RFC 1006), COTP class 0 (ISO
//! 8073: connection request/confirm, data), and the S7 PDUs this link
//! uses: Setup Communication, Read Var, Write Var and the userdata SZL
//! read. Pure: frames to bytes and back, no I/O.
//!
//! Every S7 PDU carries a PDU reference chosen by the client and echoed by
//! the PLC; [`S7Reply::pdu_ref`] lets the transport drop a late reply to an
//! earlier request.

use crate::addr::Area;
use std::fmt;

/// TPKT version.
pub const TPKT_VERSION: u8 = 3;
/// The S7 protocol id.
pub const S7_ID: u8 = 0x32;

pub const ROSCTR_JOB: u8 = 1;
pub const ROSCTR_ACK: u8 = 2;
pub const ROSCTR_ACK_DATA: u8 = 3;
pub const ROSCTR_USERDATA: u8 = 7;

pub const FN_SETUP: u8 = 0xF0;
pub const FN_READ: u8 = 0x04;
pub const FN_WRITE: u8 = 0x05;

/// COTP TPDU codes.
pub const COTP_CR: u8 = 0xE0;
pub const COTP_CC: u8 = 0xD0;
pub const COTP_DR: u8 = 0x80;
pub const COTP_DT: u8 = 0xF0;
/// COTP DT: end of TSDU.
pub const COTP_EOT: u8 = 0x80;

/// Item return code: success.
pub const RC_OK: u8 = 0xFF;

/// Request item transport sizes (S7ANY syntax).
pub const TS_BIT: u8 = 0x01;
pub const TS_BYTE: u8 = 0x02;
pub const TS_COUNTER: u8 = 0x1C;
pub const TS_TIMER: u8 = 0x1D;

/// Data transport sizes (reply data and Write Var data).
pub const DTS_NULL: u8 = 0x00;
pub const DTS_BIT: u8 = 0x03;
/// BYTE/WORD/DWORD: the length is in bits.
pub const DTS_BYTE: u8 = 0x04;
/// INTEGER: the length is in bits.
pub const DTS_INT: u8 = 0x05;
/// REAL: the length is in bytes.
pub const DTS_REAL: u8 = 0x07;
/// OCTET STRING: the length is in bytes.
pub const DTS_OCTET: u8 = 0x09;

/// Bytes of a Read Var request beside its items: S7 header (10), function
/// and item count (2).
pub const READ_REQ_FIXED: usize = 12;
/// One request item.
pub const ITEM_SPEC: usize = 12;
/// Bytes of a Read Var reply beside its items: ack-data header (12),
/// function and item count (2).
pub const READ_REP_FIXED: usize = 14;
/// The header of one reply data item.
pub const ITEM_DATA_HDR: usize = 4;
/// A Write Var request of one item beside its data: header (10), function
/// and count (2), the item (12) and the data item header (4).
pub const WRITE_FIXED: usize = 28;
/// Items a Read Var request may carry (the S7-300/400 limit; the count is a
/// byte).
pub const MAX_ITEMS: usize = 20;

/// A malformed frame.
#[derive(Debug, Clone, PartialEq)]
pub struct ProtoError(pub String);

impl fmt::Display for ProtoError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

fn perr(m: impl Into<String>) -> ProtoError {
    ProtoError(m.into())
}

fn u16_at(b: &[u8], i: usize) -> Result<u16, ProtoError> {
    b.get(i..i + 2)
        .map(|s| u16::from_be_bytes([s[0], s[1]]))
        .ok_or_else(|| perr("frame too short"))
}

/// Wrap `payload` (COTP + S7) in a TPKT header.
pub fn tpkt(payload: &[u8]) -> Vec<u8> {
    let len = (payload.len() + 4) as u16;
    let mut out = Vec::with_capacity(payload.len() + 4);
    out.extend_from_slice(&[TPKT_VERSION, 0]);
    out.extend_from_slice(&len.to_be_bytes());
    out.extend_from_slice(payload);
    out
}

/// The length of the first whole TPKT frame in `buf`: `Ok(None)` while it
/// is incomplete.
pub fn tpkt_len(buf: &[u8]) -> Result<Option<usize>, ProtoError> {
    if buf.len() < 4 {
        return Ok(None);
    }
    if buf[0] != TPKT_VERSION {
        return Err(perr(format!("not a TPKT frame (version {})", buf[0])));
    }
    let len = usize::from(u16::from_be_bytes([buf[2], buf[3]]));
    if len < 7 {
        return Err(perr(format!("TPKT length {len} is too short")));
    }
    Ok((buf.len() >= len).then_some(len))
}

/// The remote TSAP of a CPU: connection type in the high byte, `rack * 32 +
/// slot` in the low byte.
pub fn remote_tsap(conn_type: u8, rack: u8, slot: u8) -> u16 {
    (u16::from(conn_type) << 8) | (u16::from(rack) * 32 + u16::from(slot))
}

/// The local TSAP this link uses (as most S7 clients do).
pub const LOCAL_TSAP: u16 = 0x0100;

/// TPDU size code 0x0A: 1024 bytes.
pub const TPDU_SIZE_CODE: u8 = 0x0A;

/// COTP Connection Request with TPDU size and both TSAPs, in a TPKT.
pub fn cotp_cr(local_tsap: u16, remote_tsap: u16) -> Vec<u8> {
    let [lh, ll] = local_tsap.to_be_bytes();
    let [rh, rl] = remote_tsap.to_be_bytes();
    tpkt(&[
        17,
        COTP_CR,
        0x00,
        0x00, // destination reference
        0x00,
        0x01, // source reference
        0x00, // class 0
        0xC0,
        1,
        TPDU_SIZE_CODE,
        0xC1,
        2,
        lh,
        ll,
        0xC2,
        2,
        rh,
        rl,
    ])
}

/// A COTP TPDU of one TPKT frame.
#[derive(Debug, Clone, PartialEq)]
pub enum Cotp<'a> {
    /// Connection confirm.
    Cc,
    /// Disconnect request (the PLC refused or closed the connection).
    Dr { reason: u8 },
    /// Data: `last` = end of the TSDU.
    Dt { last: bool, data: &'a [u8] },
    /// Another TPDU code.
    Other(u8),
}

/// The COTP TPDU of a whole TPKT frame.
pub fn cotp(frame: &[u8]) -> Result<Cotp<'_>, ProtoError> {
    let li = usize::from(*frame.get(4).ok_or_else(|| perr("no COTP header"))?);
    let code = *frame.get(5).ok_or_else(|| perr("no COTP header"))?;
    if frame.len() < 5 + li {
        return Err(perr("COTP header runs past the frame"));
    }
    Ok(match code & 0xF0 {
        COTP_CC => Cotp::Cc,
        COTP_DR => Cotp::Dr {
            reason: frame.get(10).copied().unwrap_or(0),
        },
        COTP_DT => {
            let nr = *frame.get(6).ok_or_else(|| perr("short COTP DT"))?;
            let data = frame
                .get(5 + li..)
                .ok_or_else(|| perr("COTP DT runs past the frame"))?;
            Cotp::Dt {
                last: nr & COTP_EOT != 0,
                data,
            }
        }
        c => Cotp::Other(c),
    })
}

/// One S7 PDU in a COTP DT TPDU, in a TPKT.
pub fn dt(s7: &[u8]) -> Vec<u8> {
    let mut p = Vec::with_capacity(s7.len() + 3);
    p.extend_from_slice(&[2, COTP_DT, COTP_EOT]);
    p.extend_from_slice(s7);
    tpkt(&p)
}

/// S7 job header (10 bytes) + params + data.
fn job(pdu_ref: u16, params: &[u8], data: &[u8]) -> Vec<u8> {
    s7_pdu(ROSCTR_JOB, pdu_ref, params, data)
}

fn s7_pdu(rosctr: u8, pdu_ref: u16, params: &[u8], data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(10 + params.len() + data.len());
    out.extend_from_slice(&[S7_ID, rosctr, 0, 0]);
    out.extend_from_slice(&pdu_ref.to_be_bytes());
    out.extend_from_slice(&(params.len() as u16).to_be_bytes());
    out.extend_from_slice(&(data.len() as u16).to_be_bytes());
    out.extend_from_slice(params);
    out.extend_from_slice(data);
    out
}

/// Setup Communication: one parallel job each way, PDU size `pdu`.
pub fn setup(pdu_ref: u16, pdu: u16) -> Vec<u8> {
    let [ph, pl] = pdu.to_be_bytes();
    job(pdu_ref, &[FN_SETUP, 0, 0, 1, 0, 1, ph, pl], &[])
}

/// A Read/Write Var item: where and how much.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Item {
    pub area: Area,
    pub db: u16,
    /// Byte offset, or the timer/counter number.
    pub start: u32,
    /// Bit of a [`TS_BIT`] item.
    pub bit: u8,
    /// Bytes, or timers/counters; 1 for a bit.
    pub count: u16,
    /// [`TS_BIT`], [`TS_BYTE`], [`TS_TIMER`] or [`TS_COUNTER`].
    pub ts: u8,
}

impl Item {
    /// Bytes of `count` units from `start` of `area`.
    pub fn bytes(area: Area, db: u16, start: u32, count: u16) -> Item {
        let ts = match area {
            Area::Timer => TS_TIMER,
            Area::Counter => TS_COUNTER,
            _ => TS_BYTE,
        };
        Item {
            area,
            db,
            start,
            bit: 0,
            count,
            ts,
        }
    }

    /// One bit.
    pub fn bit(area: Area, db: u16, start: u32, bit: u8) -> Item {
        Item {
            area,
            db,
            start,
            bit,
            count: 1,
            ts: TS_BIT,
        }
    }

    /// The 12-byte S7ANY item specification.
    pub fn spec(&self) -> [u8; 12] {
        // timers and counters are addressed by number; the rest by bit
        let addr = if self.area.is_tc() {
            self.start
        } else {
            (self.start << 3) | u32::from(self.bit & 7)
        };
        let [ch, cl] = self.count.to_be_bytes();
        let [dh, dl] = self.db.to_be_bytes();
        let [_, a2, a1, a0] = addr.to_be_bytes();
        [
            0x12,
            0x0A,
            0x10,
            self.ts,
            ch,
            cl,
            dh,
            dl,
            self.area.code(),
            a2,
            a1,
            a0,
        ]
    }

    /// Bytes this item reads.
    pub fn reply_bytes(&self) -> usize {
        match self.ts {
            TS_BIT => 1,
            _ => usize::from(self.count) * self.area.unit_bytes() as usize,
        }
    }
}

/// Read Var of `items`: at most [`MAX_ITEMS`] (the caller checks; a count
/// that does not fit the count byte takes the first 255, so the count
/// and the items always agree).
pub fn read_var(pdu_ref: u16, items: &[Item]) -> Vec<u8> {
    debug_assert!(items.len() <= MAX_ITEMS, "{} items", items.len());
    let n = u8::try_from(items.len()).unwrap_or(u8::MAX);
    let items = &items[..usize::from(n)];
    let mut p = Vec::with_capacity(2 + ITEM_SPEC * items.len());
    p.extend_from_slice(&[FN_READ, n]);
    for i in items {
        p.extend_from_slice(&i.spec());
    }
    job(pdu_ref, &p, &[])
}

/// The bytes a Read Var request of `n` items takes.
pub fn read_req_len(n: usize) -> usize {
    READ_REQ_FIXED + ITEM_SPEC * n
}

/// The most bytes a reply item of `len` bytes takes (fill byte included).
pub fn reply_item_len(len: usize) -> usize {
    ITEM_DATA_HDR + len + (len & 1)
}

/// Write Var of one item with `data` (a bit: one byte, 0 or 1).
pub fn write_var(pdu_ref: u16, item: &Item, data: &[u8]) -> Vec<u8> {
    let mut p = Vec::with_capacity(14);
    p.extend_from_slice(&[FN_WRITE, 1]);
    p.extend_from_slice(&item.spec());
    let (dts, len) = match item.ts {
        TS_BIT => (DTS_BIT, data.len() as u16),
        TS_TIMER | TS_COUNTER => (DTS_OCTET, data.len() as u16),
        _ => (DTS_BYTE, (data.len() * 8) as u16),
    };
    let mut d = Vec::with_capacity(4 + data.len());
    d.extend_from_slice(&[0x00, dts]);
    d.extend_from_slice(&len.to_be_bytes());
    d.extend_from_slice(data);
    job(pdu_ref, &p, &d)
}

/// Userdata request: read SZL `id`/`index` (CPU functions, first part).
pub fn read_szl(pdu_ref: u16, id: u16, index: u16) -> Vec<u8> {
    let [ih, il] = id.to_be_bytes();
    let [xh, xl] = index.to_be_bytes();
    s7_pdu(
        ROSCTR_USERDATA,
        pdu_ref,
        // head, length 4, request, type 4 (request) | group 4 (CPU), read SZL, seq 0
        &[0x00, 0x01, 0x12, 0x04, 0x11, 0x44, 0x01, 0x00],
        &[RC_OK, DTS_OCTET, 0x00, 0x04, ih, il, xh, xl],
    )
}

/// A parsed S7 reply PDU.
#[derive(Debug, Clone, PartialEq)]
pub struct S7Reply<'a> {
    pub rosctr: u8,
    pub pdu_ref: u16,
    /// `class << 8 | code` of an ack/ack-data header; 0 = no error.
    pub error: u16,
    pub params: &'a [u8],
    pub data: &'a [u8],
}

/// Parse an S7 PDU (the payload of COTP DT).
pub fn s7_reply(b: &[u8]) -> Result<S7Reply<'_>, ProtoError> {
    if b.first() != Some(&S7_ID) {
        return Err(perr("not an S7 PDU"));
    }
    let rosctr = *b.get(1).ok_or_else(|| perr("short S7 header"))?;
    let pdu_ref = u16_at(b, 4)?;
    let plen = usize::from(u16_at(b, 6)?);
    let dlen = usize::from(u16_at(b, 8)?);
    let (hdr, error) = match rosctr {
        ROSCTR_ACK | ROSCTR_ACK_DATA => (12, u16_at(b, 10)?),
        ROSCTR_JOB | ROSCTR_USERDATA => (10, 0),
        r => return Err(perr(format!("unknown S7 PDU type {r}"))),
    };
    let params = b
        .get(hdr..hdr + plen)
        .ok_or_else(|| perr("S7 parameters run past the PDU"))?;
    let data = b
        .get(hdr + plen..hdr + plen + dlen)
        .ok_or_else(|| perr("S7 data runs past the PDU"))?;
    Ok(S7Reply {
        rosctr,
        pdu_ref,
        error,
        params,
        data,
    })
}

/// What Setup Communication agreed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Setup {
    pub amq_calling: u16,
    pub amq_called: u16,
    pub pdu: u16,
}

pub fn setup_reply(r: &S7Reply<'_>) -> Result<Setup, ProtoError> {
    if r.params.first() != Some(&FN_SETUP) || r.params.len() < 8 {
        return Err(perr("not a Setup Communication reply"));
    }
    Ok(Setup {
        amq_calling: u16_at(r.params, 2)?,
        amq_called: u16_at(r.params, 4)?,
        pdu: u16_at(r.params, 6)?,
    })
}

/// One item of a Read Var reply: its data, or the PLC's return code.
pub type ItemResult<'a> = Result<&'a [u8], u8>;

/// The items of a Read Var reply (`n` expected).
pub fn read_reply<'a>(r: &S7Reply<'a>, n: usize) -> Result<Vec<ItemResult<'a>>, ProtoError> {
    if r.params.first() != Some(&FN_READ) {
        return Err(perr("not a Read Var reply"));
    }
    let count = usize::from(
        *r.params
            .get(1)
            .ok_or_else(|| perr("short Read Var reply"))?,
    );
    if count != n {
        return Err(perr(format!("Read Var reply has {count} items, {n} asked")));
    }
    let d = r.data;
    let mut out = Vec::with_capacity(n);
    let mut i = 0;
    for k in 0..n {
        let hdr = d
            .get(i..i + ITEM_DATA_HDR)
            .ok_or_else(|| perr("Read Var reply item runs past the data"))?;
        let (rc, dts) = (hdr[0], hdr[1]);
        let len = usize::from(u16::from_be_bytes([hdr[2], hdr[3]]));
        let bytes = match dts {
            DTS_BIT | DTS_BYTE | DTS_INT => len.div_ceil(8),
            _ => len,
        };
        i += ITEM_DATA_HDR;
        if rc != RC_OK {
            // an error item carries no data (its length is 0)
            out.push(Err(rc));
            i += bytes;
        } else {
            let v = d
                .get(i..i + bytes)
                .ok_or_else(|| perr("Read Var reply data runs past the PDU"))?;
            out.push(Ok(v));
            i += bytes;
        }
        // a fill byte after an odd length, except after the last item
        if bytes & 1 == 1 && k + 1 < n {
            i += 1;
        }
    }
    Ok(out)
}

/// The return code of a one-item Write Var reply.
pub fn write_reply(r: &S7Reply<'_>) -> Result<u8, ProtoError> {
    if r.params.first() != Some(&FN_WRITE) {
        return Err(perr("not a Write Var reply"));
    }
    r.data
        .first()
        .copied()
        .ok_or_else(|| perr("Write Var reply without a return code"))
}

/// A userdata SZL reply: the error code of its params (0 = none), and the
/// SZL part.
#[derive(Debug, Clone, PartialEq)]
pub struct Szl {
    pub error: u16,
    /// More parts follow (not read by this link).
    pub more: bool,
    pub id: u16,
    pub index: u16,
    pub record_len: u16,
    pub records: Vec<Vec<u8>>,
}

pub fn szl_reply(r: &S7Reply<'_>) -> Result<Szl, ProtoError> {
    if r.rosctr != ROSCTR_USERDATA {
        return Err(perr("not a userdata reply"));
    }
    let p = r.params;
    // head (3), length, method, type|group, subfunction, seq, dur, last du, error
    if p.len() < 12 {
        return Err(perr("short userdata parameters"));
    }
    let more = p[9] != 0;
    let error = u16_at(p, 10)?;
    let d = r.data;
    if error != 0 || d.first() != Some(&RC_OK) {
        return Ok(Szl {
            error: if error != 0 {
                error
            } else {
                u16::from(*d.first().unwrap_or(&0))
            },
            more,
            id: 0,
            index: 0,
            record_len: 0,
            records: Vec::new(),
        });
    }
    let id = u16_at(d, 4)?;
    let index = u16_at(d, 6)?;
    let record_len = u16_at(d, 8)?;
    let count = u16_at(d, 10)?;
    let mut records = Vec::new();
    let rl = usize::from(record_len);
    if rl > 0 {
        for k in 0..usize::from(count) {
            let at = 12 + k * rl;
            match d.get(at..at + rl) {
                Some(rec) => records.push(rec.to_vec()),
                None => break,
            }
        }
    }
    Ok(Szl {
        error,
        more,
        id,
        index,
        record_len,
        records,
    })
}

/// Text of an S7 header error (`class << 8 | code`).
pub fn error_text(e: u16) -> String {
    let text = match e {
        0x0000 => "no error",
        0x0110 => "invalid block number",
        0x0111 => "invalid request length",
        0x0112 => "invalid parameter",
        0x0113 => "invalid block type",
        0x0114 => "block not found",
        0x011C => "protocol error",
        0x0140 => "insufficient memory available",
        0x0141 => "the job cannot be processed for a lack of resources",
        0x8001 => "the service cannot be performed while the block is in its current state",
        0x8003 => "S7 protocol error while transferring the block",
        0x8100 => "service unknown to the module",
        0x8104 => {
            "this service is not implemented on the module or a frame error was reported \
             (S7-1200/1500: enable \"Permit access with PUT/GET communication\" in the CPU's \
             protection settings)"
        }
        0x8204 => "the type specification for the object is inconsistent",
        0x8301 => "insufficient memory on the module",
        0x8302 => "too few resources available",
        0x8304 => "no further parallel jobs possible (resource bottleneck)",
        0x8305 => "function not available",
        0x8401 => "S7 protocol error: invalid service sequence",
        0x8402 => "the service cannot run in the state of the addressed object",
        0x8404 => "S7 protocol: the function cannot be performed",
        0x8500 => "S7 protocol error: wrong frames (a request or reply too long for the PDU)",
        0x8503 => "the module cancelled the service",
        0x8701 => "error addressing the object (for example an area length error)",
        0x8702 => "the requested service is not supported by the module",
        0x8703 => "access to the object refused",
        0x8704 => "access error: the object is damaged",
        0xD401 => "information function unavailable (SZL ID not available)",
        0xD402 => "SZL index not available",
        _ => "unknown error",
    };
    format!("PLC error 0x{e:04X}: {text}")
}

/// Text of a Read/Write Var item return code.
pub fn item_text(rc: u8) -> String {
    let text = match rc {
        0x01 => "hardware fault",
        0x03 => {
            "access to the object not allowed (S7-1200/1500: enable PUT/GET access and turn off \
             \"Optimized block access\" for the DB)"
        }
        0x05 => {
            "address out of range (the area or DB is shorter; S7-1200/1500: is the DB optimized?)"
        }
        0x06 => "data type not supported",
        0x07 => "data type inconsistent",
        0x0A => "object does not exist (no such DB?)",
        _ => "unknown return code",
    };
    format!("PLC item error 0x{rc:02X}: {text}")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Golden frames as S7 clients send them and as Wireshark's s7comm
    /// dissector shows them (constants only; no code copied).
    #[test]
    fn cotp_connection_request_bytes() {
        // rack 0 slot 2, PG: remote TSAP 0x0102
        assert_eq!(remote_tsap(1, 0, 2), 0x0102);
        assert_eq!(remote_tsap(3, 1, 3), 0x0323);
        assert_eq!(
            cotp_cr(LOCAL_TSAP, 0x0102),
            [
                0x03, 0x00, 0x00, 0x16, 0x11, 0xE0, 0x00, 0x00, 0x00, 0x01, 0x00, 0xC0, 0x01, 0x0A,
                0xC1, 0x02, 0x01, 0x00, 0xC2, 0x02, 0x01, 0x02
            ]
        );
        let cc = [
            0x03, 0x00, 0x00, 0x16, 0x11, 0xD0, 0x00, 0x01, 0x00, 0x01, 0x00, 0xC0, 0x01, 0x0A,
            0xC1, 0x02, 0x01, 0x00, 0xC2, 0x02, 0x01, 0x02,
        ];
        assert_eq!(tpkt_len(&cc), Ok(Some(22)));
        assert_eq!(tpkt_len(&cc[..10]), Ok(None));
        assert_eq!(cotp(&cc), Ok(Cotp::Cc));
        assert!(tpkt_len(&[0x04, 0, 0, 22]).is_err());
    }

    #[test]
    fn setup_communication_bytes() {
        assert_eq!(
            dt(&setup(0x0400, 480)),
            [
                0x03, 0x00, 0x00, 0x19, 0x02, 0xF0, 0x80, 0x32, 0x01, 0x00, 0x00, 0x04, 0x00, 0x00,
                0x08, 0x00, 0x00, 0xF0, 0x00, 0x00, 0x01, 0x00, 0x01, 0x01, 0xE0
            ]
        );
        let reply = [
            0x03, 0x00, 0x00, 0x1B, 0x02, 0xF0, 0x80, 0x32, 0x03, 0x00, 0x00, 0x04, 0x00, 0x00,
            0x08, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0xF0,
        ];
        let Cotp::Dt { last: true, data } = cotp(&reply).unwrap() else {
            panic!("not DT")
        };
        let r = s7_reply(data).unwrap();
        assert_eq!((r.rosctr, r.pdu_ref, r.error), (ROSCTR_ACK_DATA, 0x0400, 0));
        assert_eq!(
            setup_reply(&r),
            Ok(Setup {
                amq_calling: 1,
                amq_called: 1,
                pdu: 240
            })
        );
    }

    #[test]
    fn read_var_two_items_bytes() {
        let items = [
            Item::bytes(Area::Db, 1, 0, 4),
            Item::bytes(Area::Marker, 0, 10, 1),
        ];
        assert_eq!(
            read_var(0x0005, &items),
            [
                0x32, 0x01, 0x00, 0x00, 0x00, 0x05, 0x00, 0x1A, 0x00, 0x00, // header
                0x04, 0x02, // read, 2 items
                0x12, 0x0A, 0x10, 0x02, 0x00, 0x04, 0x00, 0x01, 0x84, 0x00, 0x00,
                0x00, // DB1.DBB0 ×4
                0x12, 0x0A, 0x10, 0x02, 0x00, 0x01, 0x00, 0x00, 0x83, 0x00, 0x00,
                0x50, // MB10
            ]
        );
        assert_eq!(read_var(5, &items).len(), read_req_len(2));
        // reply: first item 1 byte (odd: fill byte), second an error
        let rep = [
            0x32, 0x03, 0x00, 0x00, 0x00, 0x05, 0x00, 0x02, 0x00, 0x0A, 0x00, 0x00, // header
            0x04, 0x02, // read, 2 items
            0xFF, 0x04, 0x00, 0x08, 0xAB, 0x00, // 8 bits, fill
            0x0A, 0x00, 0x00, 0x00, // object does not exist
        ];
        let r = s7_reply(&rep).unwrap();
        assert_eq!(read_reply(&r, 2), Ok(vec![Ok(&[0xAB][..]), Err(0x0A)]));
        assert!(read_reply(&r, 3).is_err());
        // timers: addressed by number, octet string reply
        let t = Item::bytes(Area::Timer, 0, 5, 2);
        assert_eq!(
            t.spec(),
            [0x12, 0x0A, 0x10, 0x1D, 0x00, 0x02, 0x00, 0x00, 0x1D, 0x00, 0x00, 0x05]
        );
        assert_eq!(t.reply_bytes(), 4);
        // a byte offset far out: 24 bits of byte << 3
        assert_eq!(
            Item::bytes(Area::Db, 1, 0x1F_FFFF, 1).spec()[9..],
            [0xFF, 0xFF, 0xF8]
        );
    }

    #[test]
    fn write_var_bit_bytes() {
        // DB1.DBX4.3 := true
        assert_eq!(
            write_var(0x0007, &Item::bit(Area::Db, 1, 4, 3), &[1]),
            [
                0x32, 0x01, 0x00, 0x00, 0x00, 0x07, 0x00, 0x0E, 0x00, 0x05, // header
                0x05, 0x01, // write, 1 item
                0x12, 0x0A, 0x10, 0x01, 0x00, 0x01, 0x00, 0x01, 0x84, 0x00, 0x00, 0x23, // bit
                0x00, 0x03, 0x00, 0x01, 0x01, // BIT, 1 bit, value
            ]
        );
        // MW20 := 0x1234: BYTE item of 2, data length in bits
        let w = write_var(1, &Item::bytes(Area::Marker, 0, 20, 2), &[0x12, 0x34]);
        assert_eq!(&w[24..], &[0x00, 0x04, 0x00, 0x10, 0x12, 0x34]);
        assert_eq!(w.len(), WRITE_FIXED + 2);
        let rep = [
            0x32, 0x03, 0x00, 0x00, 0x00, 0x07, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00, 0x05, 0x01,
            0xFF,
        ];
        assert_eq!(write_reply(&s7_reply(&rep).unwrap()), Ok(RC_OK));
    }

    #[test]
    fn szl_bytes_and_errors() {
        assert_eq!(
            read_szl(0x0100, 0x0011, 0),
            [
                0x32, 0x07, 0x00, 0x00, 0x01, 0x00, 0x00, 0x08, 0x00, 0x08, 0x00, 0x01, 0x12, 0x04,
                0x11, 0x44, 0x01, 0x00, 0xFF, 0x09, 0x00, 0x04, 0x00, 0x11, 0x00, 0x00
            ]
        );
        let mut rep = vec![0x32, 0x07, 0, 0, 0x01, 0x00, 0x00, 0x0C, 0x00, 0x0E];
        rep.extend_from_slice(&[0x00, 0x01, 0x12, 0x08, 0x12, 0x84, 0x01, 0x01, 0, 0, 0, 0]);
        rep.extend_from_slice(&[0xFF, 0x09, 0x00, 0x0C, 0x00, 0x11, 0x00, 0x00, 0x00, 0x02]);
        rep.extend_from_slice(&[0x00, 0x01, 0xAA, 0xBB]);
        let s = szl_reply(&s7_reply(&rep).unwrap()).unwrap();
        assert_eq!((s.error, s.id, s.record_len), (0, 0x11, 2));
        assert_eq!(s.records, vec![vec![0xAA, 0xBB]]);
        let mut err = vec![0x32, 0x07, 0, 0, 0x01, 0x00, 0x00, 0x0C, 0x00, 0x04];
        err.extend_from_slice(&[
            0x00, 0x01, 0x12, 0x08, 0x12, 0x84, 0x01, 0x01, 0, 0, 0xD4, 0x01,
        ]);
        err.extend_from_slice(&[0x0A, 0x00, 0x00, 0x00]);
        assert_eq!(szl_reply(&s7_reply(&err).unwrap()).unwrap().error, 0xD401);
    }

    #[test]
    fn error_texts_name_the_code() {
        assert!(error_text(0x8104).contains("PUT/GET"));
        assert!(error_text(0x8104).starts_with("PLC error 0x8104"));
        assert!(item_text(0x05).contains("out of range"));
        assert!(item_text(0x03).contains("Optimized"));
        assert!(error_text(0x1234).contains("unknown"));
    }

    #[test]
    fn fragments_and_disconnects() {
        let frag = tpkt(&[2, COTP_DT, 0x00, 0x32]);
        assert_eq!(
            cotp(&frag),
            Ok(Cotp::Dt {
                last: false,
                data: &[0x32]
            })
        );
        let dr = tpkt(&[6, COTP_DR, 0, 0, 0, 1, 0x80]);
        assert!(matches!(cotp(&dr), Ok(Cotp::Dr { .. })));
        assert!(s7_reply(&[0x33, 1]).is_err());
        assert!(s7_reply(&[0x32, 3, 0, 0, 0, 1, 0, 9, 0, 0, 0, 0]).is_err());
    }
}
