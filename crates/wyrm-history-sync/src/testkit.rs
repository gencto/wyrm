//! Test support for targets (feature `testkit`): a host with real TCP over std sockets, so a
//! target's tests talk to a fake server on loopback. TLS is the portable host's own test.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;
use wyrm_core::{ActionMeta, NodeMeta, Sample, Status, Value};
use wyrm_link_api::{AppError, ConnId, Host, Level, ReqId, SubId, TimerId};

/// A host with real TCP (tests run natively; TLS is the portable host's own test). It also
/// keeps what an App does, so a test drives a whole [`crate::SyncApp`]: the values it shows,
/// its store, the timers it arms and the requests it sends (the test fires and answers them).
#[derive(Default)]
pub struct TcpHost {
    conns: HashMap<u32, TcpStream>,
    next: u32,
    pub values: HashMap<String, Value>,
    pub store: HashMap<String, Vec<u8>>,
    pub timers: Vec<TimerId>,
    pub invokes: Vec<(ReqId, String, String, Value)>,
    ids: u64,
}

fn unsupported<T>() -> Result<T, AppError> {
    Err(AppError::new(Status::NotSupported, "not in this test"))
}

impl Host for TcpHost {
    fn declare_node(&mut self, _p: &str, _m: NodeMeta) {}
    fn declare_action(&mut self, _p: &str, _n: &str, _a: ActionMeta) {}
    fn remove_node(&mut self, _p: &str) {}
    fn update(&mut self, p: &str, s: Sample) {
        self.values.insert(p.to_owned(), s.v);
    }
    fn now_us(&self) -> u64 {
        0
    }
    fn set_timer(&mut self, _ms: u64) -> Result<TimerId, AppError> {
        self.ids += 1;
        self.timers.push(TimerId(self.ids));
        Ok(TimerId(self.ids))
    }
    fn cancel_timer(&mut self, t: TimerId) {
        self.timers.retain(|x| *x != t);
    }
    fn store_get(&self, k: &str) -> Option<Vec<u8>> {
        self.store.get(k).cloned()
    }
    fn store_put(&mut self, k: &str, v: &[u8]) -> Result<(), AppError> {
        self.store.insert(k.to_owned(), v.to_vec());
        Ok(())
    }
    fn store_delete(&mut self, k: &str) {
        self.store.remove(k);
    }
    fn subscribe(&mut self, _k: &str) -> Result<SubId, AppError> {
        unsupported()
    }
    fn unsubscribe(&mut self, _s: SubId) {}
    fn set(&mut self, _k: &str, _v: Value) -> Result<ReqId, AppError> {
        unsupported()
    }
    fn invoke(&mut self, k: &str, a: &str, v: Value) -> Result<ReqId, AppError> {
        self.ids += 1;
        self.invokes
            .push((ReqId(self.ids), k.to_owned(), a.to_owned(), v));
        Ok(ReqId(self.ids))
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
