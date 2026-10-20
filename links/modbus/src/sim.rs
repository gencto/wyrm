//! Minimal Modbus TCP device simulator (feature `sim`): 1000 coils, discrete
//! inputs, input and holding registers, all zero at start. Addresses outside
//! the tables answer `IllegalDataAddress`. Stand-in for `diagslave` in tests.

use std::future;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use tokio::net::TcpListener;
use tokio_modbus::server::tcp::{accept_tcp_connection, Server};
use tokio_modbus::server::Service;
use tokio_modbus::{ExceptionCode, Request, Response};

pub const SIZE: usize = 1000;

#[derive(Debug)]
pub struct Tables {
    pub coils: Vec<bool>,
    pub discrete: Vec<bool>,
    pub input: Vec<u16>,
    pub holding: Vec<u16>,
}

impl Default for Tables {
    fn default() -> Self {
        Self {
            coils: vec![false; SIZE],
            discrete: vec![false; SIZE],
            input: vec![0; SIZE],
            holding: vec![0; SIZE],
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

impl Service for Sim {
    type Request = Request<'static>;
    type Response = Response;
    type Exception = ExceptionCode;
    type Future = future::Ready<Result<Response, ExceptionCode>>;

    fn call(&self, req: Request<'static>) -> Self::Future {
        let mut t = self.0.lock().unwrap_or_else(|p| p.into_inner());
        future::ready(match req {
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
            _ => Err(ExceptionCode::IllegalFunction),
        })
    }
}

/// Serve `device` on `listener` until the task is dropped or aborted.
pub async fn serve(listener: TcpListener, device: Device) -> std::io::Result<()> {
    let server = Server::new(listener);
    let on_connected = |stream, addr: SocketAddr| {
        let device = device.clone();
        async move { accept_tcp_connection(stream, addr, move |_| Ok(Some(Sim(device.clone())))) }
    };
    server
        .serve(&on_connected, |e| tracing::debug!("sim connection: {e}"))
        .await
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
