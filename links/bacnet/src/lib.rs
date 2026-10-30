//! BACnet/IP client on the driver framework (ADR 0004).
//!
//! Tree: `<conn>/<device>/<point>`; [`Conn`] is a BACnet/IP port (one UDP
//! socket, optional foreign-device registration at a BBMD), [`Dev`] a
//! BACnet device (instance, and an address or Who-Is resolution), and
//! [`Point`] one property of one object. The framework owns the tree, the
//! generated actions, states, scheduling, read-back writes and the quality
//! ladder; this crate does the protocol ([`codec`]: BVLC, NPDU, APDU and
//! the application tags, written here: no maintained async BACnet crate).
//!
//! * Reads: ReadPropertyMultiple, batched so that the request and the
//!   estimated reply fit the device's max APDU (from I-Am, or the device
//!   param); no segmentation: a request whose reply would be segmented
//!   (Abort segmentation-not-supported, buffer-overflow, apdu-too-long) is
//!   split in two, and the device's limit on properties per request is
//!   remembered. A device that does not know RPM (Reject
//!   unrecognized-service, Error services) is read with ReadProperty per
//!   property from then on. An Error or Reject for a whole RPM of several
//!   properties is read again property by property, so one bad point does
//!   not fail the others.
//! * Writes: WriteProperty with the point's `priority` (1…16); the
//!   framework reads the point back. A point with `property = relinquish`
//!   writes NULL at its own priority to its object (level write); the
//!   device action `relinquish` (any object and priority) needs config.
//! * Invoke ids per remote peer; a reply is taken only from that peer with
//!   the request's invoke id, so a late reply after a timeout is dropped
//!   (counted as `late_replies`).
//! * Bindings: a device without an address is bound by its own Who-Is
//!   only (an I-Am counts only inside that window; exactly one address
//!   must answer, and confirm by its `object-identifier`), kept until it
//!   stops answering. A Forwarded-NPDU's origin is believed from the
//!   configured BBMD only.
//! * Ping: ReadProperty of the device object's `system-status`; any reply
//!   (an Error too) means the device is alive.
//! * Quality: with `check_status` the point's `status-flags` are read in
//!   the same request as `present-value`; a set `fault` flag makes the
//!   point `bad`. Out-of-service and overridden values are published as
//!   they are (the framework has no per-point `uncertain` from a driver).
//!
//! Actions: connection `who_is {low?, high?, wait_ms = 3000}` (level
//! config); device `list_objects {limit = 1000}` (level config),
//! `read_property {...}` (level read) and `relinquish {object_type,
//! instance, priority = 16}` (level config).
//!
//! Not supported: BACnet MS/TP (serial; a routed MS/TP device behind a
//! BACnet/IP router is), segmentation, COV subscriptions, alarms and
//! events, BACnet/SC, BACnet/IPv6. The link does not answer Who-Is itself.

#![forbid(unsafe_code)]

pub mod codec;
#[cfg(feature = "sim")]
pub mod sim;

use codec::{Apdu, AppValue, Bvlc, IAm, NetAddr, ObjectId, PropRef};
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::{LazyLock, Mutex};
use std::time::Duration;
use tokio::net::UdpSocket;
use tokio::time::Instant;
use tracing::{debug, info};
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Status, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, ParamSpec};
// Traits (type namespace) beside the derive macros of the same name.
use wyrm_link_sdk::driver::{
    Driver, DriverError, Framework, Level, Outcome, ParamEnum, Params, PointId, Target,
};
use wyrm_link_sdk::LinkError;
use wyrm_link_sdk::{ParamEnum, Params};

/// The `bacnet` link: the framework running [`BacnetDriver`].
pub type Bacnet = Framework<BacnetDriver>;

// ---------------------------------------------------------------- params

/// A BACnet/IP port.
#[derive(Debug, Clone, PartialEq, Params)]
pub struct Conn {
    /// Local IPv4 address the UDP socket binds to.
    #[param(default = "0.0.0.0", display = "Bind Address", dest)]
    pub bind_host: String,
    #[param(default = 47808, display = "Bind Port", dest)]
    pub bind_port: u16,
    /// Where Who-Is goes (IP:port), unless a BBMD is set.
    #[param(
        default = "255.255.255.255:47808",
        display = "Broadcast Address",
        desc = "IP:port for Who-Is (the subnet's broadcast address)"
    )]
    pub broadcast: String,
    /// Register as a foreign device at this BBMD (IP:port); empty = none.
    #[param(
        default = "",
        display = "BBMD Address",
        placeholder = "10.0.0.1:47808",
        desc = "foreign-device registration (empty = none)"
    )]
    pub bbmd: String,
    #[param(default = 300, min = 30, max = 65535, display = "BBMD TTL (s)")]
    pub bbmd_ttl_s: u16,
    /// Bound on each confirmed request.
    #[param(default = 3000, min = 100, max = 60000, display = "APDU Timeout (ms)")]
    pub apdu_timeout_ms: u32,
    /// Repeats of a request after a timeout (not after an error reply).
    #[param(default = 1, min = 0, max = 5, display = "APDU Retries")]
    pub apdu_retries: u8,
    /// The largest reply this link accepts.
    #[param(
        default = 1476,
        min = 50,
        max = 1476,
        display = "Max APDU Length Accepted"
    )]
    pub max_apdu: u16,
}

impl Conn {
    fn timeout(&self) -> Duration {
        Duration::from_millis(self.apdu_timeout_ms.into())
    }

    /// One request with its retries.
    fn per_request(&self) -> Duration {
        self.timeout() * (1 + u32::from(self.apdu_retries))
    }
}

/// `a.b.c.d` or `a.b.c.d:port` (default port 47808).
pub fn parse_addr(s: &str) -> Result<SocketAddrV4, String> {
    let s = s.trim();
    if let Ok(a) = s.parse::<SocketAddrV4>() {
        return Ok(a);
    }
    s.parse::<Ipv4Addr>()
        .map(|ip| SocketAddrV4::new(ip, codec::DEFAULT_PORT))
        .map_err(|_| format!("{s:?} is not an IPv4 address (a.b.c.d[:port])"))
}

fn parse_mac(s: &str) -> Result<Vec<u8>, String> {
    let h: String = s
        .chars()
        .filter(|c| !matches!(c, ':' | ' ' | '-'))
        .collect();
    if !h.len().is_multiple_of(2) || h.len() > 14 {
        return Err(format!("mac: {s:?} is not 1…7 hex octets"));
    }
    (0..h.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&h[i..i + 2], 16))
        .collect::<Result<Vec<u8>, _>>()
        .map_err(|_| format!("mac: {s:?} is not hex"))
}

/// A BACnet device. Hand-written `Params`: the address, network and MAC
/// are checked together.
#[derive(Debug, Clone, PartialEq)]
pub struct Dev {
    pub instance: u32,
    /// Empty: found by Who-Is.
    pub address: String,
    /// DNET of a device behind a BACnet router; 0 = on this IP network.
    pub network: u16,
    /// DADR behind the router (hex), with `network`.
    pub mac: String,
    pub use_rpm: bool,
    /// 0 = from I-Am.
    pub max_apdu: u16,
    pub ping_s: f64,
    pub republish_s: f64,
}

impl Dev {
    fn key(&self) -> DevKey {
        DevKey {
            instance: self.instance,
            address: self.address.clone(),
            network: self.network,
            mac: self.mac.clone(),
        }
    }

    /// The address configured (`None`: by Who-Is).
    fn static_peer(&self) -> Result<Option<Peer>, String> {
        if self.address.trim().is_empty() {
            return Ok(None);
        }
        let addr = parse_addr(&self.address).map_err(|e| format!("address: {e}"))?;
        let net = if self.network == 0 {
            None
        } else {
            Some(NetAddr {
                net: self.network,
                mac: parse_mac(&self.mac)?,
            })
        };
        Ok(Some(Peer { addr, net }))
    }
}

impl Params for Dev {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("instance", TypeCode::Number)
                .bounds(0.0, f64::from(codec::MAX_INSTANCE))
                .display("Device Instance"),
            ParamSpec::new("address", TypeCode::String)
                .default("")
                .placeholder("192.168.1.20:47808")
                .desc("IP[:port]; empty = find the device by Who-Is")
                .display("Address"),
            ParamSpec::new("network", TypeCode::Number)
                .default(0u64)
                .bounds(0.0, 65534.0)
                .desc("network number of a device behind a BACnet router (0 = local)")
                .display("Network Number"),
            ParamSpec::new("mac", TypeCode::String)
                .default("")
                .placeholder("0A")
                .desc("hex MAC behind the router (MS/TP: one octet)")
                .display("MAC Address"),
            ParamSpec::new("use_rpm", TypeCode::Bool)
                .default(true)
                .display("Use ReadPropertyMultiple"),
            ParamSpec::new("max_apdu", TypeCode::Number)
                .default(0u64)
                .bounds(0.0, f64::from(codec::MAX_APDU))
                .desc("0 = from I-Am (480 if the device does not say); else 50…1476")
                .display("Max APDU"),
            ParamSpec::new("ping_s", TypeCode::Number)
                .default(10.0)
                .bounds(0.0, 3600.0)
                .desc("0 = no ping")
                .display("Ping Rate (s)"),
            ParamSpec::new("republish_s", TypeCode::Number)
                .default(0.0)
                .bounds(0.0, 3600.0)
                .desc("publish unchanged values again after this long (0 = on change only)")
                .display("Republish Unchanged Values (s)"),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let d = Dev {
            instance: field::int(m, "instance")?,
            address: field::string(m, "address")?,
            network: field::int(m, "network")?,
            mac: field::string(m, "mac")?,
            use_rpm: field::bool(m, "use_rpm")?,
            max_apdu: field::int(m, "max_apdu")?,
            ping_s: field::f64(m, "ping_s")?,
            republish_s: field::f64(m, "republish_s")?,
        };
        if d.max_apdu != 0 && d.max_apdu < 50 {
            return Err(LinkError::invalid_parameter(
                "max_apdu: 0 (from I-Am) or 50…1476",
            ));
        }
        if d.network != 0 && d.address.trim().is_empty() {
            return Err(LinkError::invalid_parameter(
                "network: a routed device needs the router's address",
            ));
        }
        if d.network != 0 && d.mac.trim().is_empty() {
            return Err(LinkError::invalid_parameter(
                "mac: a routed device needs its MAC address on that network",
            ));
        }
        if d.network == 0 && !d.mac.trim().is_empty() {
            return Err(LinkError::invalid_parameter(
                "mac: only for a device behind a router (set network)",
            ));
        }
        d.static_peer().map_err(LinkError::invalid_parameter)?;
        Ok(d)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("instance".into(), Value::UInt(self.instance.into())),
            ("address".into(), Value::Str(self.address.clone())),
            ("network".into(), Value::UInt(self.network.into())),
            ("mac".into(), Value::Str(self.mac.clone())),
            ("use_rpm".into(), Value::Bool(self.use_rpm)),
            ("max_apdu".into(), Value::UInt(self.max_apdu.into())),
            ("ping_s".into(), Value::Float(self.ping_s)),
            ("republish_s".into(), Value::Float(self.republish_s)),
        ])
    }
}

/// Object types a point can be on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, ParamEnum)]
pub enum ObjectType {
    AnalogInput,
    AnalogOutput,
    AnalogValue,
    BinaryInput,
    BinaryOutput,
    BinaryValue,
    Calendar,
    Command,
    Device,
    Loop,
    MultiStateInput,
    MultiStateOutput,
    Schedule,
    Averaging,
    MultiStateValue,
    Accumulator,
    PulseConverter,
    CharacterstringValue,
    IntegerValue,
    LargeAnalogValue,
    PositiveIntegerValue,
}

impl ObjectType {
    pub fn id(self) -> u16 {
        match self {
            ObjectType::AnalogInput => 0,
            ObjectType::AnalogOutput => 1,
            ObjectType::AnalogValue => 2,
            ObjectType::BinaryInput => 3,
            ObjectType::BinaryOutput => 4,
            ObjectType::BinaryValue => 5,
            ObjectType::Calendar => 6,
            ObjectType::Command => 7,
            ObjectType::Device => 8,
            ObjectType::Loop => 12,
            ObjectType::MultiStateInput => 13,
            ObjectType::MultiStateOutput => 14,
            ObjectType::Schedule => 17,
            ObjectType::Averaging => 18,
            ObjectType::MultiStateValue => 19,
            ObjectType::Accumulator => 23,
            ObjectType::PulseConverter => 24,
            ObjectType::CharacterstringValue => 40,
            ObjectType::IntegerValue => 45,
            ObjectType::LargeAnalogValue => 46,
            ObjectType::PositiveIntegerValue => 48,
        }
    }
}

/// Properties a point can read; `other` takes `property_id`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Property {
    PresentValue,
    StatusFlags,
    Reliability,
    Units,
    OutOfService,
    EventState,
    ObjectName,
    Description,
    RelinquishDefault,
    PriorityArray,
    MinPresValue,
    MaxPresValue,
    HighLimit,
    LowLimit,
    CovIncrement,
    SystemStatus,
    /// Not a property: a `true` written to the point writes NULL to the
    /// object's `present-value` at the point's `priority`; it reads `true`
    /// while that slot of the priority array is empty.
    Relinquish,
    Other,
}

impl Property {
    /// The property id (`None` for `other`).
    pub fn id(self) -> Option<u32> {
        use codec::prop;
        Some(match self {
            Property::PresentValue => prop::PRESENT_VALUE,
            Property::StatusFlags => prop::STATUS_FLAGS,
            Property::Reliability => prop::RELIABILITY,
            Property::Units => prop::UNITS,
            Property::OutOfService => prop::OUT_OF_SERVICE,
            Property::EventState => prop::EVENT_STATE,
            Property::ObjectName => prop::OBJECT_NAME,
            Property::Description => prop::DESCRIPTION,
            Property::RelinquishDefault => prop::RELINQUISH_DEFAULT,
            Property::PriorityArray => prop::PRIORITY_ARRAY,
            Property::MinPresValue => prop::MIN_PRES_VALUE,
            Property::MaxPresValue => prop::MAX_PRES_VALUE,
            Property::HighLimit => prop::HIGH_LIMIT,
            Property::LowLimit => prop::LOW_LIMIT,
            Property::CovIncrement => prop::COV_INCREMENT,
            Property::SystemStatus => prop::SYSTEM_STATUS,
            Property::Relinquish | Property::Other => return None,
        })
    }
}

/// How a point's value is typed. `auto` follows the object type and the
/// property; the others name the application tag.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum DType {
    Auto,
    Real,
    Double,
    Unsigned,
    Signed,
    Enumerated,
    Boolean,
    CharacterString,
    BitString,
}

/// What a point's value is, resolved from `dtype`, the object type and
/// the property.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Real,
    Double,
    Unsigned,
    Signed,
    Enumerated,
    Boolean,
    /// ENUMERATED inactive/active shown as false/true.
    BinaryPv,
    CharString,
    BitString,
    /// `status-flags` as a map of the four flags.
    StatusFlags,
    /// A relinquish point: `true` while the slot at its priority is empty.
    Relinquished,
    /// Whatever the device sends (writes follow the value's type).
    Dynamic,
}

impl Kind {
    fn type_code(self) -> TypeCode {
        match self {
            Kind::Real | Kind::Double | Kind::Unsigned | Kind::Signed | Kind::Enumerated => {
                TypeCode::Number
            }
            Kind::Boolean | Kind::BinaryPv | Kind::Relinquished => TypeCode::Bool,
            Kind::CharString => TypeCode::String,
            Kind::BitString => TypeCode::Array,
            Kind::StatusFlags => TypeCode::Map,
            Kind::Dynamic => TypeCode::Dynamic,
        }
    }

    fn numeric(self) -> bool {
        matches!(
            self,
            Kind::Real | Kind::Double | Kind::Unsigned | Kind::Signed | Kind::Enumerated
        )
    }

    /// Octets a value takes in a reply (estimate for the batch plan).
    fn reply_octets(self) -> usize {
        match self {
            Kind::Real | Kind::Unsigned | Kind::Signed | Kind::Enumerated => 5,
            Kind::Double => 10,
            Kind::Boolean | Kind::BinaryPv => 1,
            Kind::Relinquished => 5,
            Kind::StatusFlags => 3,
            Kind::BitString => 8,
            Kind::CharString => 70,
            Kind::Dynamic => 40,
        }
    }
}

/// The kind of the value of `property` on an object of type `ty`.
fn value_kind(ty: ObjectType, property: Property) -> Kind {
    match property {
        Property::PresentValue | Property::RelinquishDefault => match ty {
            ObjectType::AnalogInput
            | ObjectType::AnalogOutput
            | ObjectType::AnalogValue
            | ObjectType::Loop
            | ObjectType::PulseConverter
            | ObjectType::Averaging => Kind::Real,
            ObjectType::LargeAnalogValue => Kind::Double,
            ObjectType::BinaryInput | ObjectType::BinaryOutput | ObjectType::BinaryValue => {
                Kind::BinaryPv
            }
            ObjectType::MultiStateInput
            | ObjectType::MultiStateOutput
            | ObjectType::MultiStateValue
            | ObjectType::Accumulator
            | ObjectType::Command
            | ObjectType::PositiveIntegerValue => Kind::Unsigned,
            ObjectType::IntegerValue => Kind::Signed,
            ObjectType::Calendar => Kind::Boolean,
            ObjectType::CharacterstringValue => Kind::CharString,
            ObjectType::Schedule | ObjectType::Device => Kind::Dynamic,
        },
        Property::MinPresValue
        | Property::MaxPresValue
        | Property::HighLimit
        | Property::LowLimit
        | Property::CovIncrement => {
            if ty == ObjectType::LargeAnalogValue {
                Kind::Double
            } else {
                Kind::Real
            }
        }
        Property::StatusFlags => Kind::StatusFlags,
        Property::Reliability | Property::Units | Property::EventState | Property::SystemStatus => {
            Kind::Enumerated
        }
        Property::OutOfService => Kind::Boolean,
        Property::ObjectName | Property::Description => Kind::CharString,
        Property::Relinquish => Kind::Relinquished,
        Property::PriorityArray | Property::Other => Kind::Dynamic,
    }
}

/// One point: a property of an object. Hand-written `Params` for the cross
/// rules (`property_id` with `other`, writable kinds, scale).
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    pub object_type: ObjectType,
    pub instance: u32,
    pub property: Property,
    pub property_id: u32,
    /// -1 = the whole property.
    pub array_index: i64,
    pub dtype: DType,
    pub check_status: bool,
    pub poll_s: f64,
    pub scale: f64,
    pub offset: f64,
    pub writable: bool,
    pub priority: u8,
    pub unit: String,
}

impl Point {
    pub fn object(&self) -> ObjectId {
        ObjectId::new(self.object_type.id(), self.instance)
    }

    /// What a poll reads.
    pub fn prop(&self) -> PropRef {
        if self.property == Property::Relinquish {
            return PropRef {
                id: codec::prop::PRIORITY_ARRAY,
                index: Some(self.priority.into()),
            };
        }
        PropRef {
            id: self.property.id().unwrap_or(self.property_id),
            index: u32::try_from(self.array_index).ok(),
        }
    }

    /// What a write writes.
    fn write_prop(&self) -> PropRef {
        if self.property == Property::Relinquish {
            return PropRef {
                id: codec::prop::PRESENT_VALUE,
                index: None,
            };
        }
        self.prop()
    }

    pub fn kind(&self) -> Kind {
        let auto = value_kind(self.object_type, self.property);
        if auto == Kind::Relinquished {
            return auto;
        }
        let k = match self.dtype {
            DType::Auto => return auto,
            DType::Real => Kind::Real,
            DType::Double => Kind::Double,
            DType::Unsigned => Kind::Unsigned,
            DType::Signed => Kind::Signed,
            DType::Enumerated => Kind::Enumerated,
            DType::Boolean => Kind::Boolean,
            DType::CharacterString => Kind::CharString,
            DType::BitString => Kind::BitString,
        };
        // status-flags stays a map when its own tag is named
        if k == Kind::BitString && auto == Kind::StatusFlags {
            auto
        } else {
            k
        }
    }

    /// Whether `status-flags` is read beside the value.
    fn reads_flags(&self) -> bool {
        self.check_status
            && self.property == Property::PresentValue
            && self.object_type != ObjectType::Device
    }

    fn scaled(&self) -> bool {
        self.scale != 1.0 || self.offset != 0.0
    }
}

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("object_type", TypeCode::Enum)
                .one_of(ObjectType::NAMES)
                .display("Object Type"),
            ParamSpec::new("instance", TypeCode::Number)
                .bounds(0.0, f64::from(codec::WILDCARD_INSTANCE))
                .display("Object Instance"),
            ParamSpec::new("property", TypeCode::Enum)
                .one_of(Property::NAMES)
                .default("present_value")
                .display("Property"),
            ParamSpec::new("property_id", TypeCode::Number)
                .default(0u64)
                .bounds(0.0, 4_194_303.0)
                .desc("property identifier with property = other")
                .display("Property ID"),
            ParamSpec::new("array_index", TypeCode::Number)
                .default(-1i64)
                .bounds(-1.0, 4_294_967_294.0)
                .desc("-1 = the whole property")
                .display("Array Index"),
            ParamSpec::new("dtype", TypeCode::Enum)
                .one_of(DType::NAMES)
                .default("auto")
                .desc("auto follows the object type and property")
                .display("Data Type"),
            ParamSpec::new("check_status", TypeCode::Bool)
                .default(true)
                .desc("read status-flags with present-value; fault makes the value bad")
                .display("Check Status Flags"),
            ParamSpec::new("poll_s", TypeCode::Number)
                .default(5.0)
                .bounds(0.05, 86_400.0)
                .display("Poll Rate (s)"),
            ParamSpec::new("scale", TypeCode::Number)
                .default(1.0)
                .display("Scaling"),
            ParamSpec::new("offset", TypeCode::Number)
                .default(0.0)
                .display("Scaling Offset"),
            ParamSpec::new("writable", TypeCode::Bool)
                .default(false)
                .display("Writable"),
            ParamSpec::new("priority", TypeCode::Number)
                .default(16u64)
                .bounds(1.0, 16.0)
                .desc("write priority (1 highest … 16 lowest)")
                .display("Write Priority"),
            ParamSpec::new("unit", TypeCode::String)
                .default("")
                .desc("shown as the point's unit (list_objects suggests one)")
                .display("Unit"),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let p = Point {
            object_type: field::enumv(m, "object_type")?,
            instance: field::int(m, "instance")?,
            property: field::enumv(m, "property")?,
            property_id: field::int(m, "property_id")?,
            array_index: field::int(m, "array_index")?,
            dtype: field::enumv(m, "dtype")?,
            check_status: field::bool(m, "check_status")?,
            poll_s: field::f64(m, "poll_s")?,
            scale: field::f64(m, "scale")?,
            offset: field::f64(m, "offset")?,
            writable: field::bool(m, "writable")?,
            priority: field::int(m, "priority")?,
            unit: field::string(m, "unit")?,
        };
        if p.property == Property::Relinquish && (p.dtype != DType::Auto || p.array_index != -1) {
            return Err(LinkError::invalid_parameter(
                "property: a relinquish point takes no dtype or array_index (it uses priority)",
            ));
        }
        if p.property != Property::Other && p.property_id != 0 {
            return Err(LinkError::invalid_parameter(
                "property_id: only with property = other",
            ));
        }
        if p.scale == 0.0 || !p.scale.is_finite() || !p.offset.is_finite() {
            return Err(LinkError::invalid_parameter(
                "scale: must be a finite number other than 0",
            ));
        }
        let k = p.kind();
        if p.scaled() && !k.numeric() {
            return Err(LinkError::invalid_parameter(
                "scale: only numeric values are scaled",
            ));
        }
        if p.writable && matches!(k, Kind::BitString | Kind::StatusFlags) {
            return Err(LinkError::invalid_parameter(
                "writable: bit strings (status-flags) are read only",
            ));
        }
        Ok(p)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            (
                "object_type".into(),
                Value::Str(self.object_type.name().into()),
            ),
            ("instance".into(), Value::UInt(self.instance.into())),
            ("property".into(), Value::Str(self.property.name().into())),
            ("property_id".into(), Value::UInt(self.property_id.into())),
            ("array_index".into(), Value::Int(self.array_index)),
            ("dtype".into(), Value::Str(self.dtype.name().into())),
            ("check_status".into(), Value::Bool(self.check_status)),
            ("poll_s".into(), Value::Float(self.poll_s)),
            ("scale".into(), Value::Float(self.scale)),
            ("offset".into(), Value::Float(self.offset)),
            ("writable".into(), Value::Bool(self.writable)),
            ("priority".into(), Value::UInt(self.priority.into())),
            ("unit".into(), Value::Str(self.unit.clone())),
        ])
    }
}

// ---------------------------------------------------------------- values

/// A REAL as the shortest decimal that reads back as the same `f32`
/// (`0.1`, not `0.10000000149011612`).
fn real(f: f32) -> f64 {
    f.to_string().parse().unwrap_or_else(|_| f64::from(f))
}

/// An application value as a WYRM value (no point semantics).
pub fn to_value(v: &AppValue) -> Value {
    let wild = |x: u8, w: usize| {
        if x == 0xFF {
            "*".repeat(w)
        } else {
            format!("{x:0w$}")
        }
    };
    match v {
        AppValue::Null => Value::Null,
        AppValue::Boolean(b) => Value::Bool(*b),
        AppValue::Unsigned(u) => Value::UInt(*u),
        AppValue::Signed(i) => Value::Int(*i),
        AppValue::Real(f) => Value::Float(real(*f)),
        AppValue::Double(f) => Value::Float(*f),
        AppValue::OctetString(b) => Value::Bytes(b.clone()),
        AppValue::CharString(s) => Value::Str(s.clone()),
        AppValue::BitString(bits) => Value::Array(bits.iter().map(|b| Value::Bool(*b)).collect()),
        AppValue::Enumerated(e) => Value::UInt((*e).into()),
        AppValue::Date(y, m, d, _) => {
            let year = if *y == 0xFF {
                "****".to_owned()
            } else {
                (1900 + u32::from(*y)).to_string()
            };
            Value::Str(format!("{year}-{}-{}", wild(*m, 2), wild(*d, 2)))
        }
        AppValue::Time(h, m, s, c) => Value::Str(format!(
            "{}:{}:{}.{}",
            wild(*h, 2),
            wild(*m, 2),
            wild(*s, 2),
            wild(*c, 2)
        )),
        AppValue::ObjectId(o) => Value::Str(o.to_string()),
        AppValue::Context(_, b) => Value::Bytes(b.clone()),
        AppValue::Constructed(_, items) => Value::Array(items.iter().map(to_value).collect()),
    }
}

/// The names of the four `status-flags`, bit 0 first.
const STATUS_FLAGS: [&str; 4] = ["in_alarm", "fault", "overridden", "out_of_service"];

fn point_err(m: impl Into<String>) -> DriverError {
    DriverError::Point(m.into())
}

/// A point's value from the property's value(s).
fn decode_point(p: &Point, values: &[AppValue]) -> Result<Value, DriverError> {
    let k = p.kind();
    if k == Kind::Relinquished {
        return match values {
            [one] => Ok(Value::Bool(*one == AppValue::Null)),
            _ => Err(point_err("expected one slot of the priority array")),
        };
    }
    if k == Kind::Dynamic {
        return Ok(match values {
            [one] => to_value(one),
            many => Value::Array(many.iter().map(to_value).collect()),
        });
    }
    let v = match values {
        [one] => one,
        [] => return Err(point_err("the reply has no value")),
        many => {
            return Err(point_err(format!(
                "expected one value, got {} (set dtype auto or an array index)",
                many.len()
            )))
        }
    };
    let mismatch = || {
        point_err(format!(
            "the device sent {} for a {:?} point",
            v.tag_name(),
            p.dtype
        ))
    };
    let number = |x: f64| {
        if p.scaled() {
            Value::Float(x * p.scale + p.offset)
        } else {
            Value::Float(x)
        }
    };
    Ok(match (k, v) {
        (_, AppValue::Null) => return Err(point_err("the device sent NULL (no value)")),
        (Kind::Boolean | Kind::BinaryPv, AppValue::Boolean(b)) => Value::Bool(*b),
        (Kind::Boolean | Kind::BinaryPv, AppValue::Enumerated(e)) => Value::Bool(*e != 0),
        (Kind::CharString, AppValue::CharString(s)) => Value::Str(s.clone()),
        (Kind::StatusFlags, AppValue::BitString(bits)) => Value::Map(
            STATUS_FLAGS
                .iter()
                .enumerate()
                .map(|(i, n)| ((*n).to_owned(), Value::Bool(bits.get(i) == Some(&true))))
                .collect(),
        ),
        (Kind::BitString, AppValue::BitString(bits)) => {
            Value::Array(bits.iter().map(|b| Value::Bool(*b)).collect())
        }
        (k, AppValue::Real(f)) if k.numeric() => number(real(*f)),
        (k, AppValue::Double(f)) if k.numeric() => number(*f),
        (k, AppValue::Unsigned(u)) if k.numeric() => {
            if p.scaled() {
                number(*u as f64)
            } else {
                Value::UInt(*u)
            }
        }
        (k, AppValue::Enumerated(e)) if k.numeric() => {
            if p.scaled() {
                number(f64::from(*e))
            } else {
                Value::UInt((*e).into())
            }
        }
        (k, AppValue::Signed(i)) if k.numeric() => {
            if p.scaled() {
                number(*i as f64)
            } else {
                Value::Int(*i)
            }
        }
        _ => return Err(mismatch()),
    })
}

/// `fault` set in `status-flags` (the second value of a point's read).
fn flags_fault(values: &[AppValue]) -> Option<String> {
    match values {
        [AppValue::BitString(bits)] if bits.get(1) == Some(&true) => {
            Some("status-flags: fault".to_owned())
        }
        _ => None,
    }
}

/// A point's result from the read of its value and (with `check_status`)
/// of its `status-flags`. Flags without an answer (their request timed
/// out) leave the fault check undone: no answer for the point either, so
/// the framework's ladder applies to it. Flags the device refuses (it has
/// none) do not hide the value.
fn point_result(
    p: &Point,
    value: &Result<Vec<AppValue>, DriverError>,
    flags: Option<&Result<Vec<AppValue>, DriverError>>,
) -> Result<Value, DriverError> {
    let values = value.as_ref().map_err(Clone::clone)?;
    match flags {
        Some(Err(e @ (DriverError::Device(_) | DriverError::Transport(_)))) => Err(e.clone()),
        Some(Ok(fl)) => match flags_fault(fl) {
            Some(fault) => Err(point_err(fault)),
            None => decode_point(p, values),
        },
        _ => decode_point(p, values),
    }
}

/// The application value written for `v` on point `p` (scale undone).
fn encode_point(p: &Point, v: &Value) -> Result<AppValue, DriverError> {
    let k = p.kind();
    let raw = |x: f64| (x - p.offset) / p.scale;
    let num = || -> Result<f64, DriverError> {
        match v {
            Value::UInt(u) => Ok(*u as f64),
            Value::Int(i) => Ok(*i as f64),
            Value::Float(f) => Ok(*f),
            _ => Err(point_err("expected a number")),
        }
        .map(raw)
    };
    let whole = |x: f64, min: f64, max: f64| -> Result<f64, DriverError> {
        let r = x.round();
        if !r.is_finite() || r < min || r > max {
            return Err(point_err(format!("{x} is out of range {min}…{max}")));
        }
        Ok(r)
    };
    Ok(match k {
        Kind::Real => {
            let x = num()?;
            if !x.is_finite() || x.abs() > f64::from(f32::MAX) {
                return Err(point_err(format!("{x} does not fit a REAL")));
            }
            AppValue::Real(x as f32)
        }
        Kind::Double => AppValue::Double(num()?),
        Kind::Unsigned => AppValue::Unsigned(whole(num()?, 0.0, f64::from(u32::MAX))? as u64),
        Kind::Enumerated => AppValue::Enumerated(whole(num()?, 0.0, f64::from(u32::MAX))? as u32),
        Kind::Signed => {
            AppValue::Signed(whole(num()?, f64::from(i32::MIN), f64::from(i32::MAX))? as i64)
        }
        Kind::Boolean => match v {
            Value::Bool(b) => AppValue::Boolean(*b),
            _ => return Err(point_err("expected true or false")),
        },
        Kind::BinaryPv => match v {
            Value::Bool(b) => AppValue::Enumerated(u32::from(*b)),
            _ => return Err(point_err("expected true or false")),
        },
        Kind::CharString => match v {
            Value::Str(s) => AppValue::CharString(s.clone()),
            _ => return Err(point_err("expected a string")),
        },
        Kind::BitString | Kind::StatusFlags => return Err(point_err("bit strings are read only")),
        Kind::Relinquished => match v {
            Value::Bool(true) => AppValue::Null,
            _ => {
                return Err(point_err(
                    "write true to relinquish; command a value on the object's value point",
                ))
            }
        },
        Kind::Dynamic => match v {
            Value::Null => AppValue::Null,
            Value::Bool(b) => AppValue::Boolean(*b),
            Value::UInt(u) => AppValue::Unsigned(*u),
            Value::Int(i) => AppValue::Signed(*i),
            Value::Float(f) => AppValue::Real(*f as f32),
            Value::Str(s) => AppValue::CharString(s.clone()),
            _ => return Err(point_err("this value type cannot be written")),
        },
    })
}

// ---------------------------------------------------------------- transport

/// Where a device is: its (or its router's) IP:port, and its network
/// address behind the router.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Peer {
    pub addr: SocketAddrV4,
    pub net: Option<NetAddr>,
}

impl Peer {
    fn describe(&self) -> String {
        match &self.net {
            None => self.addr.to_string(),
            Some(n) => format!("{} net {} mac {}", self.addr, n.net, hex(&n.mac)),
        }
    }
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02X}")).collect()
}

/// A device as configured (its state is kept per configuration).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct DevKey {
    instance: u32,
    address: String,
    network: u16,
    mac: String,
}

/// What the transport knows about one device.
#[derive(Debug, Default)]
struct DevState {
    peer: Option<Peer>,
    /// Max APDU the device accepts (I-Am, the param, or the default).
    max_apdu: Option<u16>,
    /// RPM is not supported: ReadProperty only.
    rpm_off: bool,
    /// Properties per RPM the device took at most (learned from aborts).
    max_items: Option<usize>,
    /// Unicast Who-Is for max APDU sent on this transport.
    asked: bool,
}

/// An I-Am heard on this connection.
#[derive(Debug, Clone)]
pub struct Heard {
    pub peer: Peer,
    pub iam: IAm,
}

/// Default max APDU of a device that does not tell (a common MS/TP size).
const DEFAULT_DEVICE_APDU: u16 = 480;

/// Diagnostics counters beside the standard ones.
const LATE: &str = "late_replies";
const SPLITS: &str = "rpm_splits";
const WHO_IS: &str = "who_is_sent";

/// A reply to a confirmed request.
#[derive(Debug, Clone, PartialEq)]
enum Reply {
    Simple,
    Complex(Vec<u8>),
    /// A segmented ComplexACK (not accepted).
    Segmented,
    Error(u32, u32),
    Reject(u8),
    Abort(u8),
}

/// Why a read did not give values.
#[derive(Debug, Clone, PartialEq)]
enum Fail {
    /// The service is not supported (RPM: fall back to ReadProperty).
    NotSupported(String),
    /// The reply would not fit without segmentation.
    TooBig(String),
    /// Error, Reject or Abort for the request.
    Refused(String),
    /// No reply, or the socket broke.
    Io(DriverError),
}

impl Fail {
    fn into_driver(self) -> DriverError {
        match self {
            Fail::NotSupported(m) | Fail::TooBig(m) | Fail::Refused(m) => DriverError::Point(m),
            Fail::Io(e) => e,
        }
    }
}

fn classify(service: u8, r: Reply) -> Result<Vec<u8>, Fail> {
    use codec::{abort, error, reject};
    match r {
        Reply::Complex(d) => Ok(d),
        Reply::Simple => Ok(Vec::new()),
        Reply::Segmented => Err(Fail::TooBig("the device sent a segmented reply".into())),
        Reply::Reject(reason) => {
            let m = format!("reject: {}", codec::reject_text(reason));
            Err(match reason {
                reject::UNRECOGNIZED_SERVICE => Fail::NotSupported(m),
                reject::BUFFER_OVERFLOW => Fail::TooBig(m),
                _ => Fail::Refused(m),
            })
        }
        Reply::Abort(reason) => {
            let m = format!("abort: {}", codec::abort_text(reason));
            Err(match reason {
                abort::SEGMENTATION_NOT_SUPPORTED
                | abort::BUFFER_OVERFLOW
                | abort::APDU_TOO_LONG => Fail::TooBig(m),
                _ => Fail::Refused(m),
            })
        }
        Reply::Error(class, code) => {
            let m = codec::error_text(class, code);
            let unsupported = class == error::CLASS_SERVICES
                && matches!(
                    code,
                    error::CODE_SERVICE_REQUEST_DENIED
                        | error::CODE_OPTIONAL_FUNCTIONALITY_NOT_SUPPORTED
                )
                && service == codec::service::READ_PROPERTY_MULTIPLE;
            Err(if unsupported {
                Fail::NotSupported(m)
            } else {
                Fail::Refused(m)
            })
        }
    }
}

/// What came in on the socket.
enum Incoming {
    Reply {
        peer: Peer,
        invoke_id: u8,
        /// The service the reply is for (none in a Reject or Abort).
        service: Option<u8>,
        reply: Reply,
    },
    IAm(Heard),
    BvlcResult {
        from: SocketAddrV4,
        code: u16,
    },
    Other,
}

/// Decode one datagram from `from`. A Forwarded-NPDU names its original
/// source; that is believed only from the configured `bbmd` (anyone else
/// could name any address), so one from elsewhere is dropped.
fn incoming(buf: &[u8], from: SocketAddr, bbmd: Option<SocketAddrV4>) -> Incoming {
    let SocketAddr::V4(from) = from else {
        return Incoming::Other;
    };
    let (origin, npdu) = match codec::parse_bvlc(buf) {
        Ok(Bvlc::Result(code)) => return Incoming::BvlcResult { from, code },
        Ok(Bvlc::Npdu {
            origin: Some(o),
            npdu,
            ..
        }) => {
            if bbmd != Some(from) {
                return Incoming::Other;
            }
            (o, npdu)
        }
        Ok(Bvlc::Npdu {
            origin: None, npdu, ..
        }) => (from, npdu),
        _ => return Incoming::Other,
    };
    let Ok(n) = codec::parse_npdu(npdu) else {
        return Incoming::Other;
    };
    if n.network_message {
        return Incoming::Other;
    }
    let peer = Peer {
        addr: origin,
        net: n.source.clone(),
    };
    let Ok(apdu) = codec::parse_apdu(n.apdu) else {
        return Incoming::Other;
    };
    let reply = match apdu {
        Apdu::Unconfirmed {
            service: codec::service::I_AM,
            data,
        } => {
            return match codec::parse_i_am(data) {
                Ok(iam) => Incoming::IAm(Heard { peer, iam }),
                Err(_) => Incoming::Other,
            }
        }
        Apdu::SimpleAck { .. } => Reply::Simple,
        Apdu::ComplexAck {
            segmented: true, ..
        } => Reply::Segmented,
        Apdu::ComplexAck { data, .. } => Reply::Complex(data.to_vec()),
        Apdu::Error { class, code, .. } => Reply::Error(class, code),
        Apdu::Reject { reason, .. } => Reply::Reject(reason),
        Apdu::Abort {
            server: true,
            reason,
            ..
        } => Reply::Abort(reason),
        _ => return Incoming::Other,
    };
    let service = match apdu {
        Apdu::SimpleAck { service, .. }
        | Apdu::ComplexAck { service, .. }
        | Apdu::Error { service, .. } => Some(service),
        _ => None,
    };
    match apdu.reply_invoke_id() {
        Some(invoke_id) => Incoming::Reply {
            peer,
            invoke_id,
            service,
            reply,
        },
        None => Incoming::Other,
    }
}

/// One read of a property, for [`Transport::read_many`].
#[derive(Debug, Clone, Copy)]
struct ReadItem {
    obj: ObjectId,
    prop: PropRef,
    /// Estimated octets of its value in a reply.
    est: usize,
}

/// A device ready for requests.
struct DevTarget {
    key: DevKey,
    peer: Peer,
    /// Largest APDU both ends take.
    limit: u16,
    use_rpm: bool,
    /// Found by Who-Is: forgotten when it stops answering.
    discovered: bool,
}

/// The open connection: one UDP socket for every device on it.
pub struct Transport {
    sock: UdpSocket,
    conn: Conn,
    broadcast: SocketAddrV4,
    bbmd: Option<SocketAddrV4>,
    /// When the foreign-device registration is renewed.
    reregister_at: Option<Instant>,
    devs: HashMap<DevKey, DevState>,
    outcomes: Vec<Outcome>,
    buf: Vec<u8>,
}

/// The next invoke id per remote peer, kept for the whole process: a
/// connection reopened on the same port (47808) goes on from where the old
/// socket stopped, so a late reply to the old socket is not taken for a
/// new request. Per peer: two tree devices that reach one device (an
/// address and Who-Is) share its id space.
static INVOKE_IDS: LazyLock<Mutex<HashMap<Peer, u8>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Peers remembered at most in [`INVOKE_IDS`] (only peers that requests go
/// to, so a bound that a real port never reaches).
const INVOKE_PEERS_MAX: usize = 65_536;

fn next_invoke_id(peer: &Peer) -> u8 {
    let mut ids = INVOKE_IDS.lock().unwrap_or_else(|e| e.into_inner());
    if ids.len() >= INVOKE_PEERS_MAX && !ids.contains_key(peer) {
        ids.clear();
    }
    let next = ids.entry(peer.clone()).or_default();
    let id = *next;
    *next = next.wrapping_add(1);
    id
}

fn io_err(what: &str, e: std::io::Error) -> DriverError {
    DriverError::Transport(format!("{what}: {e}"))
}

/// Receive errors that come from ICMP for an earlier datagram, not from
/// this socket (Windows reports them on unconnected UDP sockets).
fn transient(e: &std::io::Error) -> bool {
    matches!(
        e.kind(),
        std::io::ErrorKind::ConnectionReset | std::io::ErrorKind::ConnectionRefused
    )
}

impl Transport {
    async fn open(conn: &Conn) -> Result<Self, DriverError> {
        let ip: Ipv4Addr = conn.bind_host.trim().parse().map_err(|_| {
            DriverError::Transport(format!(
                "bind_host: {:?} is not an IPv4 address",
                conn.bind_host
            ))
        })?;
        let broadcast = parse_addr(&conn.broadcast)
            .map_err(|e| DriverError::Transport(format!("broadcast: {e}")))?;
        let bbmd = if conn.bbmd.trim().is_empty() {
            None
        } else {
            Some(parse_addr(&conn.bbmd).map_err(|e| DriverError::Transport(format!("bbmd: {e}")))?)
        };
        let bind = SocketAddrV4::new(ip, conn.bind_port);
        let sock = UdpSocket::bind(bind)
            .await
            .map_err(|e| io_err(&format!("bind {bind}"), e))?;
        sock.set_broadcast(true)
            .map_err(|e| io_err("enable broadcast", e))?;
        let mut t = Transport {
            sock,
            conn: conn.clone(),
            broadcast,
            bbmd,
            reregister_at: None,
            devs: HashMap::new(),
            outcomes: Vec::new(),
            buf: vec![0; 2048],
        };
        if t.bbmd.is_some() {
            t.register().await?;
        }
        Ok(t)
    }

    /// Foreign-device registration at the BBMD: renewed at half its TTL.
    async fn register(&mut self) -> Result<(), DriverError> {
        let Some(bbmd) = self.bbmd else {
            return Ok(());
        };
        let frame = codec::bvlc_register(self.conn.bbmd_ttl_s);
        for attempt in 0..=self.conn.apdu_retries {
            let sent = Instant::now();
            self.sock
                .send_to(&frame, bbmd)
                .await
                .map_err(|e| io_err(&format!("register at {bbmd}"), e))?;
            let deadline = sent + self.conn.timeout();
            while let Some(inc) = self.recv_until(deadline).await? {
                if let Incoming::BvlcResult { from, code } = inc {
                    if from != bbmd {
                        continue;
                    }
                    if code != 0 {
                        self.outcomes.push(Outcome::Exception(sent.elapsed()));
                        return Err(DriverError::Transport(format!(
                            "BBMD {bbmd} refused the foreign-device registration (result 0x{code:04X})"
                        )));
                    }
                    self.outcomes.push(Outcome::Reply(sent.elapsed()));
                    let half = Duration::from_secs(u64::from(self.conn.bbmd_ttl_s) / 2);
                    self.reregister_at = Some(Instant::now() + half);
                    debug!(%bbmd, "registered as a foreign device");
                    return Ok(());
                }
            }
            self.outcomes.push(Outcome::Timeout);
            debug!(attempt, %bbmd, "no reply to the foreign-device registration");
        }
        Err(DriverError::Transport(format!(
            "BBMD {bbmd} did not answer the foreign-device registration"
        )))
    }

    async fn renew(&mut self) -> Result<(), DriverError> {
        match self.reregister_at {
            Some(at) if Instant::now() >= at => self.register().await,
            _ => Ok(()),
        }
    }

    /// The next frame before `deadline` (`None` = the deadline passed).
    /// Nothing is remembered here: an I-Am counts only for the Who-Is that
    /// waits for it ([`Transport::collect_i_am`]).
    async fn recv_until(&mut self, deadline: Instant) -> Result<Option<Incoming>, DriverError> {
        loop {
            let r = tokio::time::timeout_at(deadline, self.sock.recv_from(&mut self.buf)).await;
            let (n, from) = match r {
                Err(_) => return Ok(None),
                Ok(Err(e)) if transient(&e) => continue,
                Ok(Err(e)) => return Err(io_err("receive", e)),
                Ok(Ok(x)) => x,
            };
            return Ok(Some(incoming(&self.buf[..n], from, self.bbmd)));
        }
    }

    async fn send(&mut self, frame: &[u8], to: SocketAddrV4) -> Result<(), DriverError> {
        match self.sock.send_to(frame, to).await {
            Ok(_) => Ok(()),
            // A route or host problem concerns that device, not the socket.
            Err(e) => {
                self.outcomes.push(Outcome::Error);
                Err(DriverError::Device(format!("send to {to}: {e}")))
            }
        }
    }

    /// One confirmed request to `peer`, sent again after a timeout up to
    /// `apdu_retries` times with the same invoke id. Only a reply from the
    /// peer with that invoke id counts; others are dropped.
    async fn confirmed(
        &mut self,
        peer: &Peer,
        service: u8,
        data: &[u8],
    ) -> Result<Reply, DriverError> {
        self.renew().await?;
        let invoke_id = next_invoke_id(peer);
        let apdu = codec::confirmed_request(invoke_id, service, self.conn.max_apdu, data);
        let mut npdu = Vec::with_capacity(apdu.len() + 8);
        codec::npdu_header(&mut npdu, peer.net.as_ref(), true);
        npdu.extend_from_slice(&apdu);
        let frame = codec::bvlc_wrap(codec::bvlc::ORIGINAL_UNICAST, &npdu);
        for attempt in 0..=self.conn.apdu_retries {
            let sent = Instant::now();
            self.send(&frame, peer.addr).await?;
            let deadline = sent + self.conn.timeout();
            while let Some(inc) = self.recv_until(deadline).await? {
                let Incoming::Reply {
                    peer: from,
                    invoke_id: id,
                    service: of,
                    reply,
                } = inc
                else {
                    continue;
                };
                if from != *peer {
                    continue;
                }
                // Reject and Abort name no service: the id alone.
                if id != invoke_id || of.is_some_and(|s| s != service) {
                    // A reply to an earlier request that timed out.
                    self.outcomes.push(Outcome::Count(LATE));
                    debug!(peer = %peer.describe(), id, invoke_id, "late reply dropped");
                    continue;
                }
                self.outcomes.push(match reply {
                    Reply::Simple | Reply::Complex(_) => Outcome::Reply(sent.elapsed()),
                    _ => Outcome::Exception(sent.elapsed()),
                });
                return Ok(reply);
            }
            self.outcomes.push(Outcome::Timeout);
            debug!(peer = %peer.describe(), attempt, invoke_id, "request timed out");
        }
        Err(DriverError::Device(format!(
            "no reply from {} after {} tries",
            peer.describe(),
            1 + u32::from(self.conn.apdu_retries)
        )))
    }

    /// Who-Is to every device (through the BBMD when registered), or
    /// unicast to `to`.
    async fn send_who_is(
        &mut self,
        range: Option<(u32, u32)>,
        to: Option<&Peer>,
    ) -> Result<(), DriverError> {
        let apdu = codec::who_is(range);
        let mut npdu = Vec::new();
        let frame = match to {
            Some(p) => {
                codec::npdu_header(&mut npdu, p.net.as_ref(), false);
                npdu.extend_from_slice(&apdu);
                codec::bvlc_wrap(codec::bvlc::ORIGINAL_UNICAST, &npdu)
            }
            None => {
                let global = NetAddr {
                    net: codec::GLOBAL_NET,
                    mac: Vec::new(),
                };
                codec::npdu_header(&mut npdu, Some(&global), false);
                npdu.extend_from_slice(&apdu);
                let f = if self.bbmd.is_some() {
                    codec::bvlc::DISTRIBUTE_BROADCAST
                } else {
                    codec::bvlc::ORIGINAL_BROADCAST
                };
                codec::bvlc_wrap(f, &npdu)
            }
        };
        let dest = match (to, self.bbmd) {
            (Some(p), _) => p.addr,
            (None, Some(b)) => b,
            (None, None) => self.broadcast,
        };
        self.renew().await?;
        self.outcomes.push(Outcome::Count(WHO_IS));
        self.send(&frame, dest).await
    }

    /// The I-Ams in `range` until `deadline` (the window of the Who-Is
    /// just sent), every answer kept: one device may answer from several
    /// addresses, or something else may answer for it. With `until`, the
    /// first I-Am from that peer ends the wait (only its answer counts).
    async fn collect_i_am(
        &mut self,
        range: Option<(u32, u32)>,
        deadline: Instant,
        until: Option<&Peer>,
    ) -> Result<BTreeMap<u32, Vec<Heard>>, DriverError> {
        let mut found: BTreeMap<u32, Vec<Heard>> = BTreeMap::new();
        while let Some(inc) = self.recv_until(deadline).await? {
            let Incoming::IAm(h) = inc else { continue };
            let inst = h.iam.device.instance;
            if range.is_some_and(|(lo, hi)| inst < lo || inst > hi) {
                continue;
            }
            let done = until.is_some_and(|p| *p == h.peer);
            let seen = found.entry(inst).or_default();
            if !seen.iter().any(|s| s.peer == h.peer) && seen.len() < 8 {
                seen.push(h);
            }
            if done {
                break;
            }
        }
        Ok(found)
    }

    /// The device's address and limits: the configured address or Who-Is,
    /// and its max APDU (param, I-Am, or [`DEFAULT_DEVICE_APDU`]).
    async fn target(&mut self, dev: &Dev) -> Result<DevTarget, DriverError> {
        let key = dev.key();
        let configured = dev.static_peer().map_err(DriverError::Point)?;
        let discovered = configured.is_none();
        let st = self.devs.entry(key.clone()).or_default();
        if st.peer.is_none() {
            st.peer = configured.clone();
        }
        let (peer, known_apdu, asked) = (st.peer.clone(), st.max_apdu, st.asked);
        let (peer, max) = match peer {
            Some(peer) => {
                let max = match (dev.max_apdu, known_apdu) {
                    (0, Some(m)) => m,
                    // the configured address answers its own Who-Is (only
                    // its answer counts: the binding is the address, and
                    // that answer ends the wait)
                    (0, None) if !asked => {
                        self.devs.entry(key.clone()).or_default().asked = true;
                        let range = Some((dev.instance, dev.instance));
                        self.send_who_is(range, Some(&peer)).await?;
                        let deadline = Instant::now() + self.conn.timeout();
                        self.collect_i_am(range, deadline, Some(&peer))
                            .await?
                            .remove(&dev.instance)
                            .and_then(|hs| hs.into_iter().find(|h| h.peer == peer))
                            .map_or(DEFAULT_DEVICE_APDU, |h| h.iam.max_apdu)
                    }
                    (0, None) => DEFAULT_DEVICE_APDU,
                    (m, _) => m,
                };
                (peer, max)
            }
            None => {
                let h = self.discover(dev.instance).await?;
                let max = if dev.max_apdu > 0 {
                    dev.max_apdu
                } else {
                    h.iam.max_apdu
                };
                debug!(device = dev.instance, peer = %h.peer.describe(), "found by Who-Is");
                (h.peer, max)
            }
        };
        let st = self.devs.entry(key.clone()).or_default();
        st.peer = Some(peer.clone());
        st.max_apdu = Some(max);
        let use_rpm = dev.use_rpm && !st.rpm_off;
        Ok(DevTarget {
            key,
            peer,
            limit: max.clamp(50, codec::MAX_APDU).min(self.conn.max_apdu),
            use_rpm,
            discovered,
        })
    }

    /// Bind a device without an address: Who-Is for its instance (with
    /// the connection's retries), waiting the whole window. Exactly one
    /// address must answer (two are refused: set the address), and it must
    /// then confirm the binding by a read of the device's
    /// `object-identifier`. A binding is kept until the device stops
    /// answering ([`Transport::forget`]); no I-Am replaces it.
    async fn discover(&mut self, instance: u32) -> Result<Heard, DriverError> {
        let range = Some((instance, instance));
        for _ in 0..=self.conn.apdu_retries {
            self.send_who_is(range, None).await?;
            let deadline = Instant::now() + self.conn.timeout();
            let mut answers = self
                .collect_i_am(range, deadline, None)
                .await?
                .remove(&instance)
                .unwrap_or_default();
            match answers.len() {
                0 => continue,
                1 => {
                    let h = answers.remove(0);
                    self.confirm(instance, &h.peer).await?;
                    return Ok(h);
                }
                _ => {
                    let at: Vec<String> = answers.iter().map(|h| h.peer.describe()).collect();
                    return Err(DriverError::Device(format!(
                        "device {instance} answered Who-Is from {}; set its address",
                        at.join(", ")
                    )));
                }
            }
        }
        Err(DriverError::Device(format!(
            "device {instance} did not answer Who-Is"
        )))
    }

    /// A new binding answers a read of its device object's identifier with
    /// that identifier.
    async fn confirm(&mut self, instance: u32, peer: &Peer) -> Result<(), DriverError> {
        let obj = ObjectId::new(ObjectId::DEVICE, instance);
        let prop = PropRef {
            id: codec::prop::OBJECT_IDENTIFIER,
            index: None,
        };
        let data = codec::read_property(obj, prop);
        let r = self
            .confirmed(peer, codec::service::READ_PROPERTY, &data)
            .await?;
        let ok = classify(codec::service::READ_PROPERTY, r)
            .ok()
            .and_then(|d| codec::parse_read_property_ack(&d).ok())
            .is_some_and(|(o, _, v)| o == obj && v == [AppValue::ObjectId(obj)]);
        if !ok {
            return Err(DriverError::Device(format!(
                "{} answered Who-Is for device {instance} but does not confirm it",
                peer.describe()
            )));
        }
        Ok(())
    }

    /// A device found by Who-Is that stopped answering is looked for again.
    fn forget(&mut self, t: &DevTarget) {
        if t.discovered {
            if let Some(st) = self.devs.get_mut(&t.key) {
                st.peer = None;
                st.max_apdu = None;
            }
        }
    }

    async fn read_property(
        &mut self,
        t: &DevTarget,
        item: &ReadItem,
    ) -> Result<Vec<AppValue>, Fail> {
        let data = codec::read_property(item.obj, item.prop);
        let r = self
            .confirmed(&t.peer, codec::service::READ_PROPERTY, &data)
            .await
            .map_err(Fail::Io)?;
        let d = classify(codec::service::READ_PROPERTY, r)?;
        let (obj, prop, values) = codec::parse_read_property_ack(&d)
            .map_err(|e| Fail::Refused(format!("bad ReadProperty-ACK: {e}")))?;
        if obj != item.obj || prop != item.prop {
            return Err(Fail::Refused(format!(
                "the reply is for {obj} property {}, not the one asked",
                prop.id
            )));
        }
        Ok(values)
    }

    /// One RPM of `items` → a result per item.
    async fn rpm(
        &mut self,
        t: &DevTarget,
        items: &[ReadItem],
    ) -> Result<Vec<Result<Vec<AppValue>, DriverError>>, Fail> {
        let specs = rpm_specs(items);
        let data = codec::read_property_multiple(&specs);
        let r = self
            .confirmed(&t.peer, codec::service::READ_PROPERTY_MULTIPLE, &data)
            .await
            .map_err(Fail::Io)?;
        let d = classify(codec::service::READ_PROPERTY_MULTIPLE, r)?;
        let results = codec::parse_read_property_multiple_ack(&d)
            .map_err(|e| Fail::Refused(format!("bad ReadPropertyMultiple-ACK: {e}")))?;
        let mut by: HashMap<(ObjectId, PropRef), codec::PropResult> = HashMap::new();
        for (obj, prop, res) in results {
            by.entry((obj, prop)).or_insert(res);
        }
        Ok(items
            .iter()
            .map(|i| match by.get(&(i.obj, i.prop)) {
                Some(Ok(v)) => Ok(v.clone()),
                Some(Err((class, code))) => Err(point_err(codec::error_text(*class, *code))),
                None => Err(point_err("the device left the property out of its reply")),
            })
            .collect())
    }

    /// Read `items` (RPM batches, or ReadProperty each). Stops at the first
    /// timeout (every unread item fails with it) and at `deadline`.
    async fn read_many(
        &mut self,
        t: &mut DevTarget,
        items: &[ReadItem],
        deadline: Option<Instant>,
    ) -> Vec<Result<Vec<AppValue>, DriverError>> {
        let mut out: Vec<Option<Result<Vec<AppValue>, DriverError>>> = vec![None; items.len()];
        let mut single: VecDeque<usize> = VecDeque::new();
        let fill = |out: &mut Vec<Option<Result<Vec<AppValue>, DriverError>>>, e: &DriverError| {
            for o in out.iter_mut().filter(|o| o.is_none()) {
                *o = Some(Err(e.clone()));
            }
        };
        let late = |d: Option<Instant>| d.is_some_and(|d| Instant::now() >= d);
        let time_up = DriverError::Device("stopped at the action's time limit".into());
        if t.use_rpm {
            let cap = self.devs.get(&t.key).and_then(|s| s.max_items);
            let mut queue: VecDeque<std::ops::Range<usize>> =
                chunks(items, t.limit, cap).into_iter().collect();
            while let Some(r) = queue.pop_front() {
                if late(deadline) {
                    fill(&mut out, &time_up);
                    break;
                }
                match self.rpm(t, &items[r.clone()]).await {
                    Ok(res) => {
                        for (i, v) in r.zip(res) {
                            out[i] = Some(v);
                        }
                    }
                    Err(Fail::NotSupported(m)) => {
                        info!(
                            device = t.key.instance,
                            "ReadPropertyMultiple not supported ({m}); ReadProperty from now on"
                        );
                        if let Some(st) = self.devs.get_mut(&t.key) {
                            st.rpm_off = true;
                        }
                        t.use_rpm = false;
                        single.extend(r);
                        for q in queue.drain(..) {
                            single.extend(q);
                        }
                    }
                    Err(Fail::TooBig(m)) if r.len() > 1 => {
                        let half = r.len() / 2;
                        debug!(device = t.key.instance, items = r.len(), "{m}; splitting");
                        self.outcomes.push(Outcome::Count(SPLITS));
                        if let Some(st) = self.devs.get_mut(&t.key) {
                            st.max_items = Some(st.max_items.map_or(half, |c| c.min(half)).max(1));
                        }
                        queue.push_front(r.start + half..r.end);
                        queue.push_front(r.start..r.start + half);
                    }
                    // The whole request refused: read each, so that one bad
                    // property does not fail the others.
                    Err(Fail::Refused(_)) if r.len() > 1 => single.extend(r),
                    Err(Fail::Io(e)) => {
                        if matches!(e, DriverError::Device(_)) {
                            self.forget(t);
                        }
                        fill(&mut out, &e);
                        return out.into_iter().flatten().collect();
                    }
                    Err(f) => {
                        let e = f.into_driver();
                        for i in r {
                            out[i] = Some(Err(e.clone()));
                        }
                    }
                }
            }
        } else {
            single.extend(0..items.len());
        }
        while let Some(i) = single.pop_front() {
            if out[i].is_some() {
                continue;
            }
            if late(deadline) {
                fill(&mut out, &time_up);
                break;
            }
            match self.read_property(t, &items[i]).await {
                Ok(v) => out[i] = Some(Ok(v)),
                Err(Fail::Io(e)) => {
                    if matches!(e, DriverError::Device(_)) {
                        self.forget(t);
                    }
                    fill(&mut out, &e);
                    break;
                }
                Err(f) => out[i] = Some(Err(f.into_driver())),
            }
        }
        out.into_iter()
            .map(|o| o.unwrap_or_else(|| Err(point_err("not read"))))
            .collect()
    }
}

/// RPM read specs of `items`: adjacent items of one object share a spec.
fn rpm_specs(items: &[ReadItem]) -> Vec<(ObjectId, Vec<PropRef>)> {
    let mut specs: Vec<(ObjectId, Vec<PropRef>)> = Vec::new();
    for i in items {
        match specs.last_mut() {
            Some((o, props)) if *o == i.obj => props.push(i.prop),
            _ => specs.push((i.obj, vec![i.prop])),
        }
    }
    specs
}

/// Octets of a context-tagged unsigned.
fn ctx_len(v: u32) -> usize {
    1 + match v {
        0..=0xFF => 1,
        0x100..=0xFFFF => 2,
        0x1_0000..=0xFF_FFFF => 3,
        _ => 4,
    }
}

/// Split `items` into RPM requests whose request and estimated reply fit
/// `limit` octets, with at most `cap` properties each.
fn chunks(items: &[ReadItem], limit: u16, cap: Option<usize>) -> Vec<std::ops::Range<usize>> {
    // APDU header: request 4 octets, ComplexACK 3.
    let limit = usize::from(limit);
    let mut out = Vec::new();
    let (mut start, mut req, mut rep) = (0usize, 4usize, 3usize);
    let mut last: Option<ObjectId> = None;
    for (i, it) in items.iter().enumerate() {
        let new_obj = last != Some(it.obj);
        let obj_cost = if new_obj { 5 + 2 } else { 0 };
        let index = it.prop.index.map_or(0, ctx_len);
        let prop = ctx_len(it.prop.id);
        let item_req = obj_cost + prop + index;
        let item_rep = obj_cost + prop + index + 2 + it.est;
        let full = cap.is_some_and(|c| i - start >= c);
        if i > start && (full || req + item_req > limit || rep + item_rep > limit) {
            out.push(start..i);
            start = i;
            req = 4 + 7 + prop + index;
            rep = 3 + 7 + prop + index + 2 + it.est;
        } else {
            req += item_req;
            rep += item_rep;
        }
        last = Some(it.obj);
    }
    if start < items.len() {
        out.push(start..items.len());
    }
    out
}

// ---------------------------------------------------------------- plan

/// The reads of one `(device, poll period)` group: each point's value and,
/// with `check_status`, its `status-flags`; sorted by object so that RPM
/// specs share objects.
pub struct Plan {
    members: Vec<(PointId, Point)>,
    items: Vec<ReadItem>,
    /// Per member: its value item and its flags item.
    slots: Vec<(usize, Option<usize>)>,
}

impl Plan {
    pub fn reads(&self) -> usize {
        self.items.len()
    }
}

// ---------------------------------------------------------------- actions

/// Bound on `list_objects`: below the gateway's wait on an action.
const LIST_ACTION_MS: u32 = 170_000;
/// What `list_objects` may use from its own start.
const LIST_BUDGET_MS: u64 = 160_000;
/// Bound on `who_is`: its longest wait and a margin.
const WHO_IS_MAX_WAIT_MS: u64 = 30_000;
const WHO_IS_ACTION_MS: u32 = 35_000;
/// Bound on `read_property` and `relinquish`.
const READ_ACTION_MS: u32 = 60_000;

fn uint_param(display: &str, desc: &str, default: Option<u64>) -> ParamMeta {
    ParamMeta {
        default: default.map(Value::UInt),
        ..ParamMeta::of(TypeCode::Number)
            .display(display)
            .description(desc)
    }
}

fn enum_param(display: &str, names: &[&str]) -> ParamMeta {
    ParamMeta::of(TypeCode::String)
        .enum_values(names.iter().copied())
        .display(display)
}

fn arg_uint(
    args: &BTreeMap<String, Value>,
    name: &str,
    default: Option<u64>,
    (min, max): (u64, u64),
) -> Result<Option<u64>, LinkError> {
    let Some(v) = args.get(name).filter(|v| **v != Value::Null) else {
        return Ok(default);
    };
    let n = match v {
        Value::UInt(u) => Some(*u),
        Value::Int(i) => u64::try_from(*i).ok(),
        Value::Float(f) if f.fract() == 0.0 && *f >= 0.0 && *f <= u64::MAX as f64 => {
            Some(*f as u64)
        }
        _ => None,
    }
    .ok_or_else(|| LinkError::invalid_parameter(format!("{name}: expected a whole number")))?;
    if !(min..=max).contains(&n) {
        return Err(LinkError::invalid_parameter(format!(
            "{name}: {n} is not in {min}…{max}"
        )));
    }
    Ok(Some(n))
}

fn required(v: Option<u64>, name: &str) -> Result<u64, LinkError> {
    v.ok_or_else(|| LinkError::invalid_parameter(format!("missing {name}")))
}

/// An object type by name or number.
fn arg_object_type(args: &BTreeMap<String, Value>) -> Result<u16, LinkError> {
    match args.get("object_type") {
        Some(Value::Str(s)) => (0..1024u16)
            .find(|t| codec::object_type_name(*t) == Some(s.as_str()))
            .ok_or_else(|| LinkError::invalid_parameter(format!("object_type: unknown {s}"))),
        Some(Value::UInt(u)) if *u < 1024 => Ok(*u as u16),
        Some(_) => Err(LinkError::invalid_parameter(
            "object_type: expected a name or a number below 1024",
        )),
        None => Err(LinkError::invalid_parameter("missing object_type")),
    }
}

/// All object type names (for the action forms).
fn object_type_names() -> Vec<&'static str> {
    (0..1024u16).map_while(codec::object_type_name).collect()
}

fn action_err(e: DriverError) -> LinkError {
    match e {
        DriverError::Transport(m) => LinkError::new(Status::Disconnected, m),
        DriverError::Device(m) => LinkError::timeout(m),
        DriverError::Point(m) => LinkError::new(Status::NotAvailable, m),
    }
}

fn fail_err(f: Fail) -> LinkError {
    match f {
        Fail::Io(e) => action_err(e),
        Fail::NotSupported(m) => LinkError::not_supported(m),
        Fail::TooBig(m) | Fail::Refused(m) => LinkError::new(Status::NotAvailable, m),
    }
}

fn args_of(args: &Value) -> BTreeMap<String, Value> {
    match args {
        Value::Map(m) => m.clone(),
        _ => BTreeMap::new(),
    }
}

/// `who_is {low?, high?, wait_ms = 3000}` → the devices that answered.
async fn who_is_action(
    t: &mut Transport,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let max = u64::from(codec::MAX_INSTANCE);
    let low = arg_uint(args, "low", None, (0, max))?;
    let high = arg_uint(args, "high", None, (0, max))?;
    let wait = required(
        arg_uint(args, "wait_ms", Some(3000), (100, WHO_IS_MAX_WAIT_MS))?,
        "wait_ms",
    )?;
    let range = match (low, high) {
        (None, None) => None,
        (Some(l), Some(h)) if l <= h => Some((l as u32, h as u32)),
        (Some(l), Some(h)) => {
            return Err(LinkError::invalid_parameter(format!(
                "low: {l} is above high ({h})"
            )))
        }
        _ => {
            return Err(LinkError::invalid_parameter(
                "low and high: give both or neither",
            ))
        }
    };
    t.send_who_is(range, None).await.map_err(action_err)?;
    let deadline = Instant::now() + Duration::from_millis(wait);
    let found = t
        .collect_i_am(range, deadline, None)
        .await
        .map_err(action_err)?;
    Ok(Value::Array(
        found
            .into_values()
            .flatten()
            .map(|h| {
                let mut m = BTreeMap::from([
                    (
                        "instance".to_owned(),
                        Value::UInt(h.iam.device.instance.into()),
                    ),
                    ("address".to_owned(), Value::Str(h.peer.addr.to_string())),
                    ("vendor_id".to_owned(), Value::UInt(h.iam.vendor_id.into())),
                    ("max_apdu".to_owned(), Value::UInt(h.iam.max_apdu.into())),
                    (
                        "segmentation".to_owned(),
                        Value::Str(
                            ["both", "transmit", "receive", "none"]
                                .get(h.iam.segmentation as usize)
                                .copied()
                                .unwrap_or("unknown")
                                .to_owned(),
                        ),
                    ),
                ]);
                if let Some(n) = &h.peer.net {
                    m.insert("network".into(), Value::UInt(n.net.into()));
                    m.insert("mac".into(), Value::Str(hex(&n.mac)));
                }
                Value::Map(m)
            })
            .collect(),
    ))
}

/// Object types whose objects have `units`.
fn has_units(ty: u16) -> bool {
    matches!(ty, 0 | 1 | 2 | 12 | 18 | 23 | 24 | 45 | 46 | 48)
}

/// `list_objects {limit = 1000}`: the device's `object-list` (whole, or
/// index by index when the whole list does not fit one reply), then each
/// object's name (and units).
async fn list_objects(
    t: &mut Transport,
    dev: &Dev,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let limit = required(arg_uint(args, "limit", Some(1000), (1, 10_000))?, "limit")? as usize;
    let deadline = Instant::now() + Duration::from_millis(LIST_BUDGET_MS);
    let mut tg = t.target(dev).await.map_err(action_err)?;
    let dev_obj = ObjectId::new(ObjectId::DEVICE, dev.instance);
    let whole = ReadItem {
        obj: dev_obj,
        prop: PropRef {
            id: codec::prop::OBJECT_LIST,
            index: None,
        },
        est: 0,
    };
    let ids = |values: &[AppValue]| -> Vec<ObjectId> {
        values
            .iter()
            .filter_map(|v| match v {
                AppValue::ObjectId(o) => Some(*o),
                _ => None,
            })
            .collect()
    };
    let (mut objects, total) = match t.read_property(&tg, &whole).await {
        Ok(values) => {
            let all = ids(&values);
            let n = all.len();
            (all, n)
        }
        Err(Fail::Io(e)) => return Err(action_err(e)),
        // Too long for one reply (no segmentation): read the length, then
        // the entries.
        Err(Fail::TooBig(_) | Fail::Refused(_)) => {
            let len_item = ReadItem {
                prop: PropRef {
                    id: codec::prop::OBJECT_LIST,
                    index: Some(0),
                },
                ..whole
            };
            let len = match t
                .read_property(&tg, &len_item)
                .await
                .map_err(fail_err)?
                .as_slice()
            {
                [AppValue::Unsigned(n)] => *n as usize,
                _ => {
                    return Err(LinkError::new(
                        Status::NotAvailable,
                        "object-list[0] is not a length",
                    ))
                }
            };
            let entries: Vec<ReadItem> = (1..=len.min(limit) as u32)
                .map(|i| ReadItem {
                    prop: PropRef {
                        id: codec::prop::OBJECT_LIST,
                        index: Some(i),
                    },
                    est: 5,
                    ..whole
                })
                .collect();
            let res = t.read_many(&mut tg, &entries, Some(deadline)).await;
            let mut objs = Vec::new();
            for r in res {
                match r {
                    Ok(v) => objs.extend(ids(&v)),
                    Err(DriverError::Point(_)) => {}
                    Err(e) => {
                        if objs.is_empty() {
                            return Err(action_err(e));
                        }
                        break;
                    }
                }
            }
            (objs, len)
        }
        Err(f) => return Err(fail_err(f)),
    };
    objects.truncate(limit);
    let mut reads = Vec::new();
    for o in &objects {
        reads.push(ReadItem {
            obj: *o,
            prop: PropRef {
                id: codec::prop::OBJECT_NAME,
                index: None,
            },
            est: Kind::CharString.reply_octets(),
        });
        if has_units(o.ty) {
            reads.push(ReadItem {
                obj: *o,
                prop: PropRef {
                    id: codec::prop::UNITS,
                    index: None,
                },
                est: 5,
            });
        }
    }
    let res = t.read_many(&mut tg, &reads, Some(deadline)).await;
    let mut got: HashMap<(ObjectId, u32), Value> = HashMap::new();
    let mut truncated = objects.len() < total;
    for (it, r) in reads.iter().zip(res) {
        match r {
            Ok(v) => {
                if let Some(first) = v.first() {
                    got.insert((it.obj, it.prop.id), to_value(first));
                }
            }
            Err(DriverError::Point(_)) => {}
            Err(_) => truncated = true,
        }
    }
    let list = objects
        .iter()
        .map(|o| {
            let mut m = BTreeMap::from([
                (
                    "object_type".to_owned(),
                    codec::object_type_name(o.ty)
                        .map_or_else(|| Value::UInt(o.ty.into()), |n| Value::Str(n.into())),
                ),
                ("instance".to_owned(), Value::UInt(o.instance.into())),
            ]);
            if let Some(n) = got.get(&(*o, codec::prop::OBJECT_NAME)) {
                m.insert("name".into(), n.clone());
            }
            if let Some(Value::UInt(u)) = got.get(&(*o, codec::prop::UNITS)) {
                let (name, sym) = codec::unit(*u as u32);
                m.insert("units".into(), Value::Str(name));
                m.insert("unit".into(), Value::Str(sym.into()));
            }
            Value::Map(m)
        })
        .collect();
    Ok(Value::Map(BTreeMap::from([
        ("objects".into(), Value::Array(list)),
        ("count".into(), Value::UInt(total as u64)),
        ("truncated".into(), Value::Bool(truncated)),
    ])))
}

/// A property by name (point names, plus a few) or number.
fn arg_property(args: &BTreeMap<String, Value>) -> Result<u32, LinkError> {
    match args.get("property") {
        None | Some(Value::Null) => Ok(codec::prop::PRESENT_VALUE),
        Some(Value::UInt(u)) if *u <= 4_194_303 => Ok(*u as u32),
        Some(Value::Str(s)) => match s.as_str() {
            "object_list" => Ok(codec::prop::OBJECT_LIST),
            "object_identifier" => Ok(codec::prop::OBJECT_IDENTIFIER),
            "object_type" => Ok(codec::prop::OBJECT_TYPE),
            "vendor_identifier" => Ok(codec::prop::VENDOR_IDENTIFIER),
            "max_apdu_length_accepted" => Ok(codec::prop::MAX_APDU_LENGTH_ACCEPTED),
            "segmentation_supported" => Ok(codec::prop::SEGMENTATION_SUPPORTED),
            "number_of_states" => Ok(codec::prop::NUMBER_OF_STATES),
            other => Property::from_name(other)
                .and_then(Property::id)
                .ok_or_else(|| LinkError::invalid_parameter(format!("property: unknown {other}"))),
        },
        Some(_) => Err(LinkError::invalid_parameter(
            "property: expected a name or a property id",
        )),
    }
}

const EXTRA_PROPERTIES: [&str; 7] = [
    "object_list",
    "object_identifier",
    "object_type",
    "vendor_identifier",
    "max_apdu_length_accepted",
    "segmentation_supported",
    "number_of_states",
];

/// `read_property {object_type, instance, property = present_value,
/// array_index?}` → `{value}` (the values as they came, an array when
/// there are several).
async fn read_property_action(
    t: &mut Transport,
    dev: &Dev,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let ty = arg_object_type(args)?;
    let instance = required(
        arg_uint(
            args,
            "instance",
            None,
            (0, u64::from(codec::WILDCARD_INSTANCE)),
        )?,
        "instance",
    )? as u32;
    let id = arg_property(args)?;
    let index =
        arg_uint(args, "array_index", None, (0, u64::from(u32::MAX - 1)))?.map(|i| i as u32);
    let tg = t.target(dev).await.map_err(action_err)?;
    let item = ReadItem {
        obj: ObjectId::new(ty, instance),
        prop: PropRef { id, index },
        est: 0,
    };
    let values = t.read_property(&tg, &item).await.map_err(|f| {
        if let Fail::Io(DriverError::Device(_)) = &f {
            t.forget(&tg);
        }
        fail_err(f)
    })?;
    let value = match values.as_slice() {
        [one] => to_value(one),
        many => Value::Array(many.iter().map(to_value).collect()),
    };
    let mut m = BTreeMap::from([("value".to_owned(), value)]);
    if id == codec::prop::UNITS {
        if let [AppValue::Enumerated(u)] = values.as_slice() {
            let (name, sym) = codec::unit(*u);
            m.insert("units".into(), Value::Str(name));
            m.insert("unit".into(), Value::Str(sym.into()));
        }
    }
    Ok(Value::Map(m))
}

/// `relinquish {object_type, instance, priority = 16}`: write NULL to
/// `present-value` at that priority → `{}` (the next poll shows the value
/// the object falls back to).
async fn relinquish(
    t: &mut Transport,
    dev: &Dev,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let ty = arg_object_type(args)?;
    let instance = required(
        arg_uint(args, "instance", None, (0, u64::from(codec::MAX_INSTANCE)))?,
        "instance",
    )? as u32;
    let priority = required(arg_uint(args, "priority", Some(16), (1, 16))?, "priority")? as u8;
    let tg = t.target(dev).await.map_err(action_err)?;
    let data = codec::write_property(
        ObjectId::new(ty, instance),
        PropRef {
            id: codec::prop::PRESENT_VALUE,
            index: None,
        },
        &AppValue::Null,
        Some(priority),
    );
    let r = t
        .confirmed(&tg.peer, codec::service::WRITE_PROPERTY, &data)
        .await
        .map_err(action_err)?;
    classify(codec::service::WRITE_PROPERTY, r).map_err(fail_err)?;
    info!(device = dev.instance, object = %ObjectId::new(ty, instance), priority, "relinquished");
    Ok(Value::Map(BTreeMap::new()))
}

// ---------------------------------------------------------------- driver

pub struct BacnetDriver;

impl Driver for BacnetDriver {
    const NAME: &'static str = "bacnet";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        Transport::open(conn).await
    }

    /// ReadProperty of the device object's `system-status`: any reply means
    /// the device is alive.
    async fn ping(t: &mut Transport, dev: &Dev) -> Result<(), DriverError> {
        let tg = t.target(dev).await?;
        let item = ReadItem {
            obj: ObjectId::new(ObjectId::DEVICE, dev.instance),
            prop: PropRef {
                id: codec::prop::SYSTEM_STATUS,
                index: None,
            },
            est: 5,
        };
        match t.read_property(&tg, &item).await {
            Ok(_) | Err(Fail::NotSupported(_) | Fail::TooBig(_) | Fail::Refused(_)) => Ok(()),
            Err(Fail::Io(e)) => {
                if matches!(e, DriverError::Device(_)) {
                    t.forget(&tg);
                }
                Err(e)
            }
        }
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Plan {
        let members: Vec<(PointId, Point)> = points.to_vec();
        let mut items: Vec<(usize, bool, ReadItem)> = Vec::new();
        for (m, (_, p)) in members.iter().enumerate() {
            items.push((
                m,
                false,
                ReadItem {
                    obj: p.object(),
                    prop: p.prop(),
                    est: p.kind().reply_octets(),
                },
            ));
            if p.reads_flags() {
                items.push((
                    m,
                    true,
                    ReadItem {
                        obj: p.object(),
                        prop: PropRef {
                            id: codec::prop::STATUS_FLAGS,
                            index: None,
                        },
                        est: Kind::StatusFlags.reply_octets(),
                    },
                ));
            }
        }
        // one spec per object; a read shared by points is sent once
        items.sort_by_key(|(m, flags, it)| (it.obj, it.prop, *m, *flags));
        let mut plan = Plan {
            slots: vec![(0, None); members.len()],
            members,
            items: Vec::new(),
        };
        for (m, flags, it) in items {
            let idx = match plan.items.last() {
                Some(last) if last.obj == it.obj && last.prop == it.prop => plan.items.len() - 1,
                _ => {
                    plan.items.push(it);
                    plan.items.len() - 1
                }
            };
            if flags {
                plan.slots[m].1 = Some(idx);
            } else {
                plan.slots[m].0 = idx;
            }
        }
        plan
    }

    async fn poll(
        t: &mut Transport,
        dev: &Dev,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let mut tg = match t.target(dev).await {
            Ok(tg) => tg,
            Err(e) => {
                return plan
                    .members
                    .iter()
                    .map(|(id, _)| (id.clone(), Err(e.clone())))
                    .collect()
            }
        };
        let res = t.read_many(&mut tg, &plan.items, None).await;
        plan.members
            .iter()
            .zip(&plan.slots)
            .map(|((id, p), (v, flags))| {
                (id.clone(), point_result(p, &res[*v], flags.map(|f| &res[f])))
            })
            .collect()
    }

    async fn write(
        t: &mut Transport,
        dev: &Dev,
        _id: &str,
        p: &Point,
        v: &Value,
    ) -> Result<(), DriverError> {
        if !p.writable {
            return Err(point_err("point is not writable"));
        }
        let value = encode_point(p, v)?;
        let tg = t.target(dev).await?;
        let data = codec::write_property(p.object(), p.write_prop(), &value, Some(p.priority));
        let r = t
            .confirmed(&tg.peer, codec::service::WRITE_PROPERTY, &data)
            .await
            .inspect_err(|e| {
                if matches!(e, DriverError::Device(_)) {
                    t.forget(&tg);
                }
            })?;
        classify(codec::service::WRITE_PROPERTY, r)
            .map(|_| ())
            .map_err(|f| match f {
                Fail::Io(e) => e,
                f => point_err(format!("write: {}", f.into_driver_text())),
            })
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = NodeMeta::leaf(p.kind().type_code());
        if !p.unit.is_empty() {
            m = m.unit(p.unit.clone());
        }
        m.writable(if p.writable {
            Writable::Write
        } else {
            Writable::Never
        })
    }

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.poll_s)
    }

    fn ping_period(dev: &Dev) -> Option<Duration> {
        (dev.ping_s > 0.0).then(|| Duration::from_secs_f64(dev.ping_s))
    }

    /// A ping: Who-Is (with retries), a unicast Who-Is for the max APDU,
    /// the request (with retries); opening: the BBMD registration.
    fn io_timeout(conn: &Conn) -> Duration {
        conn.per_request() * 2 + conn.timeout() + Duration::from_secs(1)
    }

    /// Finding the device, then one request per read at worst (ReadProperty
    /// after RPM was refused); a poll stops at its first timeout.
    fn poll_timeout(conn: &Conn, plan: &Plan) -> Duration {
        let n = u32::try_from(plan.reads())
            .unwrap_or(u32::MAX)
            .saturating_add(1);
        conn.per_request().saturating_mul(n) + conn.timeout() + Duration::from_secs(1)
    }

    fn write_timeout(conn: &Conn, _p: &Point) -> Duration {
        Self::io_timeout(conn)
    }

    fn republish(dev: &Dev) -> Option<Duration> {
        (dev.republish_s > 0.0).then(|| Duration::from_secs_f64(dev.republish_s))
    }

    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        let types = object_type_names();
        let mut props: Vec<&str> = Property::NAMES
            .iter()
            .copied()
            .filter(|n| !matches!(*n, "other" | "relinquish"))
            .collect();
        props.extend(EXTRA_PROPERTIES);
        match level {
            Level::Connection => vec![(
                "who_is",
                ActionMeta::new()
                    .level(Perm::Config)
                    .display("Who-Is")
                    .timeout_ms(WHO_IS_ACTION_MS)
                    .result(ActionResult::Type(TypeCode::Array))
                    .param(
                        "low",
                        uint_param("Low Instance", "with high; empty = all", None),
                    )
                    .param("high", uint_param("High Instance", "with low", None))
                    .param(
                        "wait_ms",
                        uint_param(
                            "Wait (ms)",
                            "how long to collect I-Am, 100…30000",
                            Some(3000),
                        ),
                    ),
            )],
            Level::Device => vec![
                (
                    "list_objects",
                    // commissioning: it holds the connection's owner task
                    // for up to thousands of requests, so polling of every
                    // device on the port waits (config, as modbus
                    // scan_units); read_property is one request (read)
                    ActionMeta::new()
                        .level(Perm::Config)
                        .display("List Objects")
                        .timeout_ms(LIST_ACTION_MS)
                        .result(ActionResult::Type(TypeCode::Map))
                        .param(
                            "limit",
                            uint_param("Limit", "objects at most, 1…10000", Some(1000)),
                        ),
                ),
                (
                    "read_property",
                    ActionMeta::new()
                        .level(Perm::Read)
                        .display("Read Property")
                        .timeout_ms(READ_ACTION_MS)
                        .result(ActionResult::Type(TypeCode::Map))
                        .param(
                            "object_type",
                            enum_param("Object Type", &types).required(true),
                        )
                        .param(
                            "instance",
                            uint_param("Object Instance", "", None).required(true),
                        )
                        .param("property", enum_param("Property", &props))
                        .param(
                            "array_index",
                            uint_param("Array Index", "empty = the whole property", None),
                        ),
                ),
                (
                    "relinquish",
                    // any object and priority (commissioning): config; a
                    // relinquish point gives write users their own priority
                    ActionMeta::new()
                        .level(Perm::Config)
                        .display("Relinquish")
                        .timeout_ms(READ_ACTION_MS)
                        .result(ActionResult::Type(TypeCode::Map))
                        .param(
                            "object_type",
                            enum_param("Object Type", &types).required(true),
                        )
                        .param(
                            "instance",
                            uint_param("Object Instance", "", None).required(true),
                        )
                        .param(
                            "priority",
                            uint_param("Priority", "1…16; NULL is written there", Some(16)),
                        ),
                ),
            ],
        }
    }

    async fn invoke(
        t: &mut Transport,
        _conn: &Conn,
        target: Target<'_, Self>,
        action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        let args = args_of(args);
        match (target, action) {
            (Target::Connection, "who_is") => who_is_action(t, &args).await,
            (Target::Device { dev, .. }, "list_objects") => list_objects(t, dev, &args).await,
            (Target::Device { dev, .. }, "read_property") => {
                read_property_action(t, dev, &args).await
            }
            (Target::Device { dev, .. }, "relinquish") => relinquish(t, dev, &args).await,
            _ => Err(LinkError::not_supported(format!("action {action}"))),
        }
    }

    const DIAGNOSTICS: bool = true;
    const DIAG_EXTRA: &'static [&'static str] = &[LATE, SPLITS, WHO_IS];

    fn take_outcomes(t: &mut Transport) -> Vec<Outcome> {
        std::mem::take(&mut t.outcomes)
    }
}

impl Fail {
    fn into_driver_text(self) -> String {
        match self {
            Fail::NotSupported(m) | Fail::TooBig(m) | Fail::Refused(m) => m,
            Fail::Io(e) => e.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(ty: u16, inst: u32, prop: u32, est: usize) -> ReadItem {
        ReadItem {
            obj: ObjectId::new(ty, inst),
            prop: PropRef {
                id: prop,
                index: None,
            },
            est,
        }
    }

    fn point(kv: &[(&str, Value)]) -> wyrm_link_sdk::Result<Point> {
        let m: BTreeMap<String, Value> = kv
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect();
        Point::from_value(&Value::Map(m))
    }

    fn ai(extra: &[(&str, Value)]) -> Point {
        let mut kv = vec![
            ("object_type", Value::from("analog_input")),
            ("instance", Value::UInt(1)),
        ];
        kv.extend_from_slice(extra);
        point(&kv).unwrap()
    }

    #[test]
    fn chunks_fit_the_limit() {
        // 100 REAL present-values of 100 objects: 7 + 2 + 2 + 5 = 16 octets
        // each in the reply.
        let items: Vec<ReadItem> = (0..100).map(|i| item(0, i, 85, 5)).collect();
        let c = chunks(&items, 480, None);
        assert!(c.len() > 1);
        for r in &c {
            let specs = rpm_specs(&items[r.clone()]);
            assert!(codec::rpm_request_size(&specs) + 4 <= 480);
            assert!(3 + r.len() * 16 <= 480, "{r:?}");
        }
        assert_eq!(c.iter().map(|r| r.len()).sum::<usize>(), 100);
        assert_eq!(c[0].start, 0);
        // one object, many properties: the object costs once
        let one: Vec<ReadItem> = (0..10).map(|p| item(2, 1, 80 + p, 5)).collect();
        assert_eq!(chunks(&one, 1476, None), vec![0..10]);
        // a cap on properties per request
        assert_eq!(chunks(&one, 1476, Some(4)), vec![0..4, 4..8, 8..10]);
        // a single item larger than the limit still goes alone
        let big = vec![item(2, 1, 77, 2000), item(2, 1, 85, 5)];
        assert_eq!(chunks(&big, 480, None), vec![0..1, 1..2]);
        assert!(chunks(&[], 480, None).is_empty());
    }

    /// The value answered but its `status-flags` (in a later request) did
    /// not: the fault check could not run, so no `good` value.
    #[test]
    fn point_without_its_flags_is_not_good() {
        let p = ai(&[]);
        let v = Ok(vec![AppValue::Real(1.0)]);
        let ok_flags = Ok(vec![AppValue::BitString(vec![false; 4])]);
        let fault = Ok(vec![AppValue::BitString(vec![false, true, false, false])]);
        let timeout = Err(DriverError::Device("no reply".into()));
        let refused = Err(point_err("property: unknown-property"));
        assert_eq!(point_result(&p, &v, Some(&ok_flags)), Ok(Value::Float(1.0)));
        assert_eq!(point_result(&p, &v, None), Ok(Value::Float(1.0)));
        assert!(matches!(
            point_result(&p, &v, Some(&fault)),
            Err(DriverError::Point(_))
        ));
        assert!(matches!(
            point_result(&p, &v, Some(&timeout)),
            Err(DriverError::Device(_))
        ));
        // a device without status-flags still gives the value
        assert_eq!(point_result(&p, &v, Some(&refused)), Ok(Value::Float(1.0)));
        assert!(matches!(
            point_result(&p, &timeout, Some(&ok_flags)),
            Err(DriverError::Device(_))
        ));
    }

    #[test]
    fn point_kinds_and_values() {
        let p = ai(&[]);
        assert_eq!(p.kind(), Kind::Real);
        assert_eq!(
            decode_point(&p, &[AppValue::Real(21.5)]).unwrap(),
            Value::Float(21.5)
        );
        assert_eq!(
            decode_point(&p, &[AppValue::Real(0.1)]).unwrap(),
            Value::Float(0.1)
        );
        let s = ai(&[("scale", Value::Float(10.0)), ("offset", Value::Float(1.0))]);
        assert_eq!(
            decode_point(&s, &[AppValue::Real(2.5)]).unwrap(),
            Value::Float(26.0)
        );
        assert_eq!(
            encode_point(&s, &Value::Float(26.0)).unwrap(),
            AppValue::Real(2.5)
        );
        let bi = point(&[
            ("object_type", "binary_input".into()),
            ("instance", Value::UInt(1)),
        ])
        .unwrap();
        assert_eq!(bi.kind(), Kind::BinaryPv);
        assert_eq!(
            decode_point(&bi, &[AppValue::Enumerated(1)]).unwrap(),
            Value::Bool(true)
        );
        assert_eq!(
            encode_point(&bi, &Value::Bool(true)).unwrap(),
            AppValue::Enumerated(1)
        );
        let msv = point(&[
            ("object_type", "multi_state_value".into()),
            ("instance", Value::UInt(1)),
        ])
        .unwrap();
        assert_eq!(
            decode_point(&msv, &[AppValue::Unsigned(3)]).unwrap(),
            Value::UInt(3)
        );
        assert_eq!(
            encode_point(&msv, &Value::UInt(2)).unwrap(),
            AppValue::Unsigned(2)
        );
        assert!(encode_point(&msv, &Value::Int(-1)).is_err());
        let iv = point(&[
            ("object_type", "integer_value".into()),
            ("instance", Value::UInt(1)),
        ])
        .unwrap();
        assert_eq!(
            decode_point(&iv, &[AppValue::Signed(-5)]).unwrap(),
            Value::Int(-5)
        );
        let lav = point(&[
            ("object_type", "large_analog_value".into()),
            ("instance", Value::UInt(1)),
        ])
        .unwrap();
        assert_eq!(
            decode_point(&lav, &[AppValue::Double(1e300)]).unwrap(),
            Value::Float(1e300)
        );
        assert_eq!(
            encode_point(&lav, &Value::Float(1.5)).unwrap(),
            AppValue::Double(1.5)
        );
        // REAL range
        assert!(encode_point(&p, &Value::Float(1e300)).is_err());
        let flags = ai(&[("property", "status_flags".into())]);
        assert_eq!(flags.kind(), Kind::StatusFlags);
        let v = decode_point(
            &flags,
            &[AppValue::BitString(vec![false, true, false, true])],
        )
        .unwrap();
        let Value::Map(m) = v else { panic!() };
        assert_eq!(m["fault"], Value::Bool(true));
        assert_eq!(m["out_of_service"], Value::Bool(true));
        assert_eq!(m["in_alarm"], Value::Bool(false));
        let rel = ai(&[("property", "reliability".into())]);
        assert_eq!(
            decode_point(&rel, &[AppValue::Enumerated(7)]).unwrap(),
            Value::UInt(7)
        );
        let name = ai(&[("property", "object_name".into())]);
        assert_eq!(
            decode_point(&name, &[AppValue::CharString("AHU-1".into())]).unwrap(),
            Value::from("AHU-1")
        );
        let bits = ai(&[
            ("property", "other".into()),
            ("property_id", Value::UInt(999)),
            ("dtype", "bit_string".into()),
        ]);
        assert_eq!(
            decode_point(&bits, &[AppValue::BitString(vec![true, false])]).unwrap(),
            Value::Array(vec![Value::Bool(true), Value::Bool(false)])
        );
        let dynamic = ai(&[("property", "priority_array".into())]);
        assert_eq!(
            decode_point(&dynamic, &[AppValue::Null, AppValue::Real(1.0)]).unwrap(),
            Value::Array(vec![Value::Null, Value::Float(1.0)])
        );
        // mismatches and NULL are point errors, never a made-up value
        assert!(decode_point(&p, &[AppValue::CharString("x".into())]).is_err());
        assert!(decode_point(&p, &[AppValue::Null]).is_err());
        assert!(decode_point(&p, &[]).is_err());
        assert!(decode_point(&p, &[AppValue::Real(1.0), AppValue::Real(2.0)]).is_err());
        assert!(encode_point(&p, &Value::from("x")).is_err());
        // an explicit tag
        let u = ai(&[("dtype", "unsigned".into())]);
        assert_eq!(
            encode_point(&u, &Value::Float(4.4)).unwrap(),
            AppValue::Unsigned(4)
        );
        assert_eq!(
            flags_fault(&[AppValue::BitString(vec![false, true, false, false])]).as_deref(),
            Some("status-flags: fault")
        );
        assert_eq!(
            flags_fault(&[AppValue::BitString(vec![true, false, true, true])]),
            None
        );
    }

    #[test]
    fn point_params_bounds_and_rules() {
        for bad in [
            vec![("instance", Value::UInt(4_194_304))],
            vec![("priority", Value::UInt(0))],
            vec![("priority", Value::UInt(17))],
            vec![("scale", Value::Float(0.0))],
            vec![("property_id", Value::UInt(5))],
            vec![
                ("property", "status_flags".into()),
                ("writable", Value::Bool(true)),
            ],
            vec![
                ("property", "object_name".into()),
                ("scale", Value::Float(2.0)),
            ],
            vec![("array_index", Value::Int(-2))],
            vec![("poll_s", Value::Float(0.0))],
            vec![("object_type", "bogus".into())],
            // a relinquish point uses its priority, nothing else
            vec![
                ("property", "relinquish".into()),
                ("array_index", Value::UInt(3)),
            ],
            vec![("property", "relinquish".into()), ("dtype", "real".into())],
        ] {
            let mut kv = vec![
                ("object_type", Value::from("analog_input")),
                ("instance", Value::UInt(1)),
            ];
            for (k, v) in &bad {
                kv.retain(|(n, _)| n != k);
                kv.push((k, v.clone()));
            }
            assert!(point(&kv).is_err(), "{bad:?}");
        }
        let p = ai(&[
            ("array_index", Value::UInt(3)),
            ("writable", Value::Bool(true)),
        ]);
        assert_eq!(
            p.prop(),
            PropRef {
                id: 85,
                index: Some(3)
            }
        );
        assert_eq!(p.priority, 16);
        assert_eq!(Point::from_value(&p.to_value()).unwrap(), p);
        let other = ai(&[
            ("property", "other".into()),
            ("property_id", Value::UInt(4000)),
        ]);
        assert_eq!(other.prop().id, 4000);
        assert_eq!(other.kind(), Kind::Dynamic);
        let meta = BacnetDriver::point_meta(&ai(&[("unit", "°C".into())]));
        assert_eq!(meta.ty, Some(TypeCode::Number));
    }

    #[test]
    fn device_params() {
        let d = |kv: &[(&str, Value)]| {
            let mut m: BTreeMap<String, Value> = kv
                .iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect();
            m.entry("instance".into()).or_insert(Value::UInt(7));
            Dev::from_value(&Value::Map(m))
        };
        let ok = d(&[]).unwrap();
        assert!(ok.use_rpm && ok.address.is_empty() && ok.max_apdu == 0);
        assert_eq!(ok.static_peer().unwrap(), None);
        let s = d(&[("address", "10.0.0.5".into())]).unwrap();
        assert_eq!(
            s.static_peer().unwrap().unwrap().addr,
            "10.0.0.5:47808".parse().unwrap()
        );
        let r = d(&[
            ("address", "10.0.0.1:47809".into()),
            ("network", Value::UInt(5)),
            ("mac", "0A".into()),
        ])
        .unwrap();
        assert_eq!(
            r.static_peer().unwrap().unwrap().net,
            Some(NetAddr {
                net: 5,
                mac: vec![0x0A]
            })
        );
        for bad in [
            vec![("instance", Value::UInt(4_194_303))],
            vec![("address", "plc.local".into())],
            vec![("network", Value::UInt(5))],
            vec![("address", "10.0.0.1".into()), ("network", Value::UInt(5))],
            vec![("mac", "0A".into())],
            vec![
                ("address", "10.0.0.1".into()),
                ("network", Value::UInt(5)),
                ("mac", "zz".into()),
            ],
            vec![("max_apdu", Value::UInt(20))],
            vec![("max_apdu", Value::UInt(2000))],
        ] {
            assert!(d(&bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn plan_shares_objects_and_reads() {
        let pv = ai(&[]);
        let flags = ai(&[("property", "status_flags".into())]);
        let other = point(&[
            ("object_type", "analog_value".into()),
            ("instance", Value::UInt(1)),
            ("check_status", Value::Bool(false)),
        ])
        .unwrap();
        let dev = Dev::from_value(&Value::Map(BTreeMap::from([(
            "instance".to_owned(),
            Value::UInt(1),
        )])))
        .unwrap();
        let plan = BacnetDriver::plan(
            &dev,
            &[
                ("pv".into(), pv),
                ("flags".into(), flags),
                ("av".into(), other),
            ],
        );
        // ai:1 present-value, ai:1 status-flags (shared by pv and flags),
        // av:1 present-value
        assert_eq!(plan.reads(), 3);
        assert_eq!(plan.slots[0].1, Some(plan.slots[1].0));
        assert_eq!(rpm_specs(&plan.items).len(), 2);
    }

    #[test]
    fn replies_classified() {
        use codec::service::{READ_PROPERTY, READ_PROPERTY_MULTIPLE};
        assert!(matches!(
            classify(READ_PROPERTY_MULTIPLE, Reply::Reject(9)),
            Err(Fail::NotSupported(_))
        ));
        assert!(matches!(
            classify(READ_PROPERTY_MULTIPLE, Reply::Error(5, 29)),
            Err(Fail::NotSupported(_))
        ));
        assert!(matches!(
            classify(READ_PROPERTY, Reply::Error(5, 29)),
            Err(Fail::Refused(_))
        ));
        assert!(matches!(
            classify(READ_PROPERTY, Reply::Abort(4)),
            Err(Fail::TooBig(_))
        ));
        assert_eq!(
            classify(READ_PROPERTY, Reply::Error(1, 31)),
            Err(Fail::Refused("object: unknown-object".into()))
        );
        assert_eq!(
            classify(READ_PROPERTY, Reply::Reject(4)),
            Err(Fail::Refused("reject: invalid-tag".into()))
        );
    }

    fn test_conn(port: u16, peer: SocketAddr) -> Conn {
        Conn {
            bind_host: "127.0.0.1".into(),
            bind_port: port,
            broadcast: peer.to_string(),
            bbmd: String::new(),
            bbmd_ttl_s: 300,
            apdu_timeout_ms: 100,
            apdu_retries: 0,
            max_apdu: 1476,
        }
    }

    /// The invoke id and service of a confirmed request in `frame`.
    fn request_of(frame: &[u8]) -> (u8, u8) {
        let Ok(Bvlc::Npdu { npdu, .. }) = codec::parse_bvlc(frame) else {
            panic!("not an NPDU")
        };
        let n = codec::parse_npdu(npdu).unwrap();
        match codec::parse_apdu(n.apdu).unwrap() {
            Apdu::ConfirmedRequest {
                invoke_id, service, ..
            } => (invoke_id, service),
            other => panic!("{other:?}"),
        }
    }

    fn reply_frame(apdu: &[u8]) -> Vec<u8> {
        let mut n = Vec::new();
        codec::npdu_header(&mut n, None, false);
        n.extend_from_slice(apdu);
        codec::bvlc_wrap(codec::bvlc::ORIGINAL_UNICAST, &n)
    }

    fn dev_read() -> Vec<u8> {
        codec::read_property(
            ObjectId::new(ObjectId::DEVICE, 1),
            PropRef {
                id: codec::prop::SYSTEM_STATUS,
                index: None,
            },
        )
    }

    /// A reopened port (same local port) does not start its invoke ids
    /// again: a late reply to the old socket's request is never taken for
    /// the new socket's request.
    #[tokio::test]
    async fn invoke_ids_go_on_after_a_reopen() {
        let raw = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let SocketAddr::V4(raw_addr) = raw.local_addr().unwrap() else {
            panic!()
        };
        let port = std::net::UdpSocket::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let conn = test_conn(port, raw_addr.into());
        let peer = Peer {
            addr: raw_addr,
            net: None,
        };
        let mut ids = Vec::new();
        let mut buf = vec![0u8; 2048];
        for _ in 0..2 {
            let mut t = Transport::open(&conn).await.unwrap();
            let r = t
                .confirmed(&peer, codec::service::READ_PROPERTY, &dev_read())
                .await;
            assert!(matches!(r, Err(DriverError::Device(_))), "{r:?}");
            let (n, _) = raw.recv_from(&mut buf).await.unwrap();
            ids.push(request_of(&buf[..n]).0);
            drop(t);
        }
        assert_ne!(ids[0], ids[1], "{ids:?}");
    }

    /// A reply with the request's invoke id but another service is not
    /// the reply (it is dropped and counted late).
    #[tokio::test]
    async fn a_reply_of_another_service_is_not_taken() {
        let raw = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let SocketAddr::V4(raw_addr) = raw.local_addr().unwrap() else {
            panic!()
        };
        let conn = test_conn(0, raw_addr.into());
        let peer = Peer {
            addr: raw_addr,
            net: None,
        };
        let mut t = Transport::open(&conn).await.unwrap();
        let answer = tokio::spawn(async move {
            let mut buf = vec![0u8; 2048];
            let (n, from) = raw.recv_from(&mut buf).await.unwrap();
            let (id, service) = request_of(&buf[..n]);
            assert_eq!(service, codec::service::READ_PROPERTY);
            // a SimpleACK of a WriteProperty with this id
            let f = reply_frame(&codec::simple_ack(id, codec::service::WRITE_PROPERTY));
            raw.send_to(&f, from).await.unwrap();
            // an Error of a WriteProperty with this id
            let f = reply_frame(&codec::error_pdu(id, codec::service::WRITE_PROPERTY, 2, 40));
            raw.send_to(&f, from).await.unwrap();
        });
        let r = t
            .confirmed(&peer, codec::service::READ_PROPERTY, &dev_read())
            .await;
        answer.await.unwrap();
        assert!(matches!(r, Err(DriverError::Device(_))), "{r:?}");
        let late = t
            .outcomes
            .iter()
            .filter(|o| matches!(o, Outcome::Count(LATE)))
            .count();
        assert_eq!(late, 2);
    }

    #[test]
    fn incoming_frames() {
        let from: SocketAddr = "10.0.0.9:47808".parse().unwrap();
        // a routed SimpleACK
        let mut n = Vec::new();
        codec::npdu_header_from(
            &mut n,
            &NetAddr {
                net: 5,
                mac: vec![7],
            },
        );
        n.extend(codec::simple_ack(3, 15));
        let f = codec::bvlc_wrap(codec::bvlc::ORIGINAL_UNICAST, &n);
        let Incoming::Reply {
            peer,
            invoke_id: 3,
            service: Some(15),
            reply: Reply::Simple,
        } = incoming(&f, from, None)
        else {
            panic!()
        };
        assert_eq!(
            peer.net,
            Some(NetAddr {
                net: 5,
                mac: vec![7]
            })
        );
        // a forwarded I-Am: the original source counts, but only from the
        // configured BBMD (security: anyone else could name any origin)
        let mut n = Vec::new();
        codec::npdu_header(&mut n, None, false);
        n.extend(codec::i_am(&IAm {
            device: ObjectId::new(8, 42),
            max_apdu: 1476,
            segmentation: 3,
            vendor_id: 7,
        }));
        let origin: SocketAddrV4 = "10.0.1.20:47808".parse().unwrap();
        let f = codec::bvlc_forwarded(origin, &n);
        let SocketAddr::V4(bbmd) = from else { panic!() };
        let Incoming::IAm(h) = incoming(&f, from, Some(bbmd)) else {
            panic!()
        };
        assert_eq!(h.peer.addr, origin);
        assert_eq!(h.iam.device.instance, 42);
        assert!(matches!(incoming(&f, from, None), Incoming::Other));
        let other_bbmd: SocketAddrV4 = "10.0.0.1:47808".parse().unwrap();
        assert!(matches!(
            incoming(&f, from, Some(other_bbmd)),
            Incoming::Other
        ));
        // junk
        assert!(matches!(incoming(&[1, 2, 3], from, None), Incoming::Other));
        assert!(matches!(
            incoming(&codec::bvlc_result(0x30), from, None),
            Incoming::BvlcResult { code: 0x30, .. }
        ));
    }
}
