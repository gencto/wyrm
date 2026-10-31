//! What the runtime gives the command buffer on the engine thread: the clock, the store, the
//! link's grants and blocking TCP, plain or TLS, within the `net` allowlist (ADR 0012 rules,
//! host names and TLS: ADR 0026).

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs};
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

/// One open connection: plain TCP, or TLS over TCP (its keys never leave the host).
enum Conn {
    Plain(TcpStream),
    Tls(Box<rustls::StreamOwned<rustls::ClientConnection, TcpStream>>),
}

impl Conn {
    fn sock(&self) -> &TcpStream {
        match self {
            Conn::Plain(s) => s,
            Conn::Tls(t) => &t.sock,
        }
    }
}

impl Read for Conn {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Conn::Plain(s) => s.read(buf),
            Conn::Tls(t) => t.read(buf),
        }
    }
}

impl Write for Conn {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match self {
            Conn::Plain(s) => s.write(buf),
            Conn::Tls(t) => t.write(buf),
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            Conn::Plain(s) => s.flush(),
            Conn::Tls(t) => t.flush(),
        }
    }
}

pub struct RuntimeServices {
    store: SharedStore,
    grants: Vec<(String, Perm)>,
    policy: NetPolicy,
    conns: HashMap<u32, Conn>,
    next_conn: u32,
    call: SharedCall,
}

/// The host's CA certificates (`rustls-native-certs`), loaded once per process (CAs the host
/// adds later need a restart), and the first error of the load, if any.
type Roots = (
    Vec<rustls_pki_types::CertificateDer<'static>>,
    Option<String>,
);

static SYSTEM_ROOTS: std::sync::LazyLock<Roots> = std::sync::LazyLock::new(|| {
    let r = rustls_native_certs::load_native_certs();
    (r.certs, r.errors.first().map(|e| e.to_string()))
});

/// A client config that trusts the host's roots, or only the CAs in `ca_pem`. ring only:
/// never the process default provider (aws-lc is forbidden).
fn tls_config(ca_pem: Option<&str>) -> Result<Arc<rustls::ClientConfig>, AppError> {
    use rustls_pki_types::pem::PemObject;
    let mut roots = rustls::RootCertStore::empty();
    match ca_pem.map(str::trim).filter(|c| !c.is_empty()) {
        Some(pem) => {
            for c in rustls_pki_types::CertificateDer::pem_slice_iter(pem.as_bytes()) {
                let c = c.map_err(|e| net_err(Status::InvalidParameter, format!("ca_pem: {e}")))?;
                roots
                    .add(c)
                    .map_err(|e| net_err(Status::InvalidParameter, format!("ca_pem: {e}")))?;
            }
            if roots.is_empty() {
                return Err(net_err(
                    Status::InvalidParameter,
                    "ca_pem: no certificate in it",
                ));
            }
        }
        None => {
            let (certs, err) = &*SYSTEM_ROOTS;
            roots.add_parsable_certificates(certs.iter().cloned());
            if roots.is_empty() {
                let why = err.as_deref().unwrap_or("none found");
                return Err(net_err(
                    Status::InternalError,
                    format!("no CA certificates on this host ({why}); give ca_pem"),
                ));
            }
        }
    }
    let cfg = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(|e| net_err(Status::InternalError, format!("tls: {e}")))?
    .with_root_certificates(roots)
    .with_no_client_auth();
    Ok(Arc::new(cfg))
}

/// The addresses of `host` (an IP literal is itself), resolved on a thread of its own so a
/// hung resolver costs the call no more than `wait`.
fn resolve(host: &str, port: u16, wait: Duration) -> Result<Vec<SocketAddr>, AppError> {
    if let Ok(ip) = host.parse::<IpAddr>() {
        return Ok(vec![SocketAddr::new(ip, port)]);
    }
    let (tx, rx) = std::sync::mpsc::channel();
    let name = host.to_owned();
    std::thread::Builder::new()
        .name("wyrm-dns".into())
        .spawn(move || {
            let _ = tx.send(
                (name.as_str(), port)
                    .to_socket_addrs()
                    .map(|a| a.collect::<Vec<_>>()),
            );
        })
        .map_err(|e| net_err(Status::InternalError, format!("resolve {host}: {e}")))?;
    match rx.recv_timeout(wait) {
        Ok(Ok(a)) if !a.is_empty() => Ok(a),
        Ok(Ok(_)) => Err(net_err(
            Status::Disconnected,
            format!("resolve {host}: no address"),
        )),
        Ok(Err(e)) => Err(net_err(
            Status::Disconnected,
            format!("resolve {host}: {e}"),
        )),
        Err(_) => Err(net_err(Status::Timeout, format!("resolve {host}: timeout"))),
    }
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

    /// The address to connect to: `addr` itself (an IP the list allows), or the first address
    /// of a host name that [`NetPolicy::allows_named`] accepts.
    fn reachable(&self, addr: &str, port: u16, timeout_ms: u32) -> Result<SocketAddr, AppError> {
        let denied = || {
            net_err(
                Status::PermissionDenied,
                format!("{addr}:{port} is not in the link's net list"),
            )
        };
        if let Ok(ip) = addr.parse::<IpAddr>() {
            return if self.policy.allows(ip, port) {
                Ok(SocketAddr::new(ip, port))
            } else {
                Err(denied())
            };
        }
        if rustls_pki_types::DnsName::try_from(addr).is_err() {
            return Err(net_err(
                Status::InvalidParameter,
                format!("{addr}: an IP literal or a host name"),
            ));
        }
        resolve(addr, port, self.budget(timeout_ms)?)?
            .into_iter()
            .find(|a| self.policy.allows_named(addr, a.ip(), port))
            .ok_or_else(denied)
    }

    /// TLS over `sock`, within the time the call has left; the certificate for `host`.
    fn handshake(
        &self,
        mut sock: TcpStream,
        cfg: Arc<rustls::ClientConfig>,
        name: rustls_pki_types::ServerName<'static>,
        host: &str,
        timeout_ms: u32,
    ) -> Result<Conn, AppError> {
        let mut tls = rustls::ClientConnection::new(cfg, name)
            .map_err(|e| net_err(Status::InternalError, format!("tls {host}: {e}")))?;
        while tls.is_handshaking() {
            let t = self.budget(timeout_ms)?;
            sock.set_read_timeout(Some(t))
                .and_then(|_| sock.set_write_timeout(Some(t)))
                .map_err(|e| net_err(Status::InternalError, e.to_string()))?;
            if let Err(e) = tls.complete_io(&mut sock) {
                let status = if timed_out(&e) {
                    Status::Timeout
                } else {
                    Status::Disconnected
                };
                return Err(net_err(status, format!("tls {host}: {e}")));
            }
        }
        Ok(Conn::Tls(Box::new(rustls::StreamOwned::new(tls, sock))))
    }

    fn keep(&mut self, c: Conn) -> ConnId {
        self.next_conn = self.next_conn.wrapping_add(1);
        let h = self.next_conn;
        self.conns.insert(h, c);
        ConnId(h)
    }

    fn conn(&mut self, c: ConnId) -> Result<&mut Conn, AppError> {
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

    fn store_keys(&self) -> usize {
        lock(&self.store).len()
    }

    fn store_len(&self, key: &str) -> Option<usize> {
        lock(&self.store).value_len(key)
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
        self.sweep();
        if self.conns.len() >= MAX_CONNS {
            return Err(net_err(
                Status::ResourceExhausted,
                format!("at most {MAX_CONNS} connections"),
            ));
        }
        let to = self.reachable(addr, port, timeout_ms)?;
        let t = self.budget(timeout_ms)?;
        let s = TcpStream::connect_timeout(&to, t).map_err(|e| {
            let status = if timed_out(&e) {
                Status::Timeout
            } else {
                Status::Disconnected
            };
            net_err(status, format!("connect {addr}:{port}: {e}"))
        })?;
        let _ = s.set_nodelay(true);
        Ok(self.keep(Conn::Plain(s)))
    }

    fn tls_connect(
        &mut self,
        host: &str,
        port: u16,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<ConnId, AppError> {
        let name = rustls_pki_types::ServerName::try_from(host.to_owned()).map_err(|_| {
            net_err(
                Status::InvalidParameter,
                format!("{host}: a DNS name or an IP literal"),
            )
        })?;
        self.sweep();
        if self.conns.len() >= MAX_CONNS {
            return Err(net_err(
                Status::ResourceExhausted,
                format!("at most {MAX_CONNS} connections"),
            ));
        }
        let cfg = tls_config(ca_pem)?;
        let addr = self.reachable(host, port, timeout_ms)?;
        let t = self.budget(timeout_ms)?;
        let sock = TcpStream::connect_timeout(&addr, t).map_err(|e| {
            let status = if timed_out(&e) {
                Status::Timeout
            } else {
                Status::Disconnected
            };
            net_err(status, format!("connect {host}:{port}: {e}"))
        })?;
        let _ = sock.set_nodelay(true);
        let conn = self.handshake(sock, cfg, name, host, timeout_ms)?;
        Ok(self.keep(conn))
    }

    fn tls_upgrade(
        &mut self,
        c: ConnId,
        host: &str,
        timeout_ms: u32,
        ca_pem: Option<&str>,
    ) -> Result<(), AppError> {
        let name = rustls_pki_types::ServerName::try_from(host.to_owned()).map_err(|_| {
            net_err(
                Status::InvalidParameter,
                format!("{host}: a DNS name or an IP literal"),
            )
        })?;
        let cfg = tls_config(ca_pem)?;
        self.sweep();
        let sock = match self.conns.remove(&c.0) {
            Some(Conn::Plain(s)) => s,
            Some(tls) => {
                self.conns.insert(c.0, tls);
                return Err(net_err(
                    Status::InvalidParameter,
                    "tls_upgrade: already TLS",
                ));
            }
            None => return Err(net_err(Status::NotFound, format!("no connection {}", c.0))),
        };
        let conn = self.handshake(sock, cfg, name, host, timeout_ms)?;
        self.conns.insert(c.0, conn);
        Ok(())
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
            s.sock()
                .set_write_timeout(Some(t))
                .map_err(|e| net_err(Status::InternalError, e.to_string()))?;
            match s.write(&data[off..]) {
                Ok(0) => return Err(net_err(Status::Disconnected, "send: connection closed")),
                Ok(n) => off += n,
                Err(e) if timed_out(&e) => return Err(net_err(Status::Timeout, "send: timeout")),
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(e) => return Err(net_err(Status::Disconnected, format!("send: {e}"))),
            }
        }
        // TLS: the last record goes out now, not with the next read
        let t = self.budget(u32::MAX)?;
        let s = self.conn(c)?;
        let _ = s.sock().set_write_timeout(Some(t));
        s.flush().map_err(|e| {
            let status = if timed_out(&e) {
                Status::Timeout
            } else {
                Status::Disconnected
            };
            net_err(status, format!("send: {e}"))
        })
    }

    fn tcp_recv(&mut self, c: ConnId, max: u32, timeout_ms: u32) -> Result<Vec<u8>, AppError> {
        let t = self.budget(timeout_ms)?;
        let s = self.conn(c)?;
        s.sock()
            .set_read_timeout(Some(t))
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

    fn close_all(&mut self) {
        self.conns.clear();
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
        // a name the list does not name, resolving to loopback: refused
        let e = s.tcp_connect("localhost", 502, 100).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        let e = s.tcp_connect("bad name!", 502, 100).unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter);
        assert_eq!(s.store_ready().unwrap_err().status, Status::NotSupported);
    }

    /// A TLS server on loopback for `localhost` that answers each read with it in capitals.
    fn tls_server() -> (u16, String) {
        let ck = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let ca = ck.cert.pem();
        let key = rustls_pki_types::PrivateKeyDer::Pkcs8(ck.signing_key.serialize_der().into());
        let cfg = Arc::new(
            rustls::ServerConfig::builder_with_provider(Arc::new(
                rustls::crypto::ring::default_provider(),
            ))
            .with_safe_default_protocol_versions()
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(vec![ck.cert.der().clone()], key)
            .unwrap(),
        );
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        std::thread::spawn(move || {
            for sock in l.incoming().flatten() {
                let cfg = cfg.clone();
                std::thread::spawn(move || {
                    let conn = rustls::ServerConnection::new(cfg).unwrap();
                    let mut t = rustls::StreamOwned::new(conn, sock);
                    let mut b = [0u8; 64];
                    while let Ok(n) = t.read(&mut b) {
                        if n == 0 || t.write_all(&b[..n].to_ascii_uppercase()).is_err() {
                            break;
                        }
                        let _ = t.flush();
                    }
                });
            }
        });
        (port, ca)
    }

    fn services(net: &str) -> RuntimeServices {
        RuntimeServices::new(
            Arc::new(Mutex::new(Store::none())),
            Vec::new(),
            NetPolicy::parse(net).unwrap(),
            Arc::new(Mutex::new(CallState {
                deadline: Some(Instant::now() + Duration::from_secs(5)),
                reset: false,
            })),
        )
    }

    #[test]
    fn tls_by_name_within_the_net_list() {
        let (port, ca) = tls_server();
        // a name never opens loopback by itself (DNS rebinding)
        let mut s = services(&format!("localhost:{port}"));
        let e = s
            .tls_connect("localhost", port, 2000, Some(&ca))
            .unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied, "{e}");
        // with a loopback entry: the handshake, then send and recv as plain TCP
        let mut s = services(&format!("localhost:{port}, 127.0.0.1:{port}"));
        let c = s.tls_connect("localhost", port, 2000, Some(&ca)).unwrap();
        s.tcp_send(c, b"hello").unwrap();
        assert_eq!(s.tcp_recv(c, 64, 2000).unwrap(), b"HELLO");
        s.tcp_close(c);
        // the certificate is for localhost: another name for the same address fails
        let e = s
            .tls_connect("127.0.0.1", port, 2000, Some(&ca))
            .unwrap_err();
        assert_eq!(e.status, Status::Disconnected, "{e}");
        // another CA: refused
        let (_, other) = tls_server();
        let e = s
            .tls_connect("localhost", port, 2000, Some(&other))
            .unwrap_err();
        assert_eq!(e.status, Status::Disconnected, "{e}");
        let e = s
            .tls_connect("localhost", port, 2000, Some("junk"))
            .unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter, "{e}");
        let e = s
            .tls_connect("bad host!", port, 2000, Some(&ca))
            .unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter, "{e}");
        // nothing listed for that port
        let e = s
            .tls_connect("localhost", port + 1, 2000, Some(&ca))
            .unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied, "{e}");
        // plain by name, then TLS on the same connection (as after an SSLRequest)
        let c = s.tcp_connect("localhost", port, 2000).unwrap();
        s.tls_upgrade(c, "localhost", 2000, Some(&ca)).unwrap();
        s.tcp_send(c, b"up").unwrap();
        assert_eq!(s.tcp_recv(c, 64, 2000).unwrap(), b"UP");
        let e = s.tls_upgrade(c, "localhost", 2000, Some(&ca)).unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter, "already TLS: {e}");
        // a wrong name on upgrade: refused, and the connection is gone
        let c = s.tcp_connect("127.0.0.1", port, 2000).unwrap();
        assert!(s.tls_upgrade(c, "other.example", 2000, Some(&ca)).is_err());
        assert_eq!(s.tcp_send(c, b"x").unwrap_err().status, Status::NotFound);
    }

    #[test]
    fn waits_end_with_the_call_and_close_all_closes() {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        let call = Arc::new(Mutex::new(CallState {
            deadline: Some(Instant::now() + Duration::from_millis(300)),
            reset: false,
        }));
        let mut s = RuntimeServices::new(
            Arc::new(Mutex::new(Store::none())),
            Vec::new(),
            NetPolicy::parse(&format!("127.0.0.1:{port}")).unwrap(),
            call.clone(),
        );
        let c = s.tcp_connect("127.0.0.1", port, 1000).unwrap();
        let (mut peer, _) = l.accept().unwrap();
        // the peer sends nothing: a 5 s wait ends with the call
        let t = Instant::now();
        let e = s.tcp_recv(c, 16, 5000).unwrap_err();
        assert_eq!(e.status, Status::Timeout, "{e}");
        assert!(
            t.elapsed() < Duration::from_millis(800),
            "{:?}",
            t.elapsed()
        );
        // the instance is gone: the peer sees the connection end
        s.close_all();
        peer.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        let mut b = [0u8; 4];
        assert_eq!(peer.read(&mut b).unwrap(), 0);
    }
}
