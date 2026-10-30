//! BACnet/IP device simulator (feature `sim`) on its own UDP port.
//!
//! One device object and a few objects: analog-input 1 (the demo binary
//! changes it), analog-value 1 (commandable, writable with priorities),
//! binary-input 1, binary-value 1 (commandable), multi-state-value 1
//! (commandable), integer-value 1 and large-analog-value 1. It answers
//! Who-Is (I-Am unicast to the asker), ReadProperty, ReadPropertyMultiple
//! and WriteProperty, and can be a BBMD for one foreign device (I-Am back
//! as a Forwarded-NPDU) or sit behind a router (`routed`: requests must
//! name its network and MAC, replies carry them).
//!
//! Failure modes for tests: silence, dropped requests, slow replies (one or
//! all), a Reject, RPM not supported, an Error for a whole RPM that names
//! an unknown object (as some older devices do), and a small max APDU (a
//! reply that does not fit is aborted: segmentation-not-supported).

use crate::codec::{self, prop, Apdu, AppValue, Bvlc, IAm, NetAddr, ObjectId, PropRef};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::net::{SocketAddr, SocketAddrV4};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::net::UdpSocket;

/// One simulated object.
#[derive(Debug, Clone)]
pub struct Object {
    pub props: BTreeMap<u32, Vec<AppValue>>,
    /// Commandable: present-value follows this array, then
    /// `relinquish-default`.
    pub priority: Option<[Option<AppValue>; 16]>,
    /// Properties a client may write.
    pub writable: BTreeSet<u32>,
}

impl Object {
    fn new(name: &str, ty: u16, instance: u32) -> Self {
        let mut props = BTreeMap::new();
        props.insert(
            prop::OBJECT_IDENTIFIER,
            vec![AppValue::ObjectId(ObjectId::new(ty, instance))],
        );
        props.insert(prop::OBJECT_NAME, vec![AppValue::CharString(name.into())]);
        props.insert(prop::OBJECT_TYPE, vec![AppValue::Enumerated(ty.into())]);
        Self {
            props,
            priority: None,
            writable: BTreeSet::new(),
        }
    }

    fn io(mut self, pv: AppValue, units: Option<u32>) -> Self {
        self.props.insert(prop::PRESENT_VALUE, vec![pv]);
        self.props.insert(
            prop::STATUS_FLAGS,
            vec![AppValue::BitString(vec![false; 4])],
        );
        self.props
            .insert(prop::RELIABILITY, vec![AppValue::Enumerated(0)]);
        self.props
            .insert(prop::EVENT_STATE, vec![AppValue::Enumerated(0)]);
        self.props
            .insert(prop::OUT_OF_SERVICE, vec![AppValue::Boolean(false)]);
        if let Some(u) = units {
            self.props
                .insert(prop::UNITS, vec![AppValue::Enumerated(u)]);
        }
        self
    }

    fn commandable(mut self, default: AppValue) -> Self {
        self.props.insert(prop::RELINQUISH_DEFAULT, vec![default]);
        self.priority = Some(Default::default());
        self.writable.insert(prop::PRESENT_VALUE);
        self
    }

    /// The present value: the highest priority set, else the default.
    pub fn present_value(&self) -> Option<AppValue> {
        if let Some(arr) = &self.priority {
            if let Some(v) = arr.iter().flatten().next() {
                return Some(v.clone());
            }
            return self
                .props
                .get(&prop::RELINQUISH_DEFAULT)
                .and_then(|v| v.first().cloned());
        }
        self.props
            .get(&prop::PRESENT_VALUE)
            .and_then(|v| v.first().cloned())
    }
}

/// The simulated device and its faults.
#[derive(Debug)]
pub struct Sim {
    pub instance: u32,
    pub objects: BTreeMap<ObjectId, Object>,
    /// Max APDU in I-Am; a longer reply is aborted.
    pub max_apdu: u16,
    pub vendor_id: u32,
    /// Answer nothing at all.
    pub silent: bool,
    /// Leave the next `n` confirmed requests unanswered.
    pub drop_next: u32,
    /// Leave every read that names this object unanswered.
    pub drop_object: Option<ObjectId>,
    /// Delay before every reply.
    pub delay: Duration,
    /// Delay the next reply (once).
    pub delay_next: Option<Duration>,
    /// Reject the next confirmed request with this reason (once).
    pub reject_next: Option<u8>,
    /// Reject every RPM: unrecognized-service.
    pub rpm_unsupported: bool,
    /// An RPM naming an unknown object gets one Error unknown-object.
    pub rpm_error_whole: bool,
    /// Behind a router on this network and MAC.
    pub routed: Option<NetAddr>,
    /// Refuse foreign-device registrations.
    pub fd_nak: bool,
    /// Also answer Who-Is with a Forwarded-NPDU I-Am claiming this origin
    /// (an impersonator, or a second path to the device).
    pub spoof_i_am: Option<SocketAddrV4>,
    /// The device object's `object-identifier` names another instance.
    pub bad_identity: bool,
    /// The registered foreign device.
    pub foreign: Option<SocketAddrV4>,
    /// Requests served, by confirmed service.
    pub by_service: BTreeMap<u8, u64>,
    pub who_is: u64,
    pub registrations: u64,
    /// Properties per RPM received, last first-in order (bounded).
    pub rpm_sizes: VecDeque<usize>,
    /// WriteProperty requests: object, property, value, priority.
    pub writes: Vec<(ObjectId, u32, AppValue, Option<u8>)>,
    /// Requests left unanswered (dropped or silent).
    pub dropped: u64,
}

/// Objects of the default device.
pub mod objects {
    use crate::codec::ObjectId;
    pub const AI1: ObjectId = ObjectId { ty: 0, instance: 1 };
    pub const AV1: ObjectId = ObjectId { ty: 2, instance: 1 };
    pub const BI1: ObjectId = ObjectId { ty: 3, instance: 1 };
    pub const BV1: ObjectId = ObjectId { ty: 5, instance: 1 };
    pub const MSV1: ObjectId = ObjectId {
        ty: 19,
        instance: 1,
    };
    pub const IV1: ObjectId = ObjectId {
        ty: 45,
        instance: 1,
    };
    pub const LAV1: ObjectId = ObjectId {
        ty: 46,
        instance: 1,
    };
}

const LOG_MAX: usize = 1000;

impl Sim {
    pub fn new(instance: u32) -> Self {
        use objects::*;
        let mut objects = BTreeMap::new();
        let mut dev = Object::new("WYRM BACnet Simulator", ObjectId::DEVICE, instance);
        dev.props
            .insert(prop::SYSTEM_STATUS, vec![AppValue::Enumerated(0)]);
        objects.insert(ObjectId::new(ObjectId::DEVICE, instance), dev);
        objects.insert(
            AI1,
            Object::new("Zone Temp", AI1.ty, 1).io(AppValue::Real(21.5), Some(62)),
        );
        objects.insert(
            AV1,
            Object::new("Setpoint", AV1.ty, 1)
                .io(AppValue::Real(20.0), Some(62))
                .commandable(AppValue::Real(20.0)),
        );
        objects.insert(
            BI1,
            Object::new("Fan Status", BI1.ty, 1).io(AppValue::Enumerated(1), None),
        );
        objects.insert(
            BV1,
            Object::new("Fan Command", BV1.ty, 1)
                .io(AppValue::Enumerated(0), None)
                .commandable(AppValue::Enumerated(0)),
        );
        let mut msv = Object::new("Mode", MSV1.ty, 1)
            .io(AppValue::Unsigned(1), None)
            .commandable(AppValue::Unsigned(1));
        msv.props
            .insert(prop::NUMBER_OF_STATES, vec![AppValue::Unsigned(3)]);
        objects.insert(MSV1, msv);
        let mut iv = Object::new("Counter", IV1.ty, 1).io(AppValue::Signed(-5), None);
        iv.writable.insert(prop::PRESENT_VALUE);
        objects.insert(IV1, iv);
        objects.insert(
            LAV1,
            Object::new("Energy", LAV1.ty, 1).io(AppValue::Double(123_456_789.25), Some(19)),
        );
        Self {
            instance,
            objects,
            max_apdu: codec::MAX_APDU,
            vendor_id: 999,
            silent: false,
            drop_next: 0,
            drop_object: None,
            delay: Duration::ZERO,
            delay_next: None,
            reject_next: None,
            rpm_unsupported: false,
            rpm_error_whole: false,
            routed: None,
            fd_nak: false,
            spoof_i_am: None,
            bad_identity: false,
            foreign: None,
            by_service: BTreeMap::new(),
            who_is: 0,
            registrations: 0,
            rpm_sizes: VecDeque::new(),
            writes: Vec::new(),
            dropped: 0,
        }
    }

    /// Requests of a confirmed service served so far.
    pub fn count(&self, service: u8) -> u64 {
        self.by_service.get(&service).copied().unwrap_or(0)
    }

    pub fn set_pv(&mut self, obj: ObjectId, v: AppValue) {
        if let Some(o) = self.objects.get_mut(&obj) {
            o.props.insert(prop::PRESENT_VALUE, vec![v]);
        }
    }

    pub fn pv(&self, obj: ObjectId) -> Option<AppValue> {
        self.objects.get(&obj).and_then(Object::present_value)
    }

    /// `status-flags`: in-alarm, fault, overridden, out-of-service.
    pub fn set_flags(&mut self, obj: ObjectId, flags: [bool; 4]) {
        if let Some(o) = self.objects.get_mut(&obj) {
            o.props.insert(
                prop::STATUS_FLAGS,
                vec![AppValue::BitString(flags.to_vec())],
            );
        }
    }

    /// The priority array of a commandable object.
    pub fn priorities(&self, obj: ObjectId) -> Option<[Option<AppValue>; 16]> {
        self.objects.get(&obj).and_then(|o| o.priority.clone())
    }

    /// `n` more analog inputs, instances 100…, named `AI <i>`.
    pub fn add_analog_inputs(&mut self, n: u32) {
        for i in 100..100 + n {
            self.objects.insert(
                ObjectId::new(0, i),
                Object::new(&format!("AI {i}"), 0, i).io(AppValue::Real(i as f32), Some(98)),
            );
        }
    }

    /// A read naming [`Sim::drop_object`].
    fn names_dropped(&self, service: u8, data: &[u8]) -> bool {
        let Some(drop) = self.drop_object else {
            return false;
        };
        match service {
            codec::service::READ_PROPERTY => {
                codec::parse_read_property(data).is_ok_and(|(o, _)| o == drop)
            }
            codec::service::READ_PROPERTY_MULTIPLE => codec::parse_read_property_multiple(data)
                .is_ok_and(|specs| specs.iter().any(|(o, _)| *o == drop)),
            _ => false,
        }
    }

    fn device_id(&self) -> ObjectId {
        ObjectId::new(ObjectId::DEVICE, self.instance)
    }

    fn object_list(&self) -> Vec<AppValue> {
        self.objects
            .keys()
            .map(|o| AppValue::ObjectId(*o))
            .collect()
    }

    /// The value(s) of one property, or an error class and code.
    fn read(&self, obj: ObjectId, p: PropRef) -> codec::PropResult {
        use codec::error::*;
        let o = self
            .objects
            .get(&obj)
            .ok_or((CLASS_OBJECT, CODE_UNKNOWN_OBJECT))?;
        let all: Vec<AppValue> = match p.id {
            prop::OBJECT_IDENTIFIER if obj == self.device_id() && self.bad_identity => {
                vec![AppValue::ObjectId(ObjectId::new(
                    ObjectId::DEVICE,
                    self.instance + 1,
                ))]
            }
            prop::OBJECT_LIST if obj == self.device_id() => self.object_list(),
            prop::MAX_APDU_LENGTH_ACCEPTED if obj == self.device_id() => {
                vec![AppValue::Unsigned(self.max_apdu.into())]
            }
            prop::VENDOR_IDENTIFIER if obj == self.device_id() => {
                vec![AppValue::Unsigned(self.vendor_id.into())]
            }
            prop::SEGMENTATION_SUPPORTED if obj == self.device_id() => {
                vec![AppValue::Enumerated(3)]
            }
            prop::PRESENT_VALUE if o.priority.is_some() => o.present_value().into_iter().collect(),
            prop::PRIORITY_ARRAY if o.priority.is_some() => o
                .priority
                .iter()
                .flatten()
                .map(|v| v.clone().unwrap_or(AppValue::Null))
                .collect(),
            id => o
                .props
                .get(&id)
                .cloned()
                .ok_or((CLASS_PROPERTY, CODE_UNKNOWN_PROPERTY))?,
        };
        let is_array = matches!(p.id, prop::OBJECT_LIST | prop::PRIORITY_ARRAY);
        match p.index {
            None => Ok(all),
            Some(_) if !is_array => Err((CLASS_PROPERTY, 50)),
            Some(0) => Ok(vec![AppValue::Unsigned(all.len() as u64)]),
            Some(i) => all
                .get(i as usize - 1)
                .cloned()
                .map(|v| vec![v])
                .ok_or((CLASS_PROPERTY, CODE_INVALID_ARRAY_INDEX)),
        }
    }

    fn write(
        &mut self,
        obj: ObjectId,
        p: PropRef,
        v: AppValue,
        priority: Option<u8>,
    ) -> Result<(), (u32, u32)> {
        use codec::error::*;
        let o = self
            .objects
            .get_mut(&obj)
            .ok_or((CLASS_OBJECT, CODE_UNKNOWN_OBJECT))?;
        if !o.writable.contains(&p.id) || p.index.is_some() {
            return Err((CLASS_PROPERTY, CODE_WRITE_ACCESS_DENIED));
        }
        let same_tag = |cur: Option<&AppValue>| {
            cur.is_none_or(|c| std::mem::discriminant(c) == std::mem::discriminant(&v))
        };
        match &mut o.priority {
            Some(arr) if p.id == prop::PRESENT_VALUE => {
                let prio = priority.unwrap_or(16);
                if !(1..=16).contains(&prio) {
                    return Err((CLASS_SERVICES, CODE_VALUE_OUT_OF_RANGE));
                }
                let default = o
                    .props
                    .get(&prop::RELINQUISH_DEFAULT)
                    .and_then(|d| d.first());
                if v != AppValue::Null && !same_tag(default) {
                    return Err((CLASS_PROPERTY, CODE_INVALID_DATA_TYPE));
                }
                arr[usize::from(prio) - 1] = (v != AppValue::Null).then_some(v);
            }
            _ => {
                if !same_tag(o.props.get(&p.id).and_then(|c| c.first())) {
                    return Err((CLASS_PROPERTY, CODE_INVALID_DATA_TYPE));
                }
                o.props.insert(p.id, vec![v]);
            }
        }
        Ok(())
    }

    /// The reply APDU to a confirmed request (`None`: none).
    fn confirmed(&mut self, invoke_id: u8, service: u8, data: &[u8]) -> Vec<u8> {
        use codec::service::*;
        *self.by_service.entry(service).or_default() += 1;
        if let Some(reason) = self.reject_next.take() {
            return codec::reject_pdu(invoke_id, reason);
        }
        let reply = match service {
            READ_PROPERTY => match codec::parse_read_property(data) {
                Err(_) => codec::reject_pdu(invoke_id, 4),
                Ok((obj, p)) => match self.read(obj, p) {
                    Ok(values) => codec::complex_ack(
                        invoke_id,
                        service,
                        &codec::read_property_ack(obj, p, &values),
                    ),
                    Err((c, e)) => codec::error_pdu(invoke_id, service, c, e),
                },
            },
            READ_PROPERTY_MULTIPLE if self.rpm_unsupported => {
                codec::reject_pdu(invoke_id, codec::reject::UNRECOGNIZED_SERVICE)
            }
            READ_PROPERTY_MULTIPLE => match codec::parse_read_property_multiple(data) {
                Err(_) => codec::reject_pdu(invoke_id, 4),
                Ok(specs) => {
                    let n = specs.iter().map(|(_, p)| p.len()).sum();
                    if self.rpm_sizes.len() >= LOG_MAX {
                        self.rpm_sizes.pop_front();
                    }
                    self.rpm_sizes.push_back(n);
                    if self.rpm_error_whole
                        && specs.iter().any(|(o, _)| !self.objects.contains_key(o))
                    {
                        codec::error_pdu(
                            invoke_id,
                            service,
                            codec::error::CLASS_OBJECT,
                            codec::error::CODE_UNKNOWN_OBJECT,
                        )
                    } else {
                        let results: Vec<_> = specs
                            .into_iter()
                            .map(|(o, props)| {
                                let r = props.into_iter().map(|p| (p, self.read(o, p))).collect();
                                (o, r)
                            })
                            .collect();
                        codec::complex_ack(
                            invoke_id,
                            service,
                            &codec::read_property_multiple_ack(&results),
                        )
                    }
                }
            },
            WRITE_PROPERTY => match codec::parse_write_property(data) {
                Err(_) => codec::reject_pdu(invoke_id, 4),
                Ok((obj, p, v, prio)) => {
                    self.writes.push((obj, p.id, v.clone(), prio));
                    match self.write(obj, p, v, prio) {
                        Ok(()) => codec::simple_ack(invoke_id, service),
                        Err((c, e)) => codec::error_pdu(invoke_id, service, c, e),
                    }
                }
            },
            _ => codec::reject_pdu(invoke_id, codec::reject::UNRECOGNIZED_SERVICE),
        };
        if reply.len() > usize::from(self.max_apdu) {
            return codec::abort_pdu(invoke_id, codec::abort::SEGMENTATION_NOT_SUPPORTED);
        }
        reply
    }

    fn npdu(&self, apdu: &[u8]) -> Vec<u8> {
        let mut n = Vec::new();
        match &self.routed {
            Some(r) => codec::npdu_header_from(&mut n, r),
            None => codec::npdu_header(&mut n, None, false),
        }
        n.extend_from_slice(apdu);
        n
    }

    /// Frames to send back for one received frame.
    fn handle(
        &mut self,
        frame: &[u8],
        from: SocketAddrV4,
        me: SocketAddrV4,
    ) -> Vec<(Vec<u8>, SocketAddrV4)> {
        if self.silent {
            self.dropped += 1;
            return Vec::new();
        }
        let (function, npdu) = match codec::parse_bvlc(frame) {
            Ok(Bvlc::RegisterForeignDevice(_)) => {
                self.registrations += 1;
                let code = if self.fd_nak {
                    codec::bvlc::REGISTER_NAK
                } else {
                    self.foreign = Some(from);
                    0
                };
                return vec![(codec::bvlc_result(code), from)];
            }
            Ok(Bvlc::Npdu { function, npdu, .. }) => (function, npdu),
            _ => return Vec::new(),
        };
        let Ok(n) = codec::parse_npdu(npdu) else {
            return Vec::new();
        };
        let global = n.dest.as_ref().is_some_and(|d| d.net == codec::GLOBAL_NET);
        let for_me = match (&n.dest, &self.routed) {
            (None, None) => true,
            (Some(_), _) if global => true,
            (Some(d), Some(r)) => d == r,
            _ => false,
        };
        if !for_me || n.network_message {
            return Vec::new();
        }
        match codec::parse_apdu(n.apdu) {
            Ok(Apdu::Unconfirmed {
                service: codec::service::WHO_IS,
                data,
            }) => {
                self.who_is += 1;
                let Ok(range) = codec::parse_who_is(data) else {
                    return Vec::new();
                };
                if range.is_some_and(|(lo, hi)| self.instance < lo || self.instance > hi) {
                    return Vec::new();
                }
                let iam = self.npdu(&codec::i_am(&IAm {
                    device: self.device_id(),
                    max_apdu: self.max_apdu,
                    segmentation: 3,
                    vendor_id: self.vendor_id,
                }));
                let reply = if function == codec::bvlc::DISTRIBUTE_BROADCAST {
                    codec::bvlc_forwarded(me, &iam)
                } else {
                    codec::bvlc_wrap(codec::bvlc::ORIGINAL_UNICAST, &iam)
                };
                let mut out = vec![(reply, from)];
                if let Some(origin) = self.spoof_i_am {
                    out.push((codec::bvlc_forwarded(origin, &iam), from));
                }
                out
            }
            Ok(Apdu::ConfirmedRequest {
                invoke_id,
                service,
                segmented: false,
                data,
                ..
            }) if !global => {
                if self.drop_next > 0 || self.names_dropped(service, data) {
                    self.drop_next = self.drop_next.saturating_sub(1);
                    self.dropped += 1;
                    return Vec::new();
                }
                let apdu = self.confirmed(invoke_id, service, data);
                let npdu = self.npdu(&apdu);
                vec![(codec::bvlc_wrap(codec::bvlc::ORIGINAL_UNICAST, &npdu), from)]
            }
            _ => Vec::new(),
        }
    }
}

pub type Device = Arc<Mutex<Sim>>;

/// Run a simulated device with `instance` on `addr` (`127.0.0.1:0` for a
/// free port).
pub async fn spawn(
    addr: &str,
    instance: u32,
) -> std::io::Result<(SocketAddr, Device, tokio::task::JoinHandle<()>)> {
    let sock = UdpSocket::bind(addr).await?;
    let local = sock.local_addr()?;
    let SocketAddr::V4(me) = local else {
        return Err(std::io::Error::other("the simulator is IPv4 only"));
    };
    let dev: Device = Arc::new(Mutex::new(Sim::new(instance)));
    let d = dev.clone();
    let task = tokio::spawn(async move {
        let mut buf = vec![0u8; 2048];
        loop {
            let (n, from) = match sock.recv_from(&mut buf).await {
                Ok(x) => x,
                Err(_) => continue,
            };
            let SocketAddr::V4(from) = from else { continue };
            let (replies, delay) = {
                let Ok(mut s) = d.lock() else { return };
                let replies = s.handle(&buf[..n], from, me);
                let delay = if replies.is_empty() {
                    Duration::ZERO
                } else {
                    s.delay + s.delay_next.take().unwrap_or_default()
                };
                (replies, delay)
            };
            if !delay.is_zero() {
                tokio::time::sleep(delay).await;
            }
            for (frame, to) in replies {
                let _ = sock.send_to(&frame, to).await;
            }
        }
    });
    Ok((local, dev, task))
}
