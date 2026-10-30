//! Minimal Modbus TCP device simulator (feature `sim`): 1000 coils, discrete
//! inputs, input and holding registers, all zero at start. Addresses outside
//! the tables answer `IllegalDataAddress`. Supports FC1–6, 15, 16, 17, 22
//! and 43/14 Read Device Identification (basic and regular objects; FC22
//! and FC43 can be switched off). Every unit id is served by the same
//! tables unless [`Tables::answer_units`] names the units that answer; the
//! ids seen are recorded. Faults for tests: a fixed latency on every reply,
//! one late reply, one exception and dropped (unanswered) requests, keyed by
//! unit and address. Stand-in for `diagslave` in tests.

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::future::Future;
use std::net::SocketAddr;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::net::TcpListener;
use tokio_modbus::prelude::{
    ConformityLevel, DeviceIdObject, ReadCode, ReadDeviceIdentificationResponse,
};
use tokio_modbus::server::tcp::{accept_tcp_connection, Server};
use tokio_modbus::server::Service;
use tokio_modbus::{ExceptionCode, Request, Response, SlaveRequest};

pub const SIZE: usize = 1000;

#[derive(Debug)]
pub struct Tables {
    pub coils: Vec<bool>,
    pub discrete: Vec<bool>,
    pub input: Vec<u16>,
    pub holding: Vec<u16>,
    /// Requests served (all function codes).
    pub requests: u64,
    /// Answer FC22 (mask write) with `IllegalFunction`.
    pub no_fc22: bool,
    /// Unit ids of the requests served.
    pub units: BTreeSet<u8>,
    /// `(unit, function code, start address)` of the last [`LOG_MAX`]
    /// requests, in order (the start address is 0 for FC17).
    pub log: VecDeque<(u8, u8, u16)>,
    /// Requests served by function code.
    pub by_fc: BTreeMap<u8, u64>,
    /// Delay before every reply (a slow bus or device).
    pub latency: Duration,
    /// Answer the next request to `(unit, addr)` that much later (once).
    pub delay_once: Option<(u8, u16, Duration)>,
    /// Leave the next `n` requests to `(unit, addr)` unanswered.
    pub drop_next: Option<(u8, u16, u32)>,
    /// Answer the next request to `(unit, addr)` with this exception (once).
    pub except_once: Option<(u8, u16, ExceptionCode)>,
    /// Requests left unanswered so far.
    pub dropped: u64,
    /// TCP connections accepted.
    pub connections: u64,
    /// Units that answer (`None` = every unit); requests to others are
    /// left unanswered (counted in `dropped`).
    pub answer_units: Option<BTreeSet<u8>>,
    /// Answer FC43 with `IllegalFunction` (a device without identification).
    pub no_fc43: bool,
    /// FC43/14 objects by id: 0–2 basic (vendor name, product code,
    /// revision), 3–6 regular (vendor URL, product name, model name, user
    /// application name).
    pub device_id: BTreeMap<u8, String>,
    /// Objects per FC43 reply (0 = all); fewer sets `more follows`.
    pub id_per_reply: usize,
}

/// Entries kept in [`Tables::log`] (a long-running simulator stays bounded).
pub const LOG_MAX: usize = 10_000;

impl Tables {
    /// Requests of function code `fc` served so far.
    pub fn count(&self, fc: u8) -> u64 {
        self.by_fc.get(&fc).copied().unwrap_or(0)
    }
}

impl Default for Tables {
    fn default() -> Self {
        Self {
            coils: vec![false; SIZE],
            discrete: vec![false; SIZE],
            input: vec![0; SIZE],
            holding: vec![0; SIZE],
            requests: 0,
            no_fc22: false,
            units: BTreeSet::new(),
            log: VecDeque::new(),
            by_fc: BTreeMap::new(),
            latency: Duration::ZERO,
            delay_once: None,
            drop_next: None,
            except_once: None,
            dropped: 0,
            connections: 0,
            answer_units: None,
            no_fc43: false,
            device_id: BTreeMap::from([
                (0, "WYRM".to_owned()),
                (1, "WYRM-SIM".to_owned()),
                (2, "1.0".to_owned()),
                (3, "https://wyrm.invalid".to_owned()),
                (4, "Modbus Simulator".to_owned()),
                (5, "SIM-1000".to_owned()),
            ]),
            id_per_reply: 0,
        }
    }
}

pub type Device = Arc<Mutex<Tables>>;

fn range<T: Clone>(t: &[T], addr: u16, n: u16) -> Result<Vec<T>, ExceptionCode> {
    let (a, n) = (addr as usize, n as usize);
    t.get(a..a + n)
        .map(<[T]>::to_vec)
        .ok_or(ExceptionCode::IllegalDataAddress)
}

fn slot<T>(t: &mut [T], addr: u16) -> Result<&mut T, ExceptionCode> {
    t.get_mut(addr as usize)
        .ok_or(ExceptionCode::IllegalDataAddress)
}

struct Sim(Device);

/// The start address of a request (0 when it has none).
fn start_addr(r: &Request<'_>) -> u16 {
    match r {
        Request::ReadCoils(a, _)
        | Request::ReadDiscreteInputs(a, _)
        | Request::ReadInputRegisters(a, _)
        | Request::ReadHoldingRegisters(a, _)
        | Request::WriteSingleCoil(a, _)
        | Request::WriteSingleRegister(a, _)
        | Request::WriteMultipleRegisters(a, _)
        | Request::WriteMultipleCoils(a, _)
        | Request::MaskWriteRegister(a, _, _) => *a,
        _ => 0,
    }
}

type Answer = Result<Option<Response>, ExceptionCode>;

impl Service for Sim {
    type Request = SlaveRequest<'static>;
    type Response = Option<Response>;
    type Exception = ExceptionCode;
    type Future = Pin<Box<dyn Future<Output = Answer> + Send>>;

    fn call(&self, req: SlaveRequest<'static>) -> Self::Future {
        let mut t = self.0.lock().unwrap_or_else(|p| p.into_inner());
        let (unit, addr) = (req.slave, start_addr(&req.request));
        t.requests += 1;
        t.units.insert(unit);
        let fc = req.request.function_code().value();
        if t.log.len() == LOG_MAX {
            t.log.pop_front();
        }
        t.log.push_back((unit, fc, addr));
        *t.by_fc.entry(fc).or_default() += 1;
        if t.answer_units.as_ref().is_some_and(|u| !u.contains(&unit)) {
            t.dropped += 1;
            return Box::pin(std::future::ready(Ok(None)));
        }
        if let Some((u, a, n)) = t.drop_next {
            if (u, a) == (unit, addr) && n > 0 {
                t.drop_next = (n > 1).then_some((u, a, n - 1));
                t.dropped += 1;
                return Box::pin(std::future::ready(Ok(None)));
            }
        }
        let mut delay = t.latency;
        if let Some((u, a, d)) = t.delay_once {
            if (u, a) == (unit, addr) {
                t.delay_once = None;
                delay += d;
            }
        }
        let answer = match t.except_once {
            Some((u, a, e)) if (u, a) == (unit, addr) => {
                t.except_once = None;
                Err(e)
            }
            _ => Self::answer(&mut t, req.request).map(Some),
        };
        drop(t);
        Box::pin(async move {
            if !delay.is_zero() {
                tokio::time::sleep(delay).await;
            }
            answer
        })
    }
}

impl Sim {
    fn answer(t: &mut Tables, req: Request<'static>) -> Result<Response, ExceptionCode> {
        match req {
            Request::ReadCoils(a, n) => range(&t.coils, a, n).map(Response::ReadCoils),
            Request::ReadDiscreteInputs(a, n) => {
                range(&t.discrete, a, n).map(Response::ReadDiscreteInputs)
            }
            Request::ReadInputRegisters(a, n) => {
                range(&t.input, a, n).map(Response::ReadInputRegisters)
            }
            Request::ReadHoldingRegisters(a, n) => {
                range(&t.holding, a, n).map(Response::ReadHoldingRegisters)
            }
            Request::WriteSingleCoil(a, v) => slot(&mut t.coils, a)
                .map(|c| *c = v)
                .map(|_| Response::WriteSingleCoil(a, v)),
            Request::WriteSingleRegister(a, v) => slot(&mut t.holding, a)
                .map(|r| *r = v)
                .map(|_| Response::WriteSingleRegister(a, v)),
            Request::WriteMultipleRegisters(a, words) => {
                let end = a as usize + words.len();
                match t.holding.get_mut(a as usize..end) {
                    Some(dst) => {
                        dst.copy_from_slice(&words);
                        Ok(Response::WriteMultipleRegisters(a, words.len() as u16))
                    }
                    None => Err(ExceptionCode::IllegalDataAddress),
                }
            }
            Request::WriteMultipleCoils(a, bits) => {
                let end = a as usize + bits.len();
                match t.coils.get_mut(a as usize..end) {
                    Some(dst) => {
                        dst.copy_from_slice(&bits);
                        Ok(Response::WriteMultipleCoils(a, bits.len() as u16))
                    }
                    None => Err(ExceptionCode::IllegalDataAddress),
                }
            }
            Request::MaskWriteRegister(a, and, or) => {
                if t.no_fc22 {
                    Err(ExceptionCode::IllegalFunction)
                } else {
                    slot(&mut t.holding, a)
                        .map(|r| *r = (*r & and) | (or & !and))
                        .map(|_| Response::MaskWriteRegister(a, and, or))
                }
            }
            // FC17 Report Server ID: id 1, run indicator on.
            Request::Custom(0x11, _) => Ok(Response::Custom(0x11, vec![2, 1, 0xFF].into())),
            Request::ReadDeviceIdentification(code, start) if !t.no_fc43 => {
                Self::device_id(t, code, start)
            }
            _ => Err(ExceptionCode::IllegalFunction),
        }
    }

    /// FC43/14 stream access from object `start` within the category of
    /// `code` (basic 0–2, regular 3–6; extended has none), at most
    /// `id_per_reply` objects per reply; individual access: one object.
    fn device_id(t: &Tables, code: ReadCode, start: u8) -> Result<Response, ExceptionCode> {
        let ids = match code {
            ReadCode::Basic => 0..=2,
            ReadCode::Regular => 3..=6,
            ReadCode::Extended => 0x80..=0xFF,
            ReadCode::Specific => start..=start,
        };
        let mut objects: Vec<DeviceIdObject> = t
            .device_id
            .range(ids)
            .filter(|(id, _)| **id >= start)
            .map(|(id, v)| DeviceIdObject {
                id: *id,
                value: v.clone().into_bytes().into(),
            })
            .collect();
        if code == ReadCode::Specific && objects.is_empty() {
            return Err(ExceptionCode::IllegalDataAddress);
        }
        let more = t.id_per_reply > 0 && objects.len() > t.id_per_reply;
        let next = if more {
            objects.truncate(t.id_per_reply + 1);
            objects.pop().map_or(0, |o| o.id)
        } else {
            0
        };
        Ok(Response::ReadDeviceIdentification(
            ReadDeviceIdentificationResponse {
                read_code: code,
                conformity_level: ConformityLevel::RegularIdentification,
                more_follows: more,
                next_object_id: next,
                device_id_objects: objects,
            },
        ))
    }
}

/// Serve `device` on `listener` until the task is dropped or aborted.
pub async fn serve(listener: TcpListener, device: Device) -> std::io::Result<()> {
    let server = Server::new(listener);
    let on_connected = |stream, addr: SocketAddr| {
        let device = device.clone();
        device.lock().unwrap_or_else(|p| p.into_inner()).connections += 1;
        async move { accept_tcp_connection(stream, addr, move |_| Ok(Some(Sim(device.clone())))) }
    };
    server
        .serve(&on_connected, |e| tracing::debug!("sim connection: {e}"))
        .await
}

/// Serve `device` with RTU framing over TCP (what serial-to-Ethernet
/// gateways send) until the task is dropped or aborted.
pub async fn serve_rtu_over_tcp(listener: TcpListener, device: Device) -> std::io::Result<()> {
    use tokio_modbus::server::rtu_over_tcp;
    let server = rtu_over_tcp::Server::new(listener);
    let on_connected = |stream, addr: SocketAddr| {
        let device = device.clone();
        device.lock().unwrap_or_else(|p| p.into_inner()).connections += 1;
        async move {
            rtu_over_tcp::accept_tcp_connection(stream, addr, move |_| {
                Ok(Some(Sim(device.clone())))
            })
        }
    };
    server
        .serve(&on_connected, |e| {
            tracing::debug!("sim rtu connection: {e}")
        })
        .await
}

/// Like [`spawn`], with RTU framing over TCP.
pub async fn spawn_rtu_over_tcp(
    addr: &str,
) -> std::io::Result<(SocketAddr, Device, tokio::task::JoinHandle<()>)> {
    let listener = TcpListener::bind(addr).await?;
    let local = listener.local_addr()?;
    let device = Device::default();
    let d = device.clone();
    let task = tokio::spawn(async move {
        let _ = serve_rtu_over_tcp(listener, d).await;
    });
    Ok((local, device, task))
}

/// Bind `addr` (use port 0 for a free port) and serve in a task.
pub async fn spawn(
    addr: &str,
) -> std::io::Result<(SocketAddr, Device, tokio::task::JoinHandle<()>)> {
    let listener = TcpListener::bind(addr).await?;
    let local = listener.local_addr()?;
    let device = Device::default();
    let d = device.clone();
    let task = tokio::spawn(async move {
        let _ = serve(listener, d).await;
    });
    Ok((local, device, task))
}
