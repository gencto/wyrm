//! An OPC UA server for tests and demos (the `async-opcua` server), and a
//! TCP relay in front of it that can go silent, slow or drop connections.
//!
//! Variables in namespace [`NS`], in the folder `Line1` under Objects
//! (`ns=<i>;s=Line1.<name>`):
//!
//! | name | type | |
//! |---|---|---|
//! | `Double` | Double | changes every 100 ms (counts up by 1) |
//! | `Int32` | Int32 | 42 |
//! | `Boolean` | Boolean | true |
//! | `String` | String | "hello" |
//! | `Array` | Double[] | [1, 2, 3] |
//! | `Time` | DateTime | 2026-10-30T12:00:00Z |
//! | `Bytes` | ByteString | [1, 2, 3] |
//! | `Setpoint` | Double | writable |
//! | `Small` | Int16 | writable |
//! | `Text` | String | writable |
//! | `Flags` | Int32[] | writable |
//! | `Locked` | Double | read-only on the server |
//! | `Bad` | Double | every read answers BadSensorFailure |
//! | `Uncertain` | Double | 5.0 with UncertainLastUsableValue |
//! | `Slow` | Double | 7.0; a read waits [`Sim::set_slow`] first |
//! | `Matrix` | Double, ValueRank 2 | writable |
//!
//! `Line1` also has a HasComponent reference to `Int32` (two hierarchical
//! references to one node).
//!
//! Endpoints at `/`: None, Basic256Sha256 Sign and SignAndEncrypt, with
//! anonymous, user [`USER`]/[`PASSWORD`] and (optionally) an X.509 user.

use opcua::crypto::{CertificateStore, SecurityPolicy, X509Data};
use opcua::server::address_space::{AccessLevel, VariableBuilder};
use opcua::server::diagnostics::NamespaceMetadata;
use opcua::server::node_manager::memory::{simple_node_manager, SimpleNodeManager};
use opcua::server::{ServerBuilder, ServerHandle, ServerUserToken, ANONYMOUS_USER_TOKEN_ID};
use opcua::types::{
    ByteString, DataTypeId, DataValue, DateTime, MessageSecurityMode, NodeId, ObjectId,
    ReferenceTypeId, StatusCode, Variant,
};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinHandle;

/// The simulator's namespace URI.
pub const NS: &str = "urn:wyrm:opcua-sim:data";
/// A namespace registered before [`NS`] when [`Options::extra_namespace`]
/// is set, so that [`NS`] gets another index.
pub const EXTRA_NS: &str = "urn:wyrm:opcua-sim:extra";
pub const USER: &str = "operator";
pub const PASSWORD: &str = "sim-password";
/// The user of the X.509 identity.
pub const X509_USER: &str = "x509-operator";
/// The simulator's application URI.
pub const APP_URI: &str = "urn:wyrm:opcua-sim";

/// How to start a simulator.
#[derive(Debug, Clone, Default)]
pub struct Options {
    /// `0`: any free port.
    pub port: u16,
    /// The server's own certificate and trust lists (made when missing).
    pub pki_dir: PathBuf,
    /// Register [`EXTRA_NS`] first (namespace indexes shift).
    pub extra_namespace: bool,
    /// The server's MaxNodesPerRead (`0`: the library's default).
    pub max_nodes_per_read: usize,
    /// Refuse client certificates it does not know (default: trust all).
    pub strict_clients: bool,
    /// An X.509 user certificate (DER or PEM file) for [`X509_USER`].
    pub x509_user: Option<PathBuf>,
    /// Cap on secure channel token lifetimes (`0`: the library's default),
    /// so that clients renew their channel often.
    pub channel_lifetime_ms: u32,
}

/// A running simulator.
pub struct Sim {
    pub addr: SocketAddr,
    pub handle: ServerHandle,
    nm: Arc<SimpleNodeManager>,
    /// How long a read of `Slow` waits (ms).
    slow_ms: Arc<AtomicU64>,
    /// The index of [`NS`].
    pub ns: u16,
    pki_dir: PathBuf,
    tasks: Vec<JoinHandle<()>>,
}

impl Drop for Sim {
    fn drop(&mut self) {
        self.handle.cancel();
        for t in &self.tasks {
            t.abort();
        }
    }
}

/// The server certificate: SANs for the application URI, `localhost` and
/// `127.0.0.1`, so that a client checking host names accepts it.
pub fn ensure_server_cert(pki_dir: &Path) -> Result<(), String> {
    let cert = pki_dir.join("own/cert.der");
    let key = pki_dir.join("private/private.pem");
    if cert.is_file() && key.is_file() {
        return Ok(());
    }
    let alt = X509Data::alt_host_names(
        APP_URI,
        Some(vec!["localhost".into(), "127.0.0.1".into()]),
        false,
        false,
        false,
    );
    let data = X509Data {
        key_size: 2048,
        common_name: "WYRM OPC UA Simulator".into(),
        organization: "WYRM".into(),
        organizational_unit: String::new(),
        country: String::new(),
        state: String::new(),
        alt_host_names: alt,
        certificate_duration_days: 3650,
    };
    CertificateStore::create_certificate_and_key(&data, true, &cert, &key).map(|_| ())
}

fn var(id: &NodeId, name: &str) -> VariableBuilder {
    VariableBuilder::new(id, name, name)
}

/// Start a simulator on `127.0.0.1`.
pub async fn spawn(opts: Options) -> std::io::Result<Sim> {
    let err = |e: String| std::io::Error::other(e);
    let pki = opts.pki_dir.clone();
    tokio::task::spawn_blocking(move || ensure_server_cert(&pki))
        .await
        .map_err(|e| err(e.to_string()))?
        .map_err(err)?;
    let listener = TcpListener::bind(("127.0.0.1", opts.port)).await?;
    let addr = listener.local_addr()?;
    let users: [&str; 3] = [ANONYMOUS_USER_TOKEN_ID, "user", "x509"];
    let users: &[&str] = if opts.x509_user.is_some() {
        &users
    } else {
        &users[..2]
    };
    let mut b = ServerBuilder::new()
        .application_name("WYRM OPC UA Simulator")
        .application_uri(APP_URI)
        .product_uri("urn:wyrm:opcua-sim")
        .create_sample_keypair(false)
        .pki_dir(opts.pki_dir.clone())
        .certificate_path("own/cert.der")
        .private_key_path("private/private.pem")
        .trust_client_certs(!opts.strict_clients)
        .host("127.0.0.1")
        .port(addr.port())
        .discovery_urls(vec![format!("opc.tcp://127.0.0.1:{}/", addr.port())])
        .add_user_token("user", ServerUserToken::user_pass(USER, PASSWORD))
        .add_endpoint(
            "none",
            ("/", SecurityPolicy::None, MessageSecurityMode::None, users),
        )
        .add_endpoint(
            "b256_sign",
            (
                "/",
                SecurityPolicy::Basic256Sha256,
                MessageSecurityMode::Sign,
                users,
            ),
        )
        .add_endpoint(
            "b256_encrypt",
            (
                "/",
                SecurityPolicy::Basic256Sha256,
                MessageSecurityMode::SignAndEncrypt,
                users,
            ),
        );
    if let Some(path) = &opts.x509_user {
        b = b.add_user_token("x509", ServerUserToken::x509(X509_USER, path));
    }
    if opts.channel_lifetime_ms > 0 {
        b = b.max_secure_channel_token_lifetime_ms(opts.channel_lifetime_ms);
    }
    if opts.max_nodes_per_read > 0 {
        b.limits_mut().operational.max_nodes_per_read = opts.max_nodes_per_read;
    }
    if opts.extra_namespace {
        b = b.with_node_manager(simple_node_manager(
            NamespaceMetadata {
                namespace_uri: EXTRA_NS.into(),
                ..Default::default()
            },
            "extra",
        ));
    }
    b = b.with_node_manager(simple_node_manager(
        NamespaceMetadata {
            namespace_uri: NS.into(),
            ..Default::default()
        },
        "sim",
    ));
    let (server, handle) = b.build().map_err(err)?;
    let run = tokio::spawn(async move {
        if let Err(e) = server.run_with(listener).await {
            tracing::warn!("opc ua sim: {e}");
        }
    });
    // The node managers are ready once the server runs.
    let nm = loop {
        if let Some(nm) = handle
            .node_managers()
            .get_by_name::<SimpleNodeManager>("sim")
        {
            if handle.get_namespace_index(NS).is_some() {
                break nm;
            }
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    };
    let ns = handle
        .get_namespace_index(NS)
        .ok_or_else(|| err("namespace not registered".into()))?;
    let id = |name: &str| NodeId::new(ns, format!("Line1.{name}"));
    let folder = NodeId::new(ns, "Line1");
    {
        let mut a = nm.address_space().write();
        a.add_folder(&folder, "Line1", "Line1", &ObjectId::ObjectsFolder.into());
        let t = DateTime::parse_from_rfc3339("2026-10-30T12:00:00Z")
            .unwrap_or_else(|_| DateTime::now());
        let vars = [
            var(&id("Double"), "Double")
                .data_type(DataTypeId::Double)
                .value(0.0f64),
            var(&id("Int32"), "Int32")
                .data_type(DataTypeId::Int32)
                .value(42i32),
            var(&id("Boolean"), "Boolean")
                .data_type(DataTypeId::Boolean)
                .value(true),
            var(&id("String"), "String")
                .data_type(DataTypeId::String)
                .value("hello"),
            var(&id("Array"), "Array")
                .data_type(DataTypeId::Double)
                .value_rank(1)
                .value(vec![1.0f64, 2.0, 3.0]),
            var(&id("Time"), "Time")
                .data_type(DataTypeId::DateTime)
                .value(t),
            var(&id("Bytes"), "Bytes")
                .data_type(DataTypeId::ByteString)
                .value(ByteString::from(vec![1u8, 2, 3])),
            var(&id("Setpoint"), "Setpoint")
                .data_type(DataTypeId::Double)
                .value(0.0f64)
                .writable(),
            var(&id("Small"), "Small")
                .data_type(DataTypeId::Int16)
                .value(0i16)
                .writable(),
            var(&id("Text"), "Text")
                .data_type(DataTypeId::String)
                .value("")
                .writable(),
            var(&id("Flags"), "Flags")
                .data_type(DataTypeId::Int32)
                .value_rank(1)
                .value(vec![0i32, 0])
                .writable(),
            var(&id("Locked"), "Locked")
                .data_type(DataTypeId::Double)
                .value(1.0f64)
                .access_level(AccessLevel::CURRENT_READ)
                .user_access_level(AccessLevel::CURRENT_READ),
            var(&id("Bad"), "Bad")
                .data_type(DataTypeId::Double)
                .value(0.0f64),
            var(&id("Uncertain"), "Uncertain")
                .data_type(DataTypeId::Double)
                .value(5.0f64),
            var(&id("Slow"), "Slow")
                .data_type(DataTypeId::Double)
                .value(7.0f64),
            var(&id("Matrix"), "Matrix")
                .data_type(DataTypeId::Double)
                .value_rank(2)
                .value(vec![1.0f64, 2.0, 3.0, 4.0])
                .writable(),
        ];
        for v in vars {
            v.organized_by(folder.clone()).insert(&mut *a);
        }
        // a second hierarchical reference to one node (browse lists it once)
        a.insert_reference(&folder, &id("Int32"), ReferenceTypeId::HasComponent);
    }
    nm.inner()
        .add_read_callback(id("Bad"), |_, _, _| Err(StatusCode::BadSensorFailure));
    nm.inner().add_read_callback(id("Uncertain"), |_, _, _| {
        Ok(DataValue {
            value: Some(Variant::Double(5.0)),
            status: Some(StatusCode::UncertainLastUsableValue),
            ..Default::default()
        })
    });
    let slow_ms = Arc::new(AtomicU64::new(0));
    {
        let slow_ms = slow_ms.clone();
        // A blocking wait inside the server's read task: the Read request
        // that holds `Slow` answers late, the others of the session do not.
        nm.inner().add_read_callback(id("Slow"), move |_, _, _| {
            let ms = slow_ms.load(Ordering::SeqCst);
            if ms > 0 {
                std::thread::sleep(Duration::from_millis(ms));
            }
            Ok(DataValue::new_now(7.0f64))
        });
    }
    let ticker = {
        let nm = nm.clone();
        let subs = handle.subscriptions().clone();
        let dbl = id("Double");
        tokio::spawn(async move {
            let mut n = 0.0f64;
            loop {
                tokio::time::sleep(Duration::from_millis(100)).await;
                n += 1.0;
                let _ = nm.set_value(&subs, &dbl, None, DataValue::new_now(n));
            }
        })
    };
    Ok(Sim {
        addr,
        handle,
        nm,
        slow_ms,
        ns,
        pki_dir: opts.pki_dir,
        tasks: vec![run, ticker],
    })
}

impl Sim {
    /// `opc.tcp://127.0.0.1:<port>/`
    pub fn url(&self) -> String {
        format!("opc.tcp://127.0.0.1:{}/", self.addr.port())
    }

    /// The node id of variable `name` (`ns=<i>;s=Line1.<name>`).
    pub fn node(&self, name: &str) -> NodeId {
        NodeId::new(self.ns, format!("Line1.{name}"))
    }

    /// The value of variable `name` on the server.
    pub fn get(&self, name: &str) -> Option<Variant> {
        let a = self.nm.address_space().read();
        let node = a.find(&self.node(name))?;
        match node {
            opcua::server::address_space::NodeType::Variable(v) => {
                v.value(
                    opcua::types::TimestampsToReturn::Neither,
                    &Default::default(),
                    &Default::default(),
                    0.0,
                )
                .value
            }
            _ => None,
        }
    }

    /// Set variable `name` on the server.
    pub fn set(&self, name: &str, v: impl Into<Variant>) {
        let _ = self.nm.set_value(
            self.handle.subscriptions(),
            &self.node(name),
            None,
            DataValue::new_now(v.into()),
        );
    }

    /// Make every read of `Slow` wait `d` before it answers (a slow
    /// backend behind one node); `Duration::ZERO` answers at once.
    pub fn set_slow(&self, d: Duration) {
        let ms = u64::try_from(d.as_millis()).unwrap_or(u64::MAX);
        self.slow_ms.store(ms, Ordering::SeqCst);
    }

    /// Remove variable `name` (failure mode: a node removed).
    pub fn remove(&self, name: &str) {
        self.nm
            .address_space()
            .write()
            .delete(&self.node(name), true);
    }

    /// The server certificate as PEM (to pin it).
    pub fn certificate_pem(&self) -> String {
        let der = std::fs::read(self.pki_dir.join("own/cert.der")).unwrap_or_default();
        pem("CERTIFICATE", &der)
    }

    /// Client certificates the server refused (`strict_clients`).
    pub fn rejected_clients(&self) -> usize {
        std::fs::read_dir(self.pki_dir.join("rejected"))
            .map(|d| d.count())
            .unwrap_or(0)
    }

    /// Trust every client certificate the server refused (an operator
    /// moving them from `rejected/` to `trusted/`).
    pub fn trust_rejected_clients(&self) {
        let (rejected, trusted) = (self.pki_dir.join("rejected"), self.pki_dir.join("trusted"));
        let _ = std::fs::create_dir_all(&trusted);
        for e in std::fs::read_dir(&rejected).into_iter().flatten().flatten() {
            let _ = std::fs::rename(e.path(), trusted.join(e.file_name()));
        }
    }

    /// Stop the server (failure mode: server stop); start a new one on the
    /// same port with [`spawn`] and `Options::port`.
    pub async fn stop(mut self) {
        self.handle.cancel();
        for t in self.tasks.drain(..) {
            t.abort();
            let _ = t.await;
        }
    }
}

pub use crate::pki::pem;

// ---------- relay ----------

/// What the relay does with traffic.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RelayMode {
    /// Forward both ways.
    Pass,
    /// Keep connections open, forward nothing (a silent server).
    Silent,
    /// Close every connection and refuse new ones (a server gone).
    Drop,
}

impl RelayMode {
    /// The mode as kept in an atomic.
    const fn code(self) -> u8 {
        match self {
            RelayMode::Pass => 0,
            RelayMode::Silent => 1,
            RelayMode::Drop => 2,
        }
    }

    fn load(a: &AtomicU8) -> RelayMode {
        match a.load(Ordering::SeqCst) {
            1 => RelayMode::Silent,
            2 => RelayMode::Drop,
            _ => RelayMode::Pass,
        }
    }
}

/// A TCP relay to a simulator, for failure modes the server has no switch
/// for.
pub struct Relay {
    pub addr: SocketAddr,
    mode: Arc<AtomicU8>,
    delay_ms: Arc<AtomicU64>,
    hide_limit: Arc<AtomicBool>,
    conns: Arc<Mutex<Vec<JoinHandle<()>>>>,
    task: JoinHandle<()>,
}

/// `i=11705` (Server_ServerCapabilities_OperationLimits_MaxNodesPerRead) as
/// a four-byte NodeId in a request, and the unknown `i=65535` of the same
/// length.
const LIMIT_NODE: [u8; 4] = [0x01, 0x00, 0xB9, 0x2D];
const NO_NODE: [u8; 4] = [0x01, 0x00, 0xFF, 0xFF];

impl Drop for Relay {
    fn drop(&mut self) {
        self.task.abort();
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

impl Relay {
    /// `opc.tcp://127.0.0.1:<relay port>/`
    pub fn url(&self) -> String {
        format!("opc.tcp://127.0.0.1:{}/", self.addr.port())
    }

    pub fn set_mode(&self, m: RelayMode) {
        self.mode.store(m.code(), Ordering::SeqCst);
        if m == RelayMode::Drop {
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

    /// While set, a client's read of `MaxNodesPerRead` (i=11705) asks for a
    /// node that does not exist, so the client learns no limit, while the
    /// server still enforces its own: a server that does not publish the
    /// limit it enforces. Security None only (the relay rewrites the
    /// plain request bytes).
    pub fn set_hide_read_limit(&self, on: bool) {
        self.hide_limit.store(on, Ordering::SeqCst);
    }

    /// Hold every chunk this long before forwarding it (slow replies).
    pub fn set_delay(&self, d: Duration) {
        let ms = u64::try_from(d.as_millis()).unwrap_or(u64::MAX);
        self.delay_ms.store(ms, Ordering::SeqCst);
    }
}

/// Start a relay on `127.0.0.1` to `upstream`.
pub async fn relay(upstream: SocketAddr) -> std::io::Result<Relay> {
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let addr = listener.local_addr()?;
    let mode = Arc::new(AtomicU8::new(RelayMode::Pass.code()));
    let delay_ms = Arc::new(AtomicU64::new(0));
    let hide_limit = Arc::new(AtomicBool::new(false));
    let conns: Arc<Mutex<Vec<JoinHandle<()>>>> = Arc::default();
    let task = {
        let (mode, delay_ms, conns) = (mode.clone(), delay_ms.clone(), conns.clone());
        let hide_limit = hide_limit.clone();
        tokio::spawn(async move {
            loop {
                let Ok((client, _)) = listener.accept().await else {
                    return;
                };
                if RelayMode::load(&mode) == RelayMode::Drop {
                    drop(client);
                    continue;
                }
                let Ok(server) = TcpStream::connect(upstream).await else {
                    continue;
                };
                let (cr, cw) = client.into_split();
                let (sr, sw) = server.into_split();
                let up = tokio::spawn(pump(
                    cr,
                    sw,
                    mode.clone(),
                    delay_ms.clone(),
                    Some(hide_limit.clone()),
                ));
                let down = tokio::spawn(pump(sr, cw, mode.clone(), delay_ms.clone(), None));
                let both = tokio::spawn(async move {
                    let up = AbortGuard(up);
                    let down = AbortGuard(down);
                    let _ = tokio::join!(wait(&up), wait(&down));
                });
                let mut c = conns.lock().unwrap_or_else(|p| p.into_inner());
                c.retain(|h| !h.is_finished());
                c.push(both);
            }
        })
    };
    Ok(Relay {
        addr,
        mode,
        delay_ms,
        hide_limit,
        conns,
        task,
    })
}

struct AbortGuard(JoinHandle<()>);

impl Drop for AbortGuard {
    fn drop(&mut self) {
        self.0.abort();
    }
}

async fn wait(g: &AbortGuard) {
    while !g.0.is_finished() {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

async fn pump(
    mut from: tokio::net::tcp::OwnedReadHalf,
    mut to: tokio::net::tcp::OwnedWriteHalf,
    mode: Arc<AtomicU8>,
    delay_ms: Arc<AtomicU64>,
    hide_limit: Option<Arc<AtomicBool>>,
) {
    let mut buf = vec![0u8; 64 * 1024];
    loop {
        let n = match from.read(&mut buf).await {
            Ok(0) | Err(_) => return,
            Ok(n) => n,
        };
        let d = delay_ms.load(Ordering::SeqCst);
        if d > 0 {
            tokio::time::sleep(Duration::from_millis(d)).await;
        }
        match RelayMode::load(&mode) {
            RelayMode::Silent => continue,
            RelayMode::Drop => return,
            RelayMode::Pass => {}
        }
        if hide_limit
            .as_ref()
            .is_some_and(|h| h.load(Ordering::SeqCst))
        {
            let chunk = &mut buf[..n];
            let mut i = 0;
            while i + LIMIT_NODE.len() <= chunk.len() {
                if chunk[i..i + LIMIT_NODE.len()] == LIMIT_NODE {
                    chunk[i..i + LIMIT_NODE.len()].copy_from_slice(&NO_NODE);
                    i += LIMIT_NODE.len();
                } else {
                    i += 1;
                }
            }
        }
        if to.write_all(&buf[..n]).await.is_err() {
            return;
        }
    }
}
