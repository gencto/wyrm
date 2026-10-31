//! Test support for targets (feature `testkit`): a host with real TCP over std sockets, so a
//! target's tests talk to a fake server on loopback. TLS is the portable host's own test.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;
use wyrm_core::{ActionMeta, NodeMeta, Sample, Status, Value};
use wyrm_link_api::{AppError, ConnId, Host, Level, ReqId, SubId, TimerId};

/// A host with real TCP (tests run natively; TLS is the portable host's own test).
#[derive(Default)]
pub struct TcpHost {
    conns: HashMap<u32, TcpStream>,
    next: u32,
}

fn unsupported<T>() -> Result<T, AppError> {
    Err(AppError::new(Status::NotSupported, "not in this test"))
}

impl Host for TcpHost {
    fn declare_node(&mut self, _p: &str, _m: NodeMeta) {}
    fn declare_action(&mut self, _p: &str, _n: &str, _a: ActionMeta) {}
    fn remove_node(&mut self, _p: &str) {}
    fn update(&mut self, _p: &str, _s: Sample) {}
    fn now_us(&self) -> u64 {
        0
    }
    fn set_timer(&mut self, _ms: u64) -> Result<TimerId, AppError> {
        unsupported()
    }
    fn cancel_timer(&mut self, _t: TimerId) {}
    fn store_get(&self, _k: &str) -> Option<Vec<u8>> {
        None
    }
    fn store_put(&mut self, _k: &str, _v: &[u8]) -> Result<(), AppError> {
        unsupported()
    }
    fn store_delete(&mut self, _k: &str) {}
    fn subscribe(&mut self, _k: &str) -> Result<SubId, AppError> {
        unsupported()
    }
    fn unsubscribe(&mut self, _s: SubId) {}
    fn set(&mut self, _k: &str, _v: Value) -> Result<ReqId, AppError> {
        unsupported()
    }
    fn invoke(&mut self, _k: &str, _a: &str, _v: Value) -> Result<ReqId, AppError> {
        unsupported()
    }
    fn tcp_connect(&mut self, addr: &str, port: u16, _t: u32) -> Result<ConnId, AppError> {
        let s = TcpStream::connect((addr, port))
            .map_err(|e| AppError::new(Status::Disconnected, e.to_string()))?;
        s.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        self.next += 1;
        self.conns.insert(self.next, s);
        Ok(ConnId(self.next))
    }
    fn tcp_send(&mut self, c: ConnId, d: &[u8]) -> Result<(), AppError> {
        let s = self
            .conns
            .get_mut(&c.0)
            .ok_or(AppError::new(Status::NotFound, "conn"))?;
        s.write_all(d)
            .map_err(|e| AppError::new(Status::Disconnected, e.to_string()))
    }
    fn tcp_recv(&mut self, c: ConnId, max: u32, _t: u32) -> Result<Vec<u8>, AppError> {
        let s = self
            .conns
            .get_mut(&c.0)
            .ok_or(AppError::new(Status::NotFound, "conn"))?;
        let mut b = vec![0u8; max as usize];
        let n = s
            .read(&mut b)
            .map_err(|e| AppError::new(Status::Disconnected, e.to_string()))?;
        b.truncate(n);
        Ok(b)
    }
    fn tcp_close(&mut self, c: ConnId) {
        self.conns.remove(&c.0);
    }
    fn log(&mut self, _l: Level, _m: &str) {}
}
