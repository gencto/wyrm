//! `wasm`: a framework driver (ADR 0004) whose points a WebAssembly
//! component reads and writes (`wyrm:link/driver`, ADR 0011, ADR 0012).
//!
//! A connection names its component by SHA-256: the admin keeps the entry
//! of each `wasm` package under `<root>/<sha256>.wasm` ([`set_component_root`]),
//! and the driver checks the hash when it loads it. The connection's `net`
//! list is the component's whole network (IP literals and ports); `config`
//! (JSON) goes to the component's `init`, a point's `cfg` (JSON) to its
//! `read`/`write`, both as canonical CBOR.
//!
//! The component's host calls block, so each connection runs its instance on
//! an OS thread of its own; the framework's owner task sends it the reads and
//! writes of a poll over a small channel.

use std::path::PathBuf;
use std::sync::mpsc::{sync_channel, SyncSender, TrySendError};
use std::sync::OnceLock;
use std::time::Duration;
use tokio::sync::oneshot;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, TypeCode, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, PointId};
use wyrm_link_sdk::Params;
use wyrm_wasm_host::{DriverWorld, Host, Limits, LinkDriver, NetPolicy, Slot};

static ROOT: OnceLock<PathBuf> = OnceLock::new();
static HOST: OnceLock<Result<Host, String>> = OnceLock::new();

/// Where the components are: `<root>/<sha256>.wasm`. Set once per process.
pub fn set_component_root(root: PathBuf) {
    let _ = ROOT.set(root);
}

fn host() -> Result<&'static Host, DriverError> {
    HOST.get_or_init(|| Host::new().map_err(|e| e.to_string()))
        .as_ref()
        .map_err(|e| DriverError::Transport(format!("wasm host: {e}")))
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct Conn {
    /// SHA-256 of the component (set by "Install Link ▸ from WASM").
    #[param(default = "", display = "Component")]
    pub component: String,
    /// Where the component may connect: `<ip>/<prefix>:<port>` or
    /// `<ip>:<port>`, separated by commas (ADR 0012). Empty: no network.
    #[param(
        default = "",
        dest,
        display = "Network",
        placeholder = "10.0.5.0/24:502"
    )]
    pub net: String,
    /// JSON given to the component's `init`.
    #[param(default = "{}", display = "Config", editor = "textarea")]
    pub config: String,
    /// Time of one component call, network included.
    #[param(default = 2000, min = 10, max = 10000, display = "Call ms")]
    pub call_ms: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct Dev {
    /// Only groups points; the component has no device ping.
    #[param(default = "", display = "Note")]
    pub note: String,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct Point {
    /// JSON given to the component's `read` and `write`.
    #[param(default = "{}", display = "Point config", editor = "textarea")]
    pub cfg: String,
    #[param(default = 1.0, min = 0.05, max = 3600.0, display = "Poll s")]
    pub poll_s: f64,
    #[param(default = false, display = "Writable")]
    pub writable: bool,
    #[param(default = "", display = "Unit")]
    pub unit: String,
}

enum Req {
    Read(
        Vec<(PointId, Vec<u8>)>,
        oneshot::Sender<Vec<(PointId, Result<Vec<u8>, String>)>>,
    ),
    Write(Vec<u8>, Vec<u8>, oneshot::Sender<Result<(), String>>),
}

/// The connection's instance thread.
pub struct Transport {
    tx: SyncSender<Req>,
}

/// JSON text → canonical CBOR of the matching `Value`.
fn json_cbor(what: &str, text: &str) -> Result<Vec<u8>, DriverError> {
    let j: serde_json::Value =
        serde_json::from_str(if text.trim().is_empty() { "{}" } else { text })
            .map_err(|e| DriverError::Point(format!("{what}: {e}")))?;
    wyrm_core::codec::to_vec(&json_value(&j))
        .map_err(|e| DriverError::Point(format!("{what}: {e}")))
}

fn json_value(j: &serde_json::Value) -> Value {
    match j {
        serde_json::Value::Null => Value::Null,
        serde_json::Value::Bool(b) => Value::Bool(*b),
        serde_json::Value::Number(n) => match (n.as_u64(), n.as_i64()) {
            (Some(u), _) => Value::UInt(u),
            (_, Some(i)) => Value::Int(i),
            _ => Value::Float(n.as_f64().unwrap_or(f64::NAN)),
        },
        serde_json::Value::String(s) => Value::Str(s.clone()),
        serde_json::Value::Array(a) => Value::Array(a.iter().map(json_value).collect()),
        serde_json::Value::Object(o) => {
            Value::Map(o.iter().map(|(k, v)| (k.clone(), json_value(v))).collect())
        }
    }
}

/// A reading: the `~val` payload `{0: v, 1: q, 2: t}` (its value), or a
/// bare value.
fn reading(b: &[u8]) -> Result<Value, DriverError> {
    if let Ok(s) = wyrm_core::codec::from_slice::<wyrm_core::Sample>(b) {
        return Ok(s.v);
    }
    wyrm_core::codec::from_slice::<Value>(b)
        .map_err(|e| DriverError::Point(format!("component reading: {e}")))
}

fn component_path(sha: &str) -> Result<PathBuf, DriverError> {
    if sha.len() != 64 || !sha.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(DriverError::Transport(
            "component: a SHA-256 (64 hex digits)".into(),
        ));
    }
    let root = ROOT
        .get()
        .ok_or_else(|| DriverError::Transport("no component store in this process".into()))?;
    Ok(root.join(format!("{}.wasm", sha.to_ascii_lowercase())))
}

/// Run the instance: init, then reads and writes until the transport drops.
fn serve(
    mut d: LinkDriver,
    rx: std::sync::mpsc::Receiver<Req>,
    started: oneshot::Sender<Result<(), String>>,
) {
    if let Err(e) = d.start() {
        let _ = started.send(Err(e.to_string()));
        return;
    }
    let _ = started.send(Ok(()));
    while let Ok(req) = rx.recv() {
        match req {
            Req::Read(points, reply) => {
                let out = points
                    .into_iter()
                    .map(|(id, cfg)| (id, d.read(&cfg).map_err(|e| e.to_string())))
                    .collect();
                let _ = reply.send(out);
            }
            Req::Write(cfg, value, reply) => {
                let _ = reply.send(d.write(&cfg, &value).map_err(|e| e.to_string()));
            }
        }
    }
}

impl Transport {
    fn send(&self, req: Req) -> Result<(), DriverError> {
        self.tx.try_send(req).map_err(|e| match e {
            TrySendError::Full(_) => DriverError::Device("component busy".into()),
            TrySendError::Disconnected(_) => DriverError::Transport("component stopped".into()),
        })
    }
}

pub struct Wasm;

impl Driver for Wasm {
    const NAME: &'static str = "wasm";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Vec<(PointId, Point)>;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let net = NetPolicy::parse(&conn.net).map_err(DriverError::Transport)?;
        let config =
            json_cbor("config", &conn.config).map_err(|e| DriverError::Transport(e.to_string()))?;
        let path = component_path(&conn.component)?;
        let bytes = std::fs::read(&path)
            .map_err(|e| DriverError::Transport(format!("component {}: {e}", conn.component)))?;
        let art = host()?
            .load::<DriverWorld>(&bytes)
            .map_err(|e| DriverError::Transport(e.to_string()))?;
        if !art.sha256().eq_ignore_ascii_case(&conn.component) {
            return Err(DriverError::Transport("component: hash mismatch".into()));
        }
        let call = Duration::from_millis(conn.call_ms.clamp(10, 10_000).into());
        let limits = Limits {
            time: call,
            ..Limits::LINK
        };
        let driver = LinkDriver::new(Slot::new(art), config, limits, net);
        let (tx, rx) = sync_channel(4);
        let (started, ready) = oneshot::channel();
        std::thread::Builder::new()
            .name("wyrm-wasm-link".into())
            .spawn(move || serve(driver, rx, started))
            .map_err(|e| DriverError::Transport(format!("thread: {e}")))?;
        match tokio::time::timeout(call + Duration::from_secs(1), ready).await {
            Ok(Ok(Ok(()))) => Ok(Transport { tx }),
            Ok(Ok(Err(e))) => Err(DriverError::Transport(format!("component init: {e}"))),
            _ => Err(DriverError::Transport("component init: no answer".into())),
        }
    }

    async fn ping(_t: &mut Transport, _dev: &Dev) -> Result<(), DriverError> {
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.to_vec()
    }

    async fn poll(
        t: &mut Transport,
        _dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let mut out = Vec::new();
        let mut ask = Vec::new();
        for (id, p) in plan {
            match json_cbor("cfg", &p.cfg) {
                Ok(cfg) => ask.push((id.clone(), cfg)),
                Err(e) => out.push((id.clone(), Err(e))),
            }
        }
        let (reply, answer) = oneshot::channel();
        if let Err(e) = t.send(Req::Read(ask.clone(), reply)) {
            out.extend(ask.into_iter().map(|(id, _)| (id, Err(e.clone()))));
            return out;
        }
        match answer.await {
            Ok(results) => out.extend(results.into_iter().map(|(id, r)| {
                let v = r.map_err(DriverError::Point).and_then(|b| reading(&b));
                (id, v)
            })),
            Err(_) => {
                let e = DriverError::Transport("component stopped".into());
                out.extend(ask.into_iter().map(|(id, _)| (id, Err(e.clone()))));
            }
        }
        out
    }

    async fn write(
        t: &mut Transport,
        _dev: &Dev,
        _id: &str,
        point: &Point,
        v: &Value,
    ) -> Result<(), DriverError> {
        let cfg = json_cbor("cfg", &point.cfg)?;
        let value = wyrm_core::codec::to_vec(v).map_err(|e| DriverError::Point(e.to_string()))?;
        let (reply, answer) = oneshot::channel();
        t.send(Req::Write(cfg, value, reply))?;
        answer
            .await
            .map_err(|_| DriverError::Transport("component stopped".into()))?
            .map_err(DriverError::Point)
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = NodeMeta::leaf(TypeCode::Dynamic).writable(if p.writable {
            Writable::Write
        } else {
            Writable::Never
        });
        if !p.unit.is_empty() {
            m = m.unit(p.unit.clone());
        }
        m
    }

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.poll_s)
    }

    fn ping_period(_dev: &Dev) -> Option<Duration> {
        None
    }

    /// A poll asks the component for each point in turn, each within the
    /// call time.
    fn io_timeout(conn: &Conn) -> Duration {
        Duration::from_millis(conn.call_ms.clamp(10, 10_000).into()) * 16 + Duration::from_secs(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn readings_and_json() {
        assert_eq!(reading(&[0xa3, 0, 7, 1, 0, 2, 0]).unwrap(), Value::UInt(7));
        assert_eq!(reading(&[0x05]).unwrap(), Value::UInt(5));
        assert!(reading(&[0xff]).is_err());
        let b = json_cbor("cfg", r#"{"reg": 3, "name": "t"}"#).unwrap();
        let v: Value = wyrm_core::codec::from_slice(&b).unwrap();
        assert!(matches!(v, Value::Map(m) if m["reg"] == Value::UInt(3)));
        assert!(json_cbor("cfg", "{bad").is_err());
        assert!(component_path("abc").is_err());
    }
}
