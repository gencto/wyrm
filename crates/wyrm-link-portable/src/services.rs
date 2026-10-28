//! What the runtime gives the command buffer on the engine thread: the clock, the store, the
//! link's grants and blocking TCP within the `net` allowlist (ADR 0012 rules).

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use wyrm_core::{Perm, Status};
use wyrm_link_api::buffer::Services;
use wyrm_link_api::net::NetPolicy;
use wyrm_link_api::{AppError, ConnId};

use crate::store::Store;

/// Open connections per instance.
pub const MAX_CONNS: usize = 4;
/// Largest `recv`.
pub const MAX_RECV: u32 = 64 << 10;
/// Largest `send`.
pub const MAX_SEND: usize = 64 << 10;

/// The store, shared by the services (reads) and the engine thread (writes).
pub type SharedStore = Arc<Mutex<Store>>;
/// Set by the engine thread: the end of the current call (TCP waits never pass it), and whether
/// the instance was dropped since the last call (its connections are then closed).
#[derive(Debug, Default)]
pub struct CallState {
    pub deadline: Option<Instant>,
    pub reset: bool,
}

pub type SharedCall = Arc<Mutex<CallState>>;

pub(crate) fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

/// The grant that covers `key`: a grant path covers itself and everything below it
/// (ADR 0013); a trailing `/**` means the same. The longest covering grant decides.
pub fn grants_allow(grants: &[(String, Perm)], key: &str, need: Perm) -> bool {
    grants
        .iter()
        .filter_map(|(p, perm)| {
            let p = p.strip_suffix("/**").unwrap_or(p);
            let covers = key == p
                || key
                    .strip_prefix(p)
                    .is_some_and(|rest| rest.starts_with('/'));
            covers.then_some((p.len(), *perm))
        })
        .max_by_key(|(len, _)| *len)
        .is_some_and(|(_, perm)| perm >= need)
}

pub struct RuntimeServices {
    store: SharedStore,
    grants: Vec<(String, Perm)>,
    policy: NetPolicy,
    conns: HashMap<u32, TcpStream>,
    next_conn: u32,
    call: SharedCall,
}

fn net_err(status: Status, msg: impl Into<String>) -> AppError {
    AppError::new(status, msg)
}

impl RuntimeServices {
    pub fn new(
        store: SharedStore,
        grants: Vec<(String, Perm)>,
        policy: NetPolicy,
        call: SharedCall,
    ) -> Self {
        Self {
            store,
            grants,
            policy,
            conns: HashMap::new(),
            next_conn: 0,
            call,
        }
    }

    /// Connections of a dropped instance are closed before the new one uses the network.
    fn sweep(&mut self) {
        if std::mem::take(&mut lock(&self.call).reset) {
            self.conns.clear();
        }
    }

    /// `ms` capped at the time left in the call; an error when none is left.
    fn budget(&self, ms: u32) -> Result<Duration, AppError> {
        let left = lock(&self.call)
            .deadline
            .map(|d| d.saturating_duration_since(Instant::now()))
            .unwrap_or(Duration::ZERO);
        if left < Duration::from_millis(1) {
            return Err(net_err(Status::Timeout, "no time left in this call"));
        }
        Ok(Duration::from_millis(ms.max(1).into()).min(left))
    }

    fn conn(&mut self, c: ConnId) -> Result<&mut TcpStream, AppError> {
        self.sweep();
        self.conns
            .get_mut(&c.0)
            .ok_or_else(|| net_err(Status::NotFound, format!("no connection {}", c.0)))
    }
}

fn timed_out(e: &std::io::Error) -> bool {
    matches!(
        e.kind(),
        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
    )
}

impl Services for RuntimeServices {
    fn now_us(&self) -> u64 {
        wyrm_link_sdk::now_us()
    }

    fn store_get(&self, key: &str) -> Option<Vec<u8>> {
        lock(&self.store).get(key)
    }

    fn store_used(&self) -> u64 {
        lock(&self.store).used()
    }

    fn store_ready(&self) -> Result<(), AppError> {
        if lock(&self.store).is_ready() {
            Ok(())
        } else {
            // no `unavailable` status in spec 04: `not_supported` (this host gives no store)
            Err(AppError::new(
                Status::NotSupported,
                "the link has no store (no data directory or store key)",
            ))
        }
    }

    fn may(&self, key: &str, perm: Perm) -> bool {
        grants_allow(&self.grants, key, perm)
    }

    fn tcp_connect(&mut self, addr: &str, port: u16, timeout_ms: u32) -> Result<ConnId, AppError> {
        let ip: IpAddr = addr
            .parse()
            .map_err(|_| net_err(Status::InvalidParameter, format!("{addr}: an IP literal")))?;
        self.sweep();
        if !self.policy.allows(ip, port) {
            return Err(net_err(
                Status::PermissionDenied,
                format!("{addr}:{port} is not in the link's net list"),
            ));
        }
        if self.conns.len() >= MAX_CONNS {
            return Err(net_err(
                Status::ResourceExhausted,
                format!("at most {MAX_CONNS} connections"),
            ));
        }
        let t = self.budget(timeout_ms)?;
        let s = TcpStream::connect_timeout(&SocketAddr::new(ip, port), t).map_err(|e| {
            let status = if timed_out(&e) {
                Status::Timeout
            } else {
                Status::Disconnected
            };
            net_err(status, format!("connect {addr}:{port}: {e}"))
        })?;
        let _ = s.set_nodelay(true);
        self.next_conn = self.next_conn.wrapping_add(1);
        let h = self.next_conn;
        self.conns.insert(h, s);
        Ok(ConnId(h))
    }

    fn tcp_send(&mut self, c: ConnId, data: &[u8]) -> Result<(), AppError> {
        if data.len() > MAX_SEND {
            return Err(net_err(
                Status::InvalidParameter,
                format!("send: at most {MAX_SEND} bytes at a time"),
            ));
        }
        let mut off = 0;
        while off < data.len() {
            let t = self.budget(u32::MAX)?;
            let s = self.conn(c)?;
            s.set_write_timeout(Some(t))
                .map_err(|e| net_err(Status::InternalError, e.to_string()))?;
            match s.write(&data[off..]) {
                Ok(0) => return Err(net_err(Status::Disconnected, "send: connection closed")),
                Ok(n) => off += n,
                Err(e) if timed_out(&e) => return Err(net_err(Status::Timeout, "send: timeout")),
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(e) => return Err(net_err(Status::Disconnected, format!("send: {e}"))),
            }
        }
        Ok(())
    }

    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError> {
        let t = self.budget(timeout_ms)?;
        let s = self.conn(c)?;
        s.set_read_timeout(Some(t))
            .map_err(|e| net_err(Status::InternalError, e.to_string()))?;
        let mut buf = vec![0u8; max.min(MAX_RECV) as usize];
        match s.read(&mut buf) {
            Ok(n) => {
                buf.truncate(n);
                Ok(buf)
            }
            Err(e) if timed_out(&e) => Err(net_err(Status::Timeout, "recv: timeout")),
            Err(e) => Err(net_err(Status::Disconnected, format!("recv: {e}"))),
        }
    }

    fn tcp_close(&mut self, c: ConnId) {
        self.sweep();
        self.conns.remove(&c.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn grants_cover_paths_and_below() {
        let g = vec![
            ("wy/s/downstream/mock".to_owned(), Perm::Read),
            ("wy/s/downstream/mock/plc/**".to_owned(), Perm::Write),
        ];
        assert!(grants_allow(&g, "wy/s/downstream/mock/p", Perm::Read));
        assert!(!grants_allow(&g, "wy/s/downstream/mock/p", Perm::Write));
        assert!(grants_allow(&g, "wy/s/downstream/mock/plc/p", Perm::Write));
        assert!(grants_allow(&g, "wy/s/downstream/mock/plc", Perm::Write));
        assert!(!grants_allow(&g, "wy/s/downstream/mockx/p", Perm::Read));
        assert!(!grants_allow(&[], "wy/s/downstream/mock/p", Perm::Read));
    }

    #[test]
    fn tcp_outside_the_net_list_is_refused() {
        let mut s = RuntimeServices::new(
            Arc::new(Mutex::new(Store::none())),
            Vec::new(),
            NetPolicy::parse("10.0.0.0/8:502").unwrap(),
            Arc::new(Mutex::new(CallState {
                deadline: Some(Instant::now() + Duration::from_secs(1)),
                reset: false,
            })),
        );
        let e = s.tcp_connect("127.0.0.1", 502, 100).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        let e = s.tcp_connect("localhost", 502, 100).unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter);
        assert_eq!(s.store_ready().unwrap_err().status, Status::NotSupported);
    }
}
