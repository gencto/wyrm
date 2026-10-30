//! S7 PLC simulator (feature `sim`): an ISO-on-TCP server that answers the
//! COTP connection request, Setup Communication, Read Var, Write Var and
//! the SZL read over a byte image per area (DBs, M, I, Q) and the timer and
//! counter words. It parses requests by their byte offsets on its own (not
//! with [`crate::proto`]'s parsers), so a symmetric codec bug does not
//! pass unseen.
//!
//! Faults for tests: an address out of range → item return code 0x05 (a
//! missing DB 0x0A); a small offered PDU to force splitting (a request or
//! reply that would not fit is answered with header error 0x8500 and
//! counted in `oversize`); silence; one late reply; closing the connection
//! on the next request; PUT/GET refused (header error 0x8104); no SZL
//! (userdata error 0xD401).

use std::collections::{BTreeMap, VecDeque};
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::{AbortHandle, JoinHandle};

/// Bytes of the M, I and Q images.
pub const AREA_SIZE: usize = 1024;
/// Timers and counters.
pub const TC_COUNT: usize = 256;

/// One request item the simulator served.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LogItem {
    pub area: u8,
    pub db: u16,
    /// Byte offset (bit offset >> 3), or the timer/counter number.
    pub start: u32,
    pub bit: u8,
    pub count: u16,
    /// Transport size of the request item.
    pub ts: u8,
}

/// One S7 job the simulator received.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Job {
    /// 0x04 read, 0x05 write, 0xF0 setup, 0x00 userdata.
    pub function: u8,
    pub items: Vec<LogItem>,
    /// Bytes of the S7 PDU (header included).
    pub len: usize,
}

#[derive(Debug)]
pub struct Plc {
    /// Data blocks by number.
    pub dbs: BTreeMap<u16, Vec<u8>>,
    pub inputs: Vec<u8>,
    pub outputs: Vec<u8>,
    pub markers: Vec<u8>,
    pub timers: Vec<u16>,
    pub counters: Vec<u16>,
    /// The largest PDU the simulator agrees on.
    pub pdu_size: u16,
    /// Items per Read Var it accepts.
    pub max_items: usize,
    /// Do not answer anything.
    pub silent: bool,
    /// Delay before every reply.
    pub latency: Duration,
    /// Answer the next job that much later (once).
    pub delay_once: Option<Duration>,
    /// … and only a job that reads or writes this byte of DB1 (`None`: any).
    pub delay_at: Option<u32>,
    /// Close the connection at the next job.
    pub close_next: bool,
    /// Answer Read/Write Var with header error 0x8104 (S7-1200/1500
    /// without PUT/GET access).
    pub deny_put_get: bool,
    /// Answer SZL reads with userdata error 0xD401.
    pub no_szl: bool,
    /// Jobs received, the last [`LOG_MAX`].
    pub log: VecDeque<Job>,
    /// Remote TSAPs of the connection requests.
    pub tsaps: Vec<u16>,
    pub connections: u64,
    /// Requests or replies that would not fit the PDU (answered 0x8500).
    pub oversize: u64,
    /// The PDU agreed on the last connection.
    pub agreed_pdu: u16,
}

pub const LOG_MAX: usize = 10_000;

impl Default for Plc {
    fn default() -> Self {
        Self {
            dbs: BTreeMap::from([(1, vec![0; 1000]), (2, vec![0; 100])]),
            inputs: vec![0; AREA_SIZE],
            outputs: vec![0; AREA_SIZE],
            markers: vec![0; AREA_SIZE],
            timers: vec![0; TC_COUNT],
            counters: vec![0; TC_COUNT],
            pdu_size: 480,
            max_items: 20,
            silent: false,
            latency: Duration::ZERO,
            delay_once: None,
            delay_at: None,
            close_next: false,
            deny_put_get: false,
            no_szl: false,
            log: VecDeque::new(),
            tsaps: Vec::new(),
            connections: 0,
            oversize: 0,
            agreed_pdu: 0,
        }
    }
}

impl Plc {
    /// DB `n` (created at `size` bytes if missing).
    pub fn db(&mut self, n: u16, size: usize) -> &mut Vec<u8> {
        self.dbs.entry(n).or_insert_with(|| vec![0; size])
    }

    /// Read Var jobs received.
    pub fn reads(&self) -> Vec<&Job> {
        self.log.iter().filter(|j| j.function == 0x04).collect()
    }

    /// Write Var jobs received.
    pub fn writes(&self) -> Vec<&Job> {
        self.log.iter().filter(|j| j.function == 0x05).collect()
    }
}

pub type Device = Arc<Mutex<Plc>>;

fn plc(d: &Device) -> std::sync::MutexGuard<'_, Plc> {
    d.lock().unwrap_or_else(|p| p.into_inner())
}

/// The running simulator: its listener and connections. Dropping it (or
/// [`Sim::stop`]) closes them all.
pub struct Sim {
    listener: JoinHandle<()>,
    conns: Arc<Mutex<Vec<AbortHandle>>>,
}

impl Sim {
    /// Stop listening and close every connection (the PLC goes away).
    pub fn stop(&self) {
        self.listener.abort();
        for c in self
            .conns
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .drain(..)
        {
            c.abort();
        }
    }
}

impl Drop for Sim {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Listen on `addr` (`127.0.0.1:0` for a free port) with a new PLC image.
pub async fn spawn(addr: &str) -> std::io::Result<(SocketAddr, Device, Sim)> {
    let device = Device::default();
    let (a, s) = spawn_with(addr, device.clone()).await?;
    Ok((a, device, s))
}

/// Listen on `addr` serving `device` (to bring a stopped PLC back).
pub async fn spawn_with(addr: &str, device: Device) -> std::io::Result<(SocketAddr, Sim)> {
    let listener = TcpListener::bind(addr).await?;
    let local = listener.local_addr()?;
    let conns: Arc<Mutex<Vec<AbortHandle>>> = Arc::default();
    let cs = conns.clone();
    let task = tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let _ = stream.set_nodelay(true);
            plc(&device).connections += 1;
            let h = tokio::spawn(serve(stream, device.clone()));
            let mut cs = cs.lock().unwrap_or_else(|p| p.into_inner());
            cs.retain(|h| !h.is_finished());
            cs.push(h.abort_handle());
        }
    });
    Ok((
        local,
        Sim {
            listener: task,
            conns,
        },
    ))
}

fn be16(b: &[u8], i: usize) -> Option<u16> {
    Some(u16::from_be_bytes([*b.get(i)?, *b.get(i + 1)?]))
}

async fn read_tpkt(s: &mut TcpStream) -> Option<Vec<u8>> {
    let mut hdr = [0u8; 4];
    s.read_exact(&mut hdr).await.ok()?;
    if hdr[0] != 3 {
        return None;
    }
    let len = usize::from(u16::from_be_bytes([hdr[2], hdr[3]]));
    let mut rest = vec![0u8; len.checked_sub(4)?];
    s.read_exact(&mut rest).await.ok()?;
    Some(rest)
}

fn tpkt(payload: &[u8]) -> Vec<u8> {
    let mut out = vec![3, 0];
    out.extend_from_slice(&((payload.len() + 4) as u16).to_be_bytes());
    out.extend_from_slice(payload);
    out
}

fn dt(s7: &[u8]) -> Vec<u8> {
    let mut p = vec![2, 0xF0, 0x80];
    p.extend_from_slice(s7);
    tpkt(&p)
}

async fn serve(mut s: TcpStream, dev: Device) {
    // COTP connection request → confirm
    let Some(cr) = read_tpkt(&mut s).await else {
        return;
    };
    if cr.get(1) != Some(&0xE0) {
        return;
    }
    let mut tsap = 0;
    let mut i = 7;
    while i + 1 < cr.len() {
        let (code, len) = (cr[i], usize::from(cr[i + 1]));
        if code == 0xC2 && len == 2 {
            tsap = be16(&cr, i + 2).unwrap_or(0);
        }
        i += 2 + len;
    }
    plc(&dev).tsaps.push(tsap);
    let mut cc = cr.clone();
    cc[1] = 0xD0;
    cc[2..4].copy_from_slice(&[0x00, 0x01]);
    if s.write_all(&tpkt(&cc)).await.is_err() {
        return;
    }
    let mut pdu = 240u16;
    loop {
        let Some(frame) = read_tpkt(&mut s).await else {
            return;
        };
        // COTP DT: length byte, 0xF0, EOT|nr
        if frame.get(1) != Some(&0xF0) {
            return;
        }
        let req = &frame[usize::from(frame[0]) + 1..];
        let (reply, delay, close) = {
            let mut p = plc(&dev);
            let job = log_job(req);
            if p.log.len() == LOG_MAX {
                p.log.pop_front();
            }
            let touches = |at: u32| {
                job.items.iter().any(|it| {
                    it.area == 0x84
                        && it.db == 1
                        && it.start <= at
                        && at < it.start + u32::from(it.count).max(1)
                })
            };
            let mut delay = p.latency;
            if let Some(d) = p.delay_once {
                if p.delay_at.is_none_or(touches) && job.function != 0xF0 {
                    p.delay_once = None;
                    delay += d;
                }
            }
            p.log.push_back(job);
            if p.close_next {
                p.close_next = false;
                (None, delay, true)
            } else if p.silent {
                (None, delay, false)
            } else {
                (answer(&mut p, req, &mut pdu), delay, false)
            }
        };
        if close {
            return;
        }
        let Some(reply) = reply else {
            continue;
        };
        if !delay.is_zero() {
            tokio::time::sleep(delay).await;
        }
        if s.write_all(&dt(&reply)).await.is_err() {
            return;
        }
    }
}

fn log_job(req: &[u8]) -> Job {
    let mut job = Job {
        function: 0,
        items: Vec::new(),
        len: req.len(),
    };
    if req.get(1) == Some(&7) {
        return job;
    }
    let p = req.get(10..).unwrap_or(&[]);
    job.function = p.first().copied().unwrap_or(0);
    if matches!(job.function, 0x04 | 0x05) {
        let n = usize::from(p.get(1).copied().unwrap_or(0));
        for k in 0..n {
            let Some(it) = p.get(2 + 12 * k..2 + 12 * k + 12) else {
                break;
            };
            let addr = (u32::from(it[9]) << 16) | (u32::from(it[10]) << 8) | u32::from(it[11]);
            let tc = matches!(it[8], 0x1C | 0x1D);
            job.items.push(LogItem {
                area: it[8],
                db: u16::from_be_bytes([it[6], it[7]]),
                start: if tc { addr } else { addr >> 3 },
                bit: if tc { 0 } else { (addr & 7) as u8 },
                count: u16::from_be_bytes([it[4], it[5]]),
                ts: it[3],
            });
        }
    }
    job
}

/// An ack-data PDU.
fn ack_data(pdu_ref: [u8; 2], err: u16, params: &[u8], data: &[u8]) -> Vec<u8> {
    let mut out = vec![0x32, 3, 0, 0, pdu_ref[0], pdu_ref[1]];
    out.extend_from_slice(&(params.len() as u16).to_be_bytes());
    out.extend_from_slice(&(data.len() as u16).to_be_bytes());
    out.extend_from_slice(&err.to_be_bytes());
    out.extend_from_slice(params);
    out.extend_from_slice(data);
    out
}

fn answer(p: &mut Plc, req: &[u8], pdu: &mut u16) -> Option<Vec<u8>> {
    if req.first() != Some(&0x32) {
        return None;
    }
    let pref = [*req.get(4)?, *req.get(5)?];
    if req[1] == 7 {
        return Some(szl(p, req, pref));
    }
    let params = req.get(10..10 + usize::from(be16(req, 6)?))?;
    let data = req.get(10 + params.len()..)?;
    match params.first()? {
        0xF0 => {
            let asked = be16(params, 6)?;
            *pdu = asked.min(p.pdu_size);
            p.agreed_pdu = *pdu;
            let [h, l] = pdu.to_be_bytes();
            Some(ack_data(pref, 0, &[0xF0, 0, 0, 1, 0, 1, h, l], &[]))
        }
        f @ (0x04 | 0x05) => {
            let n = usize::from(*params.get(1)?);
            if req.len() > usize::from(*pdu) || n > p.max_items || n == 0 {
                p.oversize += 1;
                return Some(ack_data(pref, 0x8500, &[], &[]));
            }
            if p.deny_put_get {
                return Some(ack_data(pref, 0x8104, &[], &[]));
            }
            let items: Vec<&[u8]> = (0..n)
                .map(|k| params.get(2 + 12 * k..14 + 12 * k))
                .collect::<Option<_>>()?;
            let reply = if *f == 0x04 {
                read_var(p, &items)
            } else {
                write_var(p, &items, data)?
            };
            let r = ack_data(pref, 0, &[*f, n as u8], &reply);
            if r.len() > usize::from(*pdu) {
                p.oversize += 1;
                return Some(ack_data(pref, 0x8500, &[], &[]));
            }
            Some(r)
        }
        _ => Some(ack_data(pref, 0x8104, &[], &[])),
    }
}

/// The bytes of an area (`None`: no such DB).
fn area(p: &mut Plc, code: u8, db: u16) -> Option<&mut Vec<u8>> {
    match code {
        0x81 => Some(&mut p.inputs),
        0x82 => Some(&mut p.outputs),
        0x83 => Some(&mut p.markers),
        0x84 => p.dbs.get_mut(&db),
        _ => None,
    }
}

/// Where an item points: area code, DB, start, count, transport size.
fn item_of(it: &[u8]) -> (u8, u16, u32, usize, u8) {
    let addr = (u32::from(it[9]) << 16) | (u32::from(it[10]) << 8) | u32::from(it[11]);
    (
        it[8],
        u16::from_be_bytes([it[6], it[7]]),
        addr,
        usize::from(u16::from_be_bytes([it[4], it[5]])),
        it[3],
    )
}

fn read_var(p: &mut Plc, items: &[&[u8]]) -> Vec<u8> {
    let mut out = Vec::new();
    for (k, it) in items.iter().enumerate() {
        let (code, db, addr, count, ts) = item_of(it);
        let r: Result<(u8, Vec<u8>), u8> = match code {
            0x1C | 0x1D => {
                let words = if code == 0x1D { &p.timers } else { &p.counters };
                let a = addr as usize;
                words
                    .get(a..a + count)
                    .map(|w| (0x09, w.iter().flat_map(|x| x.to_be_bytes()).collect()))
                    .ok_or(0x05)
            }
            _ => match area(p, code, db) {
                None if code == 0x84 => Err(0x0A),
                None => Err(0x05),
                Some(bytes) => {
                    let start = (addr >> 3) as usize;
                    if ts == 0x01 {
                        bytes
                            .get(start)
                            .map(|b| (0x03, vec![(b >> (addr & 7)) & 1]))
                            .ok_or(0x05)
                    } else {
                        bytes
                            .get(start..start + count)
                            .map(|b| (0x04, b.to_vec()))
                            .ok_or(0x05)
                    }
                }
            },
        };
        match r {
            Ok((dts, bytes)) => {
                let len = if dts == 0x09 {
                    bytes.len()
                } else if dts == 0x03 {
                    1
                } else {
                    bytes.len() * 8
                };
                out.extend_from_slice(&[0xFF, dts]);
                out.extend_from_slice(&(len as u16).to_be_bytes());
                out.extend_from_slice(&bytes);
                if bytes.len() % 2 == 1 && k + 1 < items.len() {
                    out.push(0);
                }
            }
            Err(rc) => out.extend_from_slice(&[rc, 0, 0, 0]),
        }
    }
    out
}

fn write_var(p: &mut Plc, items: &[&[u8]], data: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    let mut i = 0;
    for (k, it) in items.iter().enumerate() {
        let (code, db, addr, count, ts) = item_of(it);
        let dts = *data.get(i + 1)?;
        let len = usize::from(be16(data, i + 2)?);
        let bytes = match dts {
            0x03 | 0x09 => len,
            _ => len.div_ceil(8),
        };
        let val = data.get(i + 4..i + 4 + bytes)?;
        i += 4 + bytes + usize::from(bytes % 2 == 1 && k + 1 < items.len());
        let rc = match area(p, code, db) {
            None if code == 0x84 => 0x0A,
            None => 0x05,
            Some(img) => {
                let start = (addr >> 3) as usize;
                if ts == 0x01 {
                    // a bit: transport BIT, one bit; the other bits stay
                    match (dts, img.get_mut(start), val.first()) {
                        (0x03, Some(b), Some(v)) => {
                            let m = 1u8 << (addr & 7);
                            *b = if *v & 1 == 1 { *b | m } else { *b & !m };
                            0xFF
                        }
                        _ => 0x07,
                    }
                } else if dts != 0x04 || bytes != count {
                    0x07
                } else {
                    match img.get_mut(start..start + count) {
                        Some(dst) => {
                            dst.copy_from_slice(val);
                            0xFF
                        }
                        None => 0x05,
                    }
                }
            }
        };
        out.push(rc);
    }
    Some(out)
}

/// SZL 0x0011 index 0: module identification of an S7-315.
fn szl(p: &Plc, req: &[u8], pref: [u8; 2]) -> Vec<u8> {
    let id = be16(req, 22).unwrap_or(0);
    let index = be16(req, 24).unwrap_or(0);
    let mut out = vec![0x32, 7, 0, 0, pref[0], pref[1], 0, 12];
    let ok = !p.no_szl && id == 0x0011;
    let mut data = Vec::new();
    if ok {
        let rec = |idx: u16, mlfb: &str| {
            let mut r = idx.to_be_bytes().to_vec();
            let mut m = mlfb.as_bytes().to_vec();
            m.resize(20, b' ');
            r.extend_from_slice(&m);
            r.extend_from_slice(&[0x00, 0xC0, 0x00, 0x03, 0x00, 0x01]);
            r
        };
        let recs = [rec(1, "6ES7 315-2EH14-0AB0"), rec(6, "6ES7 315-2EH14-0AB0")];
        data.extend_from_slice(&[0xFF, 0x09]);
        let len = 8 + recs.iter().map(Vec::len).sum::<usize>();
        data.extend_from_slice(&(len as u16).to_be_bytes());
        data.extend_from_slice(&id.to_be_bytes());
        data.extend_from_slice(&index.to_be_bytes());
        data.extend_from_slice(&28u16.to_be_bytes());
        data.extend_from_slice(&(recs.len() as u16).to_be_bytes());
        for r in recs {
            data.extend_from_slice(&r);
        }
    } else {
        data.extend_from_slice(&[0x0A, 0, 0, 0]);
    }
    out.extend_from_slice(&(data.len() as u16).to_be_bytes());
    let err: u16 = if ok { 0 } else { 0xD401 };
    out.extend_from_slice(&[0x00, 0x01, 0x12, 0x08, 0x12, 0x84, 0x01, 0x01, 0x00, 0x00]);
    out.extend_from_slice(&err.to_be_bytes());
    out.extend_from_slice(&data);
    out
}
