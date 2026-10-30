//! OPC UA client connector on the driver framework (ADR 0004), on
//! `async-opcua` (MPL-2.0, RustCrypto: no OpenSSL).
//!
//! Tree: `<conn>/<device>/<point>`. A connection is one session to an
//! endpoint (`opc.tcp://host:4840/path`) with a security policy and mode, a
//! user identity (anonymous, user name + password, X.509) and the
//! application instance certificate. A device is a group of nodes with an
//! optional namespace URI; a point is one node's Value attribute.
//!
//! The framework owns the tree, the generated actions, states, polling and
//! read-back writes. This crate does the protocol: batched Read requests
//! (at most the device's `max_nodes_per_read`, lowered to the server's
//! `MaxNodesPerRead`), Write with the server's data type, a ping that reads
//! `Server_ServerStatus_State` (i=2259), and the driver actions `browse`
//! (device) and `get_endpoints` (connection).
//!
//! Quality: only a `Good` status gives a value. `Uncertain` and `Bad` fail
//! the point (`bad/device_error`, last value kept): the framework has no
//! `uncertain` quality for a fresh value, and a non-Good status is never
//! shown as `good`. A Read request that times out answers
//! `DriverError::Device` for its points: when another request of the poll
//! answered, only those points take the ladder (`uncertain/stale`, then
//! `bad/comm_fail`); when none answered, it is a device miss. A lost
//! session fails the connection and the framework reopens it with its
//! backoff.
//!
//! Certificates live in the link's `data_dir` (see [`pki`]). The
//! [`Opcua`] link puts that directory in scope while connection params
//! are parsed, so each connection knows where its files are.

#![forbid(unsafe_code)]

pub mod conv;
pub mod pki;
mod session;
#[cfg(feature = "sim")]
pub mod sim;

pub use session::Transport;

use conv::NodeRef;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::Duration;
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, TypeCode, Value};
use wyrm_link_sdk::driver::params::ParamSpec;
use wyrm_link_sdk::driver::{
    Driver, DriverError, Framework, Level, Outcome, Params, PointId, Target, Tree,
};
use wyrm_link_sdk::{Caller, Link, LinkCtx, LinkError, ReplySink};

tokio::task_local! {
    /// The link's PKI directory while connection params are parsed.
    static PKI: Option<PathBuf>;
}

// ---------- parameters ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq, wyrm_link_sdk::ParamEnum)]
pub enum Policy {
    #[param(name = "None")]
    None,
    #[param(name = "Basic256Sha256")]
    Basic256Sha256,
    #[param(name = "Aes128_Sha256_RsaOaep")]
    Aes128Sha256RsaOaep,
    #[param(name = "Aes256_Sha256_RsaPss")]
    Aes256Sha256RsaPss,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, wyrm_link_sdk::ParamEnum)]
pub enum Mode {
    None,
    Sign,
    SignAndEncrypt,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, wyrm_link_sdk::ParamEnum)]
pub enum Identity {
    Anonymous,
    Username,
    Certificate,
}

/// The params of a connection as entered (see [`Conn`]).
#[derive(Clone, PartialEq, wyrm_link_sdk::Params)]
pub struct ConnParams {
    #[param(
        dest,
        display = "Endpoint URL",
        placeholder = "opc.tcp://plc1:4840/",
        desc = "opc.tcp://host:port/path"
    )]
    pub endpoint: String,
    #[param(enum, dest, default = "None", display = "Security Policy")]
    pub security_policy: Policy,
    #[param(enum, dest, default = "none", display = "Security Mode")]
    pub security_mode: Mode,
    #[param(enum, default = "anonymous", display = "User Identity")]
    pub identity: Identity,
    #[param(default = "", display = "User Name")]
    pub username: String,
    #[param(default = "", secret, display = "Password")]
    pub password: String,
    #[param(
        default = "",
        editor = "textarea",
        display = "User Certificate (PEM)",
        desc = "identity certificate: X.509 user token"
    )]
    pub user_cert_pem: String,
    #[param(default = "", secret, display = "User Key (PEM)")]
    pub user_key_pem: String,
    #[param(
        default = "",
        editor = "textarea",
        display = "Application Certificate (PEM)",
        desc = "empty: a self-signed one is made in the link's data_dir"
    )]
    pub cert_pem: String,
    #[param(default = "", secret, display = "Application Key (PEM)")]
    pub key_pem: String,
    #[param(
        default = "",
        dest,
        editor = "textarea",
        display = "Server Certificate (PEM)",
        desc = "pin: only this server certificate is trusted"
    )]
    pub server_cert_pem: String,
    #[param(
        default = false,
        dest,
        display = "Trust on First Use",
        desc = "trust the first server certificate seen, then only that one"
    )]
    pub trust_on_first_use: bool,
    #[param(default = "urn:wyrm:opcua:client", display = "Application URI")]
    pub application_uri: String,
    #[param(
        default = 60000,
        min = 10000,
        max = 3600000,
        display = "Session Timeout (ms)"
    )]
    pub session_timeout_ms: u32,
    #[param(
        default = 5000,
        min = 100,
        max = 60000,
        display = "Request Timeout (ms)"
    )]
    pub request_timeout_ms: u32,
    #[param(
        default = 15000,
        min = 1000,
        max = 120000,
        display = "Connect Timeout (ms)",
        desc = "bound on GetEndpoints + CreateSession + ActivateSession, and on a ping"
    )]
    pub connect_timeout_ms: u32,
}

/// Never prints a secret.
impl std::fmt::Debug for ConnParams {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConnParams")
            .field("endpoint", &self.endpoint)
            .field("security_policy", &self.security_policy)
            .field("security_mode", &self.security_mode)
            .field("identity", &self.identity)
            .finish_non_exhaustive()
    }
}

/// A connection: its params and the link's PKI directory (`None`: no
/// `data_dir`; only security None then).
#[derive(Debug, Clone, PartialEq)]
pub struct Conn {
    pub p: ConnParams,
    pub pki: Option<PathBuf>,
}

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

impl Params for Conn {
    fn schema() -> Vec<ParamSpec> {
        ConnParams::schema()
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let p = ConnParams::from_map(m)?;
        session::parse_endpoint(&p.endpoint).map_err(|e| bad("endpoint", e))?;
        if (p.security_policy == Policy::None) != (p.security_mode == Mode::None) {
            return Err(bad(
                "security_mode",
                "None goes with security policy None, Sign/SignAndEncrypt with the others",
            ));
        }
        match p.identity {
            Identity::Anonymous => {}
            Identity::Username if p.username.is_empty() => {
                return Err(bad("username", "required for identity username"))
            }
            Identity::Username => {}
            Identity::Certificate => {
                if p.user_cert_pem.is_empty() || p.user_key_pem.is_empty() {
                    return Err(bad(
                        "user_cert_pem",
                        "identity certificate needs user_cert_pem and user_key_pem",
                    ));
                }
                opcua::crypto::X509::from_pem(p.user_cert_pem.as_bytes())
                    .map_err(|_| bad("user_cert_pem", "not a PEM certificate"))?;
                opcua::crypto::PrivateKey::from_pem(p.user_key_pem.as_bytes())
                    .map_err(|_| bad("user_key_pem", "not a PEM RSA private key"))?;
            }
        }
        session::identity_allowed(p.identity, p.security_mode, &p.endpoint)
            .map_err(|e| bad("identity", e))?;
        if p.cert_pem.is_empty() != p.key_pem.is_empty() {
            return Err(bad("cert_pem", "cert_pem and key_pem go together"));
        }
        if !p.cert_pem.is_empty() {
            opcua::crypto::X509::from_pem(p.cert_pem.as_bytes())
                .map_err(|_| bad("cert_pem", "not a PEM certificate"))?;
            opcua::crypto::PrivateKey::from_pem(p.key_pem.as_bytes())
                .map_err(|_| bad("key_pem", "not a PEM RSA private key"))?;
        }
        if !p.server_cert_pem.is_empty() {
            opcua::crypto::X509::from_pem(p.server_cert_pem.as_bytes())
                .map_err(|_| bad("server_cert_pem", "not a PEM certificate"))?;
        }
        if !p.application_uri.contains(':') {
            return Err(bad("application_uri", "expected a URI (urn:…)"));
        }
        let pki = PKI.try_with(|d| d.clone()).ok().flatten();
        Ok(Conn { p, pki })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        self.p.to_map()
    }
}

/// Device parameters: a group of nodes on the connection.
#[derive(Debug, Clone, PartialEq, wyrm_link_sdk::Params)]
pub struct Dev {
    #[param(
        default = "",
        display = "Namespace URI",
        desc = "points without ns=/nsu= are in this namespace, found by URI on each connect"
    )]
    pub namespace_uri: String,
    #[param(
        default = 500,
        min = 1,
        max = 10000,
        display = "Max Nodes per Read",
        desc = "lowered to the server's MaxNodesPerRead"
    )]
    pub max_nodes_per_read: u32,
    #[param(default = 5.0, min = 0.1, max = 3600.0, display = "Ping Rate (s)")]
    pub ping_s: f64,
}

/// The params of a point as entered (see [`Point`]).
#[derive(Debug, Clone, PartialEq, wyrm_link_sdk::Params)]
pub struct PointParams {
    #[param(
        display = "Node ID",
        placeholder = "ns=2;s=Line1.Temp",
        desc = "ns=<n>;s=…, nsu=<uri>;i=…, or s=… in the device's namespace"
    )]
    pub node_id: String,
    #[param(default = 1.0, min = 0.01, max = 86400.0, display = "Poll Rate (s)")]
    pub poll_s: f64,
    #[param(default = false, display = "Writable")]
    pub writable: bool,
    #[param(default = 1.0, display = "Scaling")]
    pub scale: f64,
    #[param(default = 0.0, display = "Scaling Offset")]
    pub offset: f64,
    #[param(default = "", display = "Unit")]
    pub unit: String,
}

/// A point: its params and the parsed node id.
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    pub p: PointParams,
    pub node: NodeRef,
}

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        PointParams::schema()
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let p = PointParams::from_map(m)?;
        let node = conv::parse_node(&p.node_id).map_err(|e| bad("node_id", e))?;
        if p.scale == 0.0 {
            return Err(bad("scale", "must not be 0"));
        }
        Ok(Point { p, node })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        self.p.to_map()
    }
}

// ---------- driver ----------

/// The points of one `(device, poll period)` group.
pub struct Plan {
    points: Vec<(PointId, Point)>,
    chunks: usize,
}

/// Bound on `browse` and `get_endpoints`.
const ACTION_MS: u32 = 30_000;

pub struct OpcuaDriver;

impl Driver for OpcuaDriver {
    const NAME: &'static str = "opcua";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        Transport::open(conn).await
    }

    async fn ping(t: &mut Transport, _dev: &Dev) -> Result<(), DriverError> {
        t.ping().await
    }

    fn plan(dev: &Dev, points: &[(PointId, Point)]) -> Plan {
        let per = dev.max_nodes_per_read.max(1) as usize;
        Plan {
            points: points.to_vec(),
            chunks: points.len().div_ceil(per).max(1),
        }
    }

    async fn poll(
        t: &mut Transport,
        dev: &Dev,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        t.poll(dev, &plan.points).await
    }

    async fn write(
        t: &mut Transport,
        dev: &Dev,
        _id: &str,
        point: &Point,
        v: &Value,
    ) -> Result<(), DriverError> {
        if !point.p.writable {
            return Err(DriverError::Point("point is read-only".into()));
        }
        t.write(dev, point, v).await
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let scaled = p.p.scale != 1.0 || p.p.offset != 0.0;
        // The type comes from the server; a scaled point is a number.
        let mut m = if scaled {
            NodeMeta::number()
        } else {
            NodeMeta::leaf(TypeCode::Dynamic)
        }
        .writable(if p.p.writable {
            Writable::Write
        } else {
            Writable::Never
        });
        if !p.p.unit.is_empty() {
            m = m.unit(p.p.unit.clone());
        }
        m
    }

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.p.poll_s)
    }

    fn ping_period(dev: &Dev) -> Option<Duration> {
        Some(Duration::from_secs_f64(dev.ping_s))
    }

    fn io_timeout(conn: &Conn) -> Duration {
        Duration::from_millis(conn.p.connect_timeout_ms.into())
    }

    fn poll_timeout(conn: &Conn, plan: &Plan) -> Duration {
        let per = Duration::from_millis(u64::from(conn.p.request_timeout_ms) + 1000);
        per * plan.chunks as u32
    }

    fn write_timeout(conn: &Conn, _point: &Point) -> Duration {
        // the data type read, then the write
        Duration::from_millis(2 * u64::from(conn.p.request_timeout_ms) + 1000)
    }

    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        match level {
            Level::Device => vec![(
                "browse",
                ActionMeta::new()
                    .level(Perm::Read)
                    .display("Browse")
                    .timeout_ms(ACTION_MS)
                    .result(ActionResult::Type(TypeCode::Array))
                    .param(
                        "node",
                        ParamMeta {
                            default: Some(Value::Str("i=85".into())),
                            ..ParamMeta::of(TypeCode::String)
                                .display("Node ID")
                                .description("start node; i=85 is the Objects folder")
                        },
                    )
                    .param(
                        "depth",
                        ParamMeta {
                            default: Some(Value::UInt(1)),
                            ..ParamMeta::of(TypeCode::Number)
                                .display("Depth")
                                .description("levels below the node, 1…5")
                        },
                    )
                    .param(
                        "limit",
                        ParamMeta {
                            default: Some(Value::UInt(500)),
                            ..ParamMeta::of(TypeCode::Number)
                                .display("Limit")
                                .description("at most this many nodes, 1…5000")
                        },
                    ),
            )],
            Level::Connection => vec![(
                "get_endpoints",
                ActionMeta::new()
                    .level(Perm::Read)
                    .display("Get Endpoints")
                    .timeout_ms(ACTION_MS)
                    .result(ActionResult::Type(TypeCode::Array)),
            )],
        }
    }

    async fn invoke(
        t: &mut Transport,
        _conn: &Conn,
        target: Target<'_, Self>,
        action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        let empty = BTreeMap::new();
        let args = match args {
            Value::Map(m) => m,
            _ => &empty,
        };
        match (target, action) {
            (Target::Device { dev, .. }, "browse") => {
                let node = match args.get("node") {
                    None | Some(Value::Null) => "i=85".to_owned(),
                    Some(Value::Str(s)) => s.clone(),
                    Some(_) => return Err(bad("node", "expected a node id")),
                };
                let node = conv::parse_node(&node).map_err(|e| bad("node", e))?;
                let depth = arg_uint(args, "depth", 1, (1, 5))? as u32;
                let limit = arg_uint(args, "limit", 500, (1, 5000))? as usize;
                t.browse(dev, &node, depth, limit).await
            }
            (Target::Connection, "get_endpoints") => t.get_endpoints().await,
            _ => Err(LinkError::not_supported(format!("action {action}"))),
        }
    }

    const DIAGNOSTICS: bool = true;

    fn take_outcomes(t: &mut Transport) -> Vec<Outcome> {
        t.take_outcomes()
    }

    fn status_note(t: &Transport) -> Option<String> {
        t.note()
    }
}

/// A whole-number arg in `min..=max`, `default` when absent.
fn arg_uint(
    args: &BTreeMap<String, Value>,
    name: &str,
    default: u64,
    (min, max): (u64, u64),
) -> Result<u64, LinkError> {
    let n = match args.get(name) {
        None | Some(Value::Null) => default,
        Some(Value::UInt(n)) => *n,
        Some(Value::Float(f)) if f.fract() == 0.0 && *f >= 0.0 => *f as u64,
        Some(_) => return Err(bad(name, "expected a whole number")),
    };
    if n < min || n > max {
        return Err(bad(name, format!("{n} not in {min}…{max}")));
    }
    Ok(n)
}

// ---------- the link ----------

/// The `opcua` link: [`Framework`] running [`OpcuaDriver`], with the link's
/// PKI directory (`<data_dir>/opcua-pki`) in scope while connection params
/// are parsed (start, `add_connection`, `edit`, imports).
pub struct Opcua {
    inner: Framework<OpcuaDriver>,
    pki: Option<PathBuf>,
}

impl Link for Opcua {
    const NAME: &'static str = OpcuaDriver::NAME;
    const VERSION: &'static str = OpcuaDriver::VERSION;
    type Config = Tree;

    async fn start(tree: Tree, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        let pki = ctx.data_dir().map(session::pki_root);
        let inner = PKI
            .scope(
                pki.clone(),
                <Framework<OpcuaDriver> as Link>::start(tree, ctx),
            )
            .await?;
        Ok(Self { inner, pki })
    }

    async fn on_set(
        &mut self,
        path: &str,
        value: Value,
        who: &Caller,
    ) -> wyrm_link_sdk::Result<()> {
        PKI.scope(self.pki.clone(), self.inner.on_set(path, value, who))
            .await
    }

    async fn on_invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        who: &Caller,
        out: ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        PKI.scope(
            self.pki.clone(),
            self.inner.on_invoke(path, action, args, who, out),
        )
        .await
    }

    async fn stop(&mut self) {
        self.inner.stop().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    #[test]
    fn conn_rules() {
        let ok =
            Conn::from_value(&map(&[("endpoint", "opc.tcp://127.0.0.1:4840/".into())])).unwrap();
        assert_eq!(ok.p.security_policy, Policy::None);
        assert_eq!(ok.p.request_timeout_ms, 5000);
        assert_eq!(ok.pki, None, "outside a link: no PKI directory");
        for bad in [
            map(&[]),
            map(&[("endpoint", "http://x".into())]),
            map(&[("endpoint", "opc.tcp://".into())]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("security_policy", "Basic256Sha256".into()),
            ]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("security_mode", "sign".into()),
            ]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("identity", "username".into()),
            ]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("identity", "certificate".into()),
            ]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("cert_pem", "x".into()),
            ]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("server_cert_pem", "x".into()),
            ]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("request_timeout_ms", 50u64.into()),
            ]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("session_timeout_ms", 99_999_999u64.into()),
            ]),
            map(&[
                ("endpoint", "opc.tcp://h:1/".into()),
                ("application_uri", "nouri".into()),
            ]),
        ] {
            assert!(Conn::from_value(&bad).is_err(), "{bad:?}");
        }
        // a key's content never appears in an error
        let e = Conn::from_value(&map(&[
            ("endpoint", "opc.tcp://h:1/".into()),
            ("cert_pem", "not-a-cert".into()),
            ("key_pem", "very-private".into()),
        ]))
        .unwrap_err();
        assert!(!e.message.contains("very-private"), "{}", e.message);
        let c = Conn::from_value(&map(&[
            ("endpoint", "opc.tcp://127.0.0.1:1/".into()),
            ("identity", "username".into()),
            ("username", "u".into()),
            ("password", "pw-secret".into()),
        ]))
        .unwrap();
        assert!(!format!("{c:?}").contains("pw-secret"));
        assert!(!c
            .public_map()
            .values()
            .any(|v| *v == Value::from("pw-secret")));
    }

    #[tokio::test]
    async fn conn_takes_the_pki_directory_in_scope() {
        let v = map(&[("endpoint", "opc.tcp://h:1/".into())]);
        let c = PKI
            .scope(Some(PathBuf::from("/x/opcua-pki")), async {
                Conn::from_value(&v)
            })
            .await
            .unwrap();
        assert_eq!(c.pki, Some(PathBuf::from("/x/opcua-pki")));
    }

    #[test]
    fn point_rules() {
        let p = Point::from_value(&map(&[("node_id", "ns=2;s=a".into())])).unwrap();
        assert_eq!(p.p.poll_s, 1.0);
        assert_eq!(Point::from_value(&p.to_value()).unwrap(), p);
        for bad in [
            map(&[]),
            map(&[("node_id", "x".into())]),
            map(&[("node_id", "ns=2;s=a".into()), ("scale", 0.0.into())]),
            map(&[("node_id", "ns=2;s=a".into()), ("poll_s", 0.0.into())]),
        ] {
            assert!(Point::from_value(&bad).is_err(), "{bad:?}");
        }
        let meta = OpcuaDriver::point_meta(&p);
        assert_eq!(meta.ty, Some(TypeCode::Dynamic));
    }

    #[test]
    fn plans_count_chunks() {
        let dev = Dev::from_value(&map(&[("max_nodes_per_read", 2u64.into())])).unwrap();
        let p = Point::from_value(&map(&[("node_id", "i=1".into())])).unwrap();
        let pts: Vec<_> = (0..5).map(|i| (format!("p{i}"), p.clone())).collect();
        assert_eq!(OpcuaDriver::plan(&dev, &pts).chunks, 3);
        assert_eq!(OpcuaDriver::plan(&dev, &[]).chunks, 1);
        assert!(Dev::from_value(&map(&[("max_nodes_per_read", 0u64.into())])).is_err());
    }
}
