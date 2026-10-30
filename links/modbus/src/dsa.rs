//! `import_dsa` (root action, `config`): the Modbus tree of a
//! `dslink-java-modbus` `nodes.json` (commit `0745d7d`) as our connections,
//! devices, folders and points, with a report of what could not be mapped.
//! The framework imports the result like `import` (checked before anything
//! changes, every connection stopped, P18).
//!
//! The file is what the DSA Java SDK serializer writes: the link's children
//! by name (`%XX`-encoded), each an object with `$…` configs, `@…`
//! attributes and its children. Attributes are also read without `@`, and
//! numbers also as strings (`Util.getIntValue`). The input is the whole file
//! or one connection's DSA export (the node without its name: `name`
//! required). Sources of each attribute: `tests/fixtures/dsa-nodes.md`.
//!
//! * Scaling: DSA shows `raw / scaling + scaling offset` (`SlaveNode.java:326`),
//!   we `raw × scale + offset`, so `scale = 1 / scaling` and `offset =
//!   scaling offset`; `scaling = 0` refuses the point. A write takes the
//!   exact inverse `(value − offset) / scale` (DSA writes `value × scaling −
//!   scaling offset`, `SlaveFolder.java:640`). Booleans and text ignore
//!   scaling, as in DSA. `offset` (the DSA register address) is `addr`.
//! * Times: `polling interval` and `suppress non-cov update duration` are
//!   stored in ms. The interval (per device in DSA) becomes `poll_s` on each
//!   point; the suppress duration `republish_s` (DSA 0 = publish on every
//!   poll: half the interval here, so every poll republishes).
//! * Per connection in DSA, per device here: `max read register count` →
//!   `max_regs`, `max read bit count` → `max_bits`; `use batch polling`
//!   false → both 1 (each point read alone).
//! * Not working as imported (`disabled`, node enabled false): UDP (as TCP)
//!   and ASCII (as RTU) transports and parity MARK/SPACE (as none), ruling
//!   14; 1.5 stop bits (as 1); unit 0 on a serial connection (P3).
//! * Not carried (`dropped`): `zero on failed poll` set (ruling 14: quality
//!   says it), `discard data delay` above 0, `max write register count` (we
//!   write up to 123 registers in one request), values outside our bounds
//!   (clamped), nodes DSA itself does not load, local slaves.
//! * Ignored as runtime state or copies: `$is`, `$type`, `?value`,
//!   `$writable`, the `Connection Status` / `Device Status` leaves, and the
//!   connection's attributes that a serial device repeats.
//! * Names: decoded, characters outside `[A-Za-z0-9_.-]` become `_`; a name
//!   our tree reserves, or one taken (a point id is unique on its device,
//!   folders included), gets `_2`, `_3`…; `renamed` lists every change.
//!   Folders deeper than [`MAX_FOLDER_DEPTH`] go into the deepest one.

use crate::codec::DType;
use crate::{Conn, Device, Point};
use serde_json::{Map as JsonMap, Value as Json};
use std::collections::{BTreeMap, BTreeSet};
use wyrm_core::meta::{ActionResult, ParamMeta, EDITOR_TEXTAREA};
use wyrm_core::{ActionMeta, Perm, TypeCode, Value};
use wyrm_link_sdk::driver::branch::{self, Level, Node};
use wyrm_link_sdk::driver::framework::MAX_FOLDER_DEPTH;
use wyrm_link_sdk::driver::{Converted, Params};
use wyrm_link_sdk::LinkError;

/// The root action.
pub const ACTION: &str = "import_dsa";

// Attribute names (`ModbusConnection.java:38-65`, `IpConnection.java:25-27`,
// `SerialConn.java:29-32`, `SlaveFolder.java:52-66`).
const RESTORE_TYPE: &str = "restoreType";
const TRANSPORT: &str = "transport type";
const HOST: &str = "host";
const PORT: &str = "port";
const COMM_PORT: &str = "comm port id";
const COMM_PORT_MANUAL: &str = "comm port id (manual entry)";
const BAUD: &str = "baud rate";
const DATA_BITS: &str = "data bits";
const STOP_BITS: &str = "stop bits";
const PARITY: &str = "parity";
const TIMEOUT: &str = "Timeout";
const RETRIES: &str = "retries";
const MAX_BITS: &str = "max read bit count";
const MAX_REGS: &str = "max read register count";
const MAX_WRITE: &str = "max write register count";
const DISCARD: &str = "discard data delay";
const MULTI_WRITE: &str = "use multiple write commands";
const MULTI_WRITE_ONLY: &str = "use multiple write commands only";
const SLAVE_ID: &str = "slave id";
const INTERVAL: &str = "polling interval";
const ZERO_FAIL: &str = "zero on failed poll";
const BATCH: &str = "use batch polling";
const CONTIGUOUS: &str = "contiguous batch requests only";
const SUPPRESS: &str = "suppress non-cov update duration";
const TYPE: &str = "type";
const OFFSET: &str = "offset";
const REGS: &str = "number of registers";
const DATA_TYPE: &str = "data type";
const BIT: &str = "bit";
const SCALING: &str = "scaling";
const SCALING_OFFSET: &str = "scaling offset";
const WRITABLE: &str = "writable";
/// Status leaves (`ModbusConnection.java:67`, `SlaveFolder.java:68`).
const STATUS_LEAVES: [&str; 2] = ["Connection Status", "Device Status"];

/// Names our tree keeps for itself: the status and diagnostics leaves of
/// connections and devices, and the framework's action names (a folder may
/// not take one). `folders_kept` imports each through the link.
const RESERVED: &[&str] = &[
    "status",
    "error",
    "requests",
    "errors",
    "timeouts",
    "exceptions",
    "reopens",
    "last_rtt_ms",
    "avg_rtt_ms",
    "edit",
    "remove",
    "restart",
    "start",
    "stop",
    "export",
    "rescan",
    "copy",
    "import",
];

/// `import_dsa {json, name?}` → `{created, dropped, disabled, renamed,
/// reenter}`.
pub fn form() -> ActionMeta {
    ActionMeta::new()
        .level(Perm::Config)
        .display("Import from DSA")
        .param(
            "json",
            ParamMeta::of(TypeCode::String)
                .required(true)
                .display("JSON")
                .editor(EDITOR_TEXTAREA)
                .description("nodes.json of dslink-java-modbus, or the export of one connection"),
        )
        .param(
            "name",
            ParamMeta::of(TypeCode::String)
                .required(false)
                .display("Name")
                .description("Name of the connection (required for the export of one)"),
        )
        .timeout_ms(branch::ACTION_MS)
        .result(ActionResult::Type(TypeCode::Map))
}

/// The action's args (`json`, `name?`) through [`convert`].
pub fn convert_args(args: &Value) -> Result<Converted, LinkError> {
    let Value::Map(m) = args else {
        return Err(LinkError::invalid_parameter("expected {json, name?}"));
    };
    let Some(Value::Str(text)) = m.get("json") else {
        return Err(LinkError::invalid_parameter("json: required"));
    };
    let name = match m.get("name") {
        None | Some(Value::Null) => None,
        Some(Value::Str(s)) if s.is_empty() => None,
        Some(Value::Str(s)) => Some(s.as_str()),
        Some(_) => return Err(LinkError::invalid_parameter("name: expected a string")),
    };
    convert(text, name)
}

/// Convert DSA `text`; `name` names the connection (the export of one
/// connection needs it; a whole file must then hold exactly one).
pub fn convert(text: &str, name: Option<&str>) -> Result<Converted, LinkError> {
    if text.len() > branch::MAX_BYTES {
        return Err(LinkError::invalid_parameter(format!(
            "json: more than {} bytes",
            branch::MAX_BYTES
        )));
    }
    let j: Json = serde_json::from_str(text)
        .map_err(|e| LinkError::invalid_parameter(format!("json: {e}")))?;
    let Json::Object(root) = j else {
        return Err(LinkError::invalid_parameter(
            "json: expected a DSA nodes.json object",
        ));
    };
    let root = Dsa(&root);
    let mut cv = Conv::default();
    let tops = if root.restore_type().is_some() || root.has(HOST) || root.has(COMM_PORT) {
        let Some(n) = name else {
            return Err(LinkError::invalid_parameter(
                "name: required for the export of one connection",
            ));
        };
        cv.classify(vec![(n.to_owned(), root)])
    } else {
        cv.classify(root.children())
    };
    if tops.is_empty() && cv.dropped.is_empty() {
        return Err(LinkError::invalid_parameter(
            "json: no DSA Modbus connection found",
        ));
    }
    if name.is_some() && tops.len() != 1 {
        return Err(LinkError::invalid_parameter(format!(
            "name: the file holds {} connections; name gives one a name",
            tops.len()
        )));
    }
    let mut conns = Vec::new();
    let mut taken = BTreeSet::new();
    for (dsa_name, top) in tops {
        let id = match name {
            Some(n) => n.to_owned(),
            None => cv.name(&dsa_name, &dsa_name, "", |n| taken.contains(n)),
        };
        taken.insert(id.clone());
        if let Some(n) = cv.connection(&dsa_name, &id, top) {
            conns.push(n);
        }
    }
    let nodes: usize = conns.iter().map(Node::count).sum();
    if nodes > branch::MAX_NODES {
        return Err(LinkError::invalid_parameter(format!(
            "json: {nodes} nodes, more than {}",
            branch::MAX_NODES
        )));
    }
    Ok(Converted {
        connections: conns,
        report: cv.report(),
    })
}

/// One DSA node object.
#[derive(Clone, Copy)]
struct Dsa<'a>(&'a JsonMap<String, Json>);

impl<'a> Dsa<'a> {
    /// Attribute `name`: `@name`, or a plain key that is not a child.
    fn get(self, name: &str) -> Option<&'a Json> {
        self.0
            .get(&format!("@{name}"))
            .or_else(|| self.0.get(name).filter(|v| !v.is_object()))
            .filter(|v| !v.is_null())
    }

    fn has(self, name: &str) -> bool {
        self.get(name).is_some()
    }

    /// A string attribute (a number or boolean as its text).
    fn text(self, name: &str) -> Option<String> {
        match self.get(name)? {
            Json::String(s) => Some(s.clone()),
            Json::Number(n) => Some(n.to_string()),
            Json::Bool(b) => Some(b.to_string()),
            _ => None,
        }
    }

    fn restore_type(self) -> Option<String> {
        self.text(RESTORE_TYPE)
    }

    /// Children by decoded name: object values under keys without `$`,
    /// `@` or `?`.
    fn children(self) -> Vec<(String, Dsa<'a>)> {
        self.0
            .iter()
            .filter(|(k, _)| !k.starts_with(['$', '@', '?']))
            .filter_map(|(k, v)| match v {
                Json::Object(m) => Some((decode_name(k), Dsa(m))),
                _ => None,
            })
            .collect()
    }
}

/// A number: JSON number or numeric text, finite.
fn number(j: &Json) -> Option<f64> {
    let f = match j {
        Json::Number(n) => n.as_f64()?,
        Json::String(s) => s.trim().parse::<f64>().ok()?,
        _ => return None,
    };
    f.is_finite().then_some(f)
}

/// An integer (a number without a fraction).
fn integer(j: &Json) -> Option<i64> {
    let f = number(j)?;
    (f.fract() == 0.0 && f.abs() < 9e15).then_some(f as i64)
}

fn boolean(j: &Json) -> Option<bool> {
    match j {
        Json::Bool(b) => Some(*b),
        Json::String(s) if s.eq_ignore_ascii_case("true") => Some(true),
        Json::String(s) if s.eq_ignore_ascii_case("false") => Some(false),
        _ => None,
    }
}

/// `StringUtils.decodeName`: `%XX` → the byte.
fn decode_name(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let hex = |c: u8| (c as char).to_digit(16);
        if b[i] == b'%' && i + 2 < b.len() {
            if let (Some(h), Some(l)) = (hex(b[i + 1]), hex(b[i + 2])) {
                out.push(u8::try_from(h * 16 + l).unwrap_or(b'_'));
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// A valid node id from a DSA name (before reserved names and duplicates).
fn sanitize(name: &str) -> String {
    let mut s: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.') {
                c
            } else {
                '_'
            }
        })
        .collect();
    if s.is_empty() {
        s.push_str("node");
    }
    if let Some(rest) = s.strip_prefix("add_") {
        // `add_*` is the framework's (a folder may not take it).
        s = format!("add-{rest}");
    }
    s
}

fn join(at: &str, name: &str) -> String {
    if at.is_empty() {
        name.to_owned()
    } else {
        format!("{at}/{name}")
    }
}

/// A top node of the file to import as one connection.
enum Top<'a> {
    Ip(Dsa<'a>),
    Serial(Dsa<'a>),
    /// Two-tier IP devices on one host and port (`ModbusLink.java:399-436`):
    /// the first one's attributes make the connection.
    Legacy(Vec<(String, Dsa<'a>)>),
}

/// What a connection gives its devices.
struct ConnCtx {
    max_regs: u64,
    max_bits: u64,
    /// Serial: unit 0 is broadcast (P3).
    rtu: bool,
}

#[derive(Default)]
struct Conv {
    dropped: Vec<Value>,
    disabled: Vec<Value>,
    renamed: Vec<Value>,
}

fn entry(kv: &[(&str, &str)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), Value::from(*v)))
            .collect(),
    )
}

impl Conv {
    fn report(self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("dropped".into(), Value::Array(self.dropped)),
            ("disabled".into(), Value::Array(self.disabled)),
            ("renamed".into(), Value::Array(self.renamed)),
        ])
    }

    /// `field` of the DSA node at `path` is not carried (or not as it was).
    fn drop(&mut self, path: &str, field: &str, reason: impl Into<String>) {
        self.dropped.push(entry(&[
            ("path", path),
            ("field", field),
            ("reason", &reason.into()),
        ]));
    }

    /// Our node at `key` will not work as imported: enabled false.
    fn disable(&mut self, key: &str, reason: impl Into<String>) {
        self.disabled
            .push(entry(&[("path", key), ("reason", &reason.into())]));
    }

    /// The id of the DSA node `name` at `path`, below our `at`, avoiding
    /// reserved names and those `taken` says are; a change goes in `renamed`.
    fn name(&mut self, name: &str, path: &str, at: &str, taken: impl Fn(&str) -> bool) -> String {
        let base = sanitize(name);
        let free = |n: &str| !RESERVED.contains(&n) && !taken(n);
        let id = if free(&base) {
            base
        } else {
            (2..)
                .map(|i| format!("{base}_{i}"))
                .find(|n| free(n))
                .expect("a free name")
        };
        if id != name {
            self.renamed
                .push(entry(&[("from", path), ("to", &join(at, &id))]));
        }
        id
    }

    /// The top nodes that are connections; the others are reported.
    fn classify<'a>(&mut self, nodes: Vec<(String, Dsa<'a>)>) -> Vec<(String, Top<'a>)> {
        let mut tops: Vec<(String, Top<'a>)> = Vec::new();
        let mut legacy: BTreeMap<(String, String), usize> = BTreeMap::new();
        for (name, n) in nodes {
            match n.restore_type().as_deref() {
                // `ModbusLink.java:376-398`
                Some("conn") if n.has(HOST) && n.has(PORT) => tops.push((name, Top::Ip(n))),
                Some("conn") if n.has(COMM_PORT) || n.has(COMM_PORT_MANUAL) => {
                    tops.push((name, Top::Serial(n)))
                }
                Some("conn") => self.drop(
                    &name,
                    HOST,
                    "a connection without host and port or comm port id: DSA does not load it",
                ),
                Some("folder") if n.has(HOST) && n.has(PORT) => {
                    if !(n.has(SLAVE_ID) && n.has(INTERVAL)) {
                        self.drop(
                            &name,
                            SLAVE_ID,
                            "a two-tier device without slave id or polling interval: DSA does not load it",
                        );
                        continue;
                    }
                    let key = (
                        n.text(HOST).unwrap_or_default(),
                        n.text(PORT).unwrap_or_default(),
                    );
                    match legacy.get(&key) {
                        Some(&i) => {
                            if let Top::Legacy(devs) = &mut tops[i].1 {
                                devs.push((name, n));
                            }
                        }
                        None => {
                            legacy.insert(key, tops.len());
                            tops.push((name.clone(), Top::Legacy(vec![(name, n)])));
                        }
                    }
                }
                Some("folder") => self.drop(
                    &name,
                    RESTORE_TYPE,
                    "a device or folder without a connection: import its connection",
                ),
                Some("editable folder") => self.drop(
                    &name,
                    RESTORE_TYPE,
                    "a local slave (setup local slave): slave mode is not imported",
                ),
                Some(other) => self.drop(
                    &name,
                    RESTORE_TYPE,
                    format!("{other:?} is not a DSA Modbus connection"),
                ),
                None => self.drop(
                    &name,
                    RESTORE_TYPE,
                    "not a DSA Modbus node (no restoreType): DSA removes it at start",
                ),
            }
        }
        tops
    }

    /// An integer attribute in `lo..=hi`: `default` when missing, reported
    /// and clamped (or the default) when outside or not a number.
    fn int_in(&mut self, n: Dsa, path: &str, attr: &str, lo: i64, hi: i64, default: i64) -> u64 {
        let v = match n.get(attr) {
            None => default,
            Some(j) => match integer(j) {
                Some(x) if x < lo || x > hi => {
                    let c = x.clamp(lo, hi);
                    self.drop(path, attr, format!("{x} is outside {lo}…{hi}: {c} set"));
                    c
                }
                Some(x) => x,
                None => {
                    self.drop(path, attr, format!("not an integer: {j}; {default} set"));
                    default
                }
            },
        };
        u64::try_from(v).unwrap_or(0)
    }

    fn bool_of(&mut self, n: Dsa, path: &str, attr: &str, default: bool) -> bool {
        match n.get(attr) {
            None => default,
            Some(j) => boolean(j).unwrap_or_else(|| {
                self.drop(path, attr, format!("not true or false: {j}; {default} set"));
                default
            }),
        }
    }

    /// The connection `top` (DSA `dsa_name`) as our `id`, or `None` when it
    /// cannot be imported (reported).
    fn connection(&mut self, dsa_name: &str, id: &str, top: Top) -> Option<Node> {
        let (node, devices): (Dsa, Vec<(String, Dsa)>) = match &top {
            Top::Ip(n) | Top::Serial(n) => (*n, n.children()),
            Top::Legacy(devs) => (devs[0].1, devs.clone()),
        };
        let serial = matches!(top, Top::Serial(_));
        let mut enabled = true;
        let mut params = BTreeMap::new();
        let transport = node
            .text(TRANSPORT)
            .map(|t| t.to_ascii_uppercase())
            .unwrap_or_else(|| {
                let t = if serial { "RTU" } else { "TCP" };
                self.drop(dsa_name, TRANSPORT, format!("missing: {t} set"));
                t.to_owned()
            });
        let kind = if serial {
            match transport.as_str() {
                "RTU" => {}
                "ASCII" => {
                    enabled = false;
                    self.disable(
                        id,
                        "transport ASCII: Modbus ASCII is not supported (ruling 14); imported as RTU",
                    );
                }
                other => {
                    self.drop(dsa_name, TRANSPORT, format!("unknown transport {other:?}"));
                    return None;
                }
            }
            let port = node
                .text(COMM_PORT)
                .filter(|p| !p.trim().is_empty())
                .or_else(|| node.text(COMM_PORT_MANUAL))
                .unwrap_or_default();
            params.insert("serial_port".into(), Value::Str(port));
            for (attr, ours) in [(BAUD, "baud_rate"), (DATA_BITS, "data_bits")] {
                if let Some(j) = node.get(attr) {
                    let Some(x) = integer(j).and_then(|x| u64::try_from(x).ok()) else {
                        self.drop(dsa_name, attr, format!("not an integer: {j}"));
                        return None;
                    };
                    params.insert(ours.into(), Value::UInt(x));
                }
            }
            // jssc: 1, 2, or 3 for 1.5 stop bits.
            let stop = match node.get(STOP_BITS).map(integer) {
                None | Some(Some(1)) => 1,
                Some(Some(2)) => 2,
                Some(_) => {
                    enabled = false;
                    self.disable(
                        id,
                        "stop bits: only 1 and 2 are supported (DSA 3 = 1.5); imported as 1",
                    );
                    1
                }
            };
            params.insert("stop_bits".into(), Value::UInt(stop));
            // `ParityType.parseParity`: anything else is NONE.
            let parity = node.text(PARITY).unwrap_or_default().to_ascii_uppercase();
            let ours = match parity.as_str() {
                "ODD" => "odd",
                "EVEN" => "even",
                "MARK" | "SPACE" => {
                    enabled = false;
                    self.disable(
                        id,
                        format!("parity {parity}: not supported (ruling 14); imported as none"),
                    );
                    "none"
                }
                _ => "none",
            };
            params.insert("parity".into(), Value::from(ours));
            "serial_connection"
        } else {
            match transport.as_str() {
                "TCP" => {}
                "UDP" => {
                    enabled = false;
                    self.disable(
                        id,
                        "transport UDP: Modbus UDP is not supported (ruling 14); imported as TCP",
                    );
                }
                other => {
                    self.drop(dsa_name, TRANSPORT, format!("unknown transport {other:?}"));
                    return None;
                }
            }
            params.insert("transport".into(), Value::from("tcp"));
            params.insert(
                "host".into(),
                Value::Str(node.text(HOST).unwrap_or_default()),
            );
            let port = node.get(PORT).and_then(integer);
            let Some(port) = port.and_then(|p| u64::try_from(p).ok()) else {
                self.drop(dsa_name, PORT, "not a port number");
                return None;
            };
            params.insert("port".into(), Value::UInt(port));
            "ip_connection"
        };
        // Defaults as DSA restores them (`ModbusLink.java:353-358`, `:200-207`).
        let timeout = self.int_in(node, dsa_name, TIMEOUT, 100, 10_000, 500);
        params.insert("timeout_ms".into(), Value::UInt(timeout));
        let retries = self.int_in(node, dsa_name, RETRIES, 0, 5, 2);
        params.insert("retries".into(), Value::UInt(retries));
        let mode = match node.text(MULTI_WRITE) {
            Some(m) if m.eq_ignore_ascii_case("Always") => "multiple",
            Some(m) if m.eq_ignore_ascii_case("Never") => "single",
            Some(m) if m.eq_ignore_ascii_case("As Appropriate") => "auto",
            Some(m) => {
                self.drop(
                    dsa_name,
                    MULTI_WRITE,
                    format!("unknown {m:?}: auto set (As Appropriate)"),
                );
                "auto"
            }
            // `ModbusLink.java:364-372`
            None if node.get(MULTI_WRITE_ONLY).and_then(boolean) == Some(true) => "multiple",
            None => "auto",
        };
        params.insert("write_mode".into(), Value::from(mode));
        let max_bits = self.int_in(node, dsa_name, MAX_BITS, 1, 2000, 2000);
        let max_regs = self.int_in(node, dsa_name, MAX_REGS, 1, 125, 125);
        if let Some(j) = node.get(MAX_WRITE) {
            self.drop(
                dsa_name,
                MAX_WRITE,
                format!("{j}: no equivalent; a write carries up to 123 registers in one request"),
            );
        }
        match node.get(DISCARD) {
            Some(j) if integer(j) == Some(0) => {}
            Some(j) => self.drop(dsa_name, DISCARD, format!("{j}: no equivalent")),
            None => {}
        }
        if let Err(e) = Conn::from_kind_value(kind, &Value::Map(params.clone())) {
            self.drop(dsa_name, "", format!("not imported: {}", e.message));
            return None;
        }
        params.insert("kind".into(), Value::from(kind));
        let cctx = ConnCtx {
            max_regs,
            max_bits,
            rtu: serial,
        };
        let mut children = Vec::new();
        let mut taken = BTreeSet::new();
        for (dn, d) in devices {
            if STATUS_LEAVES.contains(&dn.as_str()) {
                continue;
            }
            let path = match &top {
                Top::Legacy(_) => dn.clone(),
                _ => format!("{dsa_name}/{dn}"),
            };
            // `ModbusConnection.java:190-195`
            if !(d.has(SLAVE_ID) && d.has(INTERVAL)) {
                self.drop(
                    &path,
                    RESTORE_TYPE,
                    "not a device (no slave id or polling interval): DSA removes it at start",
                );
                continue;
            }
            let did = self.name(&dn, &path, id, |n| taken.contains(n));
            if let Some(n) = self.device(d, &path, &join(id, &did), &did, &cctx) {
                taken.insert(did);
                children.push(n);
            }
        }
        Some(Node {
            level: Level::Connection,
            name: id.to_owned(),
            params,
            enabled,
            children,
        })
    }

    /// A device at DSA `path`, our `key` (`conn/id`).
    fn device(&mut self, d: Dsa, path: &str, key: &str, id: &str, c: &ConnCtx) -> Option<Node> {
        let unit = d.get(SLAVE_ID).and_then(integer);
        let Some(unit) = unit.filter(|u| (0..=255).contains(u)) else {
            let j = d.get(SLAVE_ID).map(Json::to_string).unwrap_or_default();
            self.drop(
                path,
                SLAVE_ID,
                format!("{j}: units are 0…255; device not imported"),
            );
            return None;
        };
        let interval = d.get(INTERVAL).and_then(number);
        let Some(ms) = interval.filter(|ms| *ms > 0.0) else {
            self.drop(
                path,
                INTERVAL,
                "not a positive number (ms); device not imported",
            );
            return None;
        };
        let poll_s = (ms / 1000.0).clamp(0.01, 86_400.0);
        if poll_s != ms / 1000.0 {
            self.drop(
                path,
                INTERVAL,
                format!("{ms} ms is outside 10 ms…24 h: {poll_s} s set"),
            );
        }
        if self.bool_of(d, path, ZERO_FAIL, false) {
            self.drop(
                path,
                ZERO_FAIL,
                "not supported (ruling 14): a failed poll shows bad quality, the last value stays",
            );
        }
        // Defaults as DSA restores them (`ModbusConnection.java:174-189`).
        let batch = self.bool_of(d, path, BATCH, true);
        let contiguous = self.bool_of(d, path, CONTIGUOUS, true);
        let suppress_ms = match d.get(SUPPRESS) {
            None => 60_000.0,
            Some(j) => number(j).filter(|x| *x >= 0.0).unwrap_or_else(|| {
                self.drop(path, SUPPRESS, format!("not a duration: {j}; 60 s set"));
                60_000.0
            }),
        };
        let republish = if suppress_ms == 0.0 {
            // DSA 0: every poll publishes (`SlaveNode.java:377-378`).
            (poll_s / 2.0).min(3600.0)
        } else {
            let s = suppress_ms / 1000.0;
            if s > 3600.0 {
                self.drop(path, SUPPRESS, format!("{s} s is above 3600 s: 3600 s set"));
            }
            s.min(3600.0)
        };
        let (max_regs, max_bits) = if batch {
            (c.max_regs, c.max_bits)
        } else {
            (1, 1)
        };
        let params = BTreeMap::from([
            ("unit".into(), Value::UInt(u64::try_from(unit).unwrap_or(0))),
            ("contiguous_only".into(), Value::Bool(contiguous)),
            ("max_regs".into(), Value::UInt(max_regs)),
            ("max_bits".into(), Value::UInt(max_bits)),
            ("republish_s".into(), Value::Float(republish)),
        ]);
        if let Err(e) = Device::from_value(&Value::Map(params.clone())) {
            self.drop(path, "", format!("not imported: {}", e.message));
            return None;
        }
        let mut enabled = true;
        if c.rtu && unit == 0 {
            enabled = false;
            self.disable(
                key,
                "unit 0 is the RTU broadcast address, which is not supported (P3)",
            );
        }
        let mut ids = BTreeSet::new();
        let mut children = Vec::new();
        let mut local = BTreeSet::new();
        let mut parent = Parent {
            key,
            depth: 0,
            out: &mut children,
            local: &mut local,
        };
        self.contents(d, path, &mut parent, &mut ids, poll_s);
        Some(Node {
            level: Level::Device,
            name: id.to_owned(),
            params,
            enabled,
            children,
        })
    }

    /// The folders and points of the DSA device or folder `n` at `path`
    /// into `p`; `ids` are the point ids of the device.
    fn contents(
        &mut self,
        n: Dsa,
        path: &str,
        p: &mut Parent<'_>,
        ids: &mut BTreeSet<String>,
        poll_s: f64,
    ) {
        for (cn, c) in n.children() {
            if STATUS_LEAVES.contains(&cn.as_str()) {
                continue;
            }
            let cpath = format!("{path}/{cn}");
            match c.restore_type().as_deref() {
                Some("point") => {
                    let Some(params) = self.point(c, &cpath, poll_s) else {
                        continue;
                    };
                    let local = &*p.local;
                    let id =
                        self.name(&cn, &cpath, p.key, |x| ids.contains(x) || local.contains(x));
                    ids.insert(id.clone());
                    p.local.insert(id.clone());
                    p.out.push(Node {
                        level: Level::Point,
                        name: id,
                        params,
                        enabled: true,
                        children: Vec::new(),
                    });
                }
                Some("folder") if p.depth >= MAX_FOLDER_DEPTH => {
                    self.drop(
                        &cpath,
                        "folder",
                        format!(
                            "folders nest at most {MAX_FOLDER_DEPTH} deep: its contents are in {}",
                            p.key
                        ),
                    );
                    self.contents(c, &cpath, p, ids, poll_s);
                }
                Some("folder") => {
                    let local = &*p.local;
                    let fid = self.name(&cn, &cpath, p.key, |x| local.contains(x));
                    p.local.insert(fid.clone());
                    let key = join(p.key, &fid);
                    let (mut out, mut local) = (Vec::new(), BTreeSet::new());
                    let mut sub = Parent {
                        key: &key,
                        depth: p.depth + 1,
                        out: &mut out,
                        local: &mut local,
                    };
                    self.contents(c, &cpath, &mut sub, ids, poll_s);
                    p.out.push(Node {
                        level: Level::Folder,
                        name: fid,
                        params: BTreeMap::new(),
                        enabled: true,
                        children: out,
                    });
                }
                _ => self.drop(
                    &cpath,
                    RESTORE_TYPE,
                    "not a DSA Modbus point or folder: DSA removes it at start",
                ),
            }
        }
    }

    /// A point's params, or `None` (reported).
    fn point(&mut self, n: Dsa, path: &str, poll_s: f64) -> Option<BTreeMap<String, Value>> {
        // `SlaveFolder.java:149-150`: DSA drops a point without one of these.
        for attr in [
            TYPE,
            OFFSET,
            REGS,
            DATA_TYPE,
            SCALING,
            SCALING_OFFSET,
            WRITABLE,
        ] {
            if !n.has(attr) {
                self.drop(path, attr, "missing: DSA does not load the point either");
                return None;
            }
        }
        let table = n.text(TYPE).unwrap_or_default().to_ascii_lowercase();
        if !matches!(table.as_str(), "coil" | "discrete" | "holding" | "input") {
            self.drop(path, TYPE, format!("unknown point type {table:?}"));
            return None;
        }
        let bits = matches!(table.as_str(), "coil" | "discrete");
        let int = |attr: &str| n.get(attr).and_then(integer);
        let Some(addr) = int(OFFSET).and_then(|a| u64::try_from(a).ok()) else {
            self.drop(path, OFFSET, "not an address 0…65535");
            return None;
        };
        let bit = n.get(BIT).map_or(Some(-1), integer);
        let Some(bit) = bit else {
            self.drop(path, BIT, "not an integer");
            return None;
        };
        let dtype_name = n.text(DATA_TYPE).unwrap_or_default();
        let (dtype, bit) = match dtype(&dtype_name, bits, bit) {
            Ok(d) => d,
            Err((field, why)) => {
                self.drop(path, field, why);
                return None;
            }
        };
        let numeric = !matches!(
            dtype,
            DType::Binary | DType::Bits16 | DType::Char | DType::VarChar
        );
        let (mut scale, mut offset) = (1.0, 0.0);
        if numeric {
            let scaling = n.get(SCALING).and_then(number);
            let add = n.get(SCALING_OFFSET).and_then(number);
            let (Some(scaling), Some(add)) = (scaling, add) else {
                let attr = if scaling.is_none() {
                    SCALING
                } else {
                    SCALING_OFFSET
                };
                self.drop(path, attr, "not a number");
                return None;
            };
            if scaling == 0.0 {
                self.drop(
                    path,
                    SCALING,
                    "0: DSA divides the raw value by it; point not imported",
                );
                return None;
            }
            scale = 1.0 / scaling;
            offset = add;
        }
        let mut writable = self.bool_of(n, path, WRITABLE, false);
        if writable && !matches!(table.as_str(), "coil" | "holding") {
            self.drop(
                path,
                WRITABLE,
                "only coil and holding points can be written: imported read-only",
            );
            writable = false;
        }
        let regs = if matches!(dtype, DType::Char | DType::VarChar) {
            match int(REGS).and_then(|r| u64::try_from(r).ok()) {
                Some(r) => r,
                None => {
                    self.drop(path, REGS, "not a register count");
                    return None;
                }
            }
        } else {
            1
        };
        let params = BTreeMap::from([
            ("table".into(), Value::Str(table)),
            ("addr".into(), Value::UInt(addr)),
            ("dtype".into(), Value::from(dtype.name())),
            ("bit".into(), Value::UInt(bit)),
            ("regs".into(), Value::UInt(regs)),
            ("poll_s".into(), Value::Float(poll_s)),
            ("scale".into(), Value::Float(scale)),
            ("offset".into(), Value::Float(offset)),
            ("writable".into(), Value::Bool(writable)),
        ]);
        if let Err(e) = Point::from_value(&Value::Map(params.clone())) {
            self.drop(path, "", format!("not imported: {}", e.message));
            return None;
        }
        Some(params)
    }
}

/// Where the contents of a device or folder go.
struct Parent<'a> {
    /// Our key of the device or folder.
    key: &'a str,
    /// Folders above the contents (0 = the device's own).
    depth: usize,
    out: &'a mut Vec<Node>,
    /// Names taken in it (folders and points).
    local: &'a mut BTreeSet<String>,
}

/// A DSA data type (`DataType.java:4-31`, case-insensitive) on a bit table
/// or a register as ours, with our `bit`; a refusal names the DSA attribute.
/// modbus4j (`DataType.java:60-112`): a 16-bit SWAP swaps the two bytes, a
/// 32/64-bit SWAP the words, SWAPSWAP both (DCBA); M10K is read as a 32-bit
/// int of `hi, lo` (`SlaveNode.java:265-267,282-300`).
fn dtype(name: &str, bits: bool, bit: i64) -> Result<(DType, u64), (&'static str, String)> {
    use DType::*;
    let upper = name.to_ascii_uppercase();
    let d = match upper.as_str() {
        "BOOLEAN" => Binary,
        "INT16" => I16,
        "UINT16" => U16,
        "INT16SWAP" => I16BSwap,
        "UINT16SWAP" => U16BSwap,
        "INT32" => I32,
        "UINT32" => U32,
        "INT32SWAP" => I32WSwap,
        "UINT32SWAP" => U32WSwap,
        "INT32SWAPSWAP" => I32WBSwap,
        "UINT32SWAPSWAP" => U32WBSwap,
        "FLOAT32" => F32,
        "FLOAT32SWAP" => F32WSwap,
        "INT64" => I64,
        "UINT64" => U64,
        "INT64SWAP" => I64WSwap,
        "UINT64SWAP" => U64WSwap,
        "FLOAT64" => F64,
        "FLOAT64SWAP" => F64WSwap,
        "BCD16" => Bcd16,
        "BCD32" => Bcd32,
        "BCD32SWAP" => Bcd32WSwap,
        "CHARSTRING" => Char,
        "VARCHARSTRING" => VarChar,
        "INT32M10K" => I32M10k,
        "UINT32M10K" => U32M10k,
        "INT32M10KSWAP" => I32M10kWSwap,
        "UINT32M10KSWAP" => U32M10kWSwap,
        _ => return Err((DATA_TYPE, format!("unknown DSA data type {name:?}"))),
    };
    // Coil and discrete hold bits whatever the type (`SlaveFolder.java:317-319`).
    if bits {
        return Ok((Binary, 0));
    }
    if d != Binary {
        return Ok((d, 0));
    }
    // BOOLEAN on a register: bit -1 reads it as 16 bools
    // (`SlaveNode.java:270-271,313-319`), else that bit.
    match bit {
        -1 => Ok((Bits16, 0)),
        0..=15 => Ok((Binary, u64::try_from(bit).unwrap_or(0))),
        _ => Err((BIT, format!("{bit}: a register has bits 0…15"))),
    }
}
