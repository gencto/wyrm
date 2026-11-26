//! KNXnet/IP frames (core, tunnelling and routing services) as they travel
//! in one UDP datagram:
//!
//! ```text
//! 06 10 | service type (2) | total length (2) | body
//! ```
//!
//! The service type's high octet is the service family, the low octet the
//! service inside it; the low octets do not repeat across the families
//! this link speaks, so [`Service`] is one table keyed by the low octet.

use crate::addr::IndividualAddr;
use std::net::{Ipv4Addr, SocketAddrV4};

/// The port KNXnet/IP is registered on.
pub const PORT: u16 = 3671;
/// The multicast group of search requests and of routing.
pub const MULTICAST: Ipv4Addr = Ipv4Addr::new(224, 0, 23, 12);

const HEADER_LEN: u8 = 0x06;
const VERSION: u8 = 0x10;
/// Host protocol code of an HPAI: IPv4 UDP.
const IPV4_UDP: u8 = 0x01;
/// Connection type of a CRI: a tunnel.
const TUNNEL_CONNECTION: u8 = 0x04;
/// Tunnelling layer of a CRI: the data link layer.
const TUNNEL_LINKLAYER: u8 = 0x02;
/// Description type: device information.
const DIB_DEVICE_INFO: u8 = 0x01;
const DIB_DEVICE_INFO_LEN: usize = 54;

wyrm_core::wire_enum! {
    /// Service type identifier, by its low octet.
    pub enum Service {
        SearchRequest = 0x01 => "SEARCH_REQUEST",
        SearchResponse = 0x02 => "SEARCH_RESPONSE",
        ConnectRequest = 0x05 => "CONNECT_REQUEST",
        ConnectResponse = 0x06 => "CONNECT_RESPONSE",
        ConnectionStateRequest = 0x07 => "CONNECTIONSTATE_REQUEST",
        ConnectionStateResponse = 0x08 => "CONNECTIONSTATE_RESPONSE",
        DisconnectRequest = 0x09 => "DISCONNECT_REQUEST",
        DisconnectResponse = 0x0A => "DISCONNECT_RESPONSE",
        TunnellingRequest = 0x20 => "TUNNELLING_REQUEST",
        TunnellingAck = 0x21 => "TUNNELLING_ACK",
        RoutingIndication = 0x30 => "ROUTING_INDICATION",
        RoutingLostMessage = 0x31 => "ROUTING_LOST_MESSAGE",
        RoutingBusy = 0x32 => "ROUTING_BUSY",
    }
}

impl Service {
    /// The service family (the type's high octet): core, tunnelling,
    /// routing.
    pub const fn family(self) -> u8 {
        match self {
            Service::TunnellingRequest | Service::TunnellingAck => 0x04,
            Service::RoutingIndication | Service::RoutingLostMessage | Service::RoutingBusy => 0x05,
            _ => 0x02,
        }
    }
}

wyrm_core::wire_enum! {
    /// Status of a connect, connection state or tunnelling answer.
    pub enum ErrorCode {
        NoError = 0x00 => "no error",
        HostProtocolType = 0x01 => "host protocol not supported",
        VersionNotSupported = 0x02 => "protocol version not supported",
        SequenceNumber = 0x04 => "sequence number out of order",
        ConnectionId = 0x21 => "no connection with this channel",
        ConnectionType = 0x22 => "connection type not supported",
        ConnectionOption = 0x23 => "connection option not supported",
        NoMoreConnections = 0x24 => "all tunnels of the interface are in use",
        DataConnection = 0x26 => "data connection error",
        KnxConnection = 0x27 => "the interface lost the bus",
        TunnellingLayer = 0x29 => "tunnelling layer not supported",
    }
}

/// A status octet for people: its text, or the number of a code this link
/// does not know.
pub fn status_text(code: u8) -> String {
    match ErrorCode::try_from(code) {
        Ok(e) => e.name().to_owned(),
        Err(c) => format!("status 0x{}", wyrm_core::hex::encode_upper([c])),
    }
}

wyrm_core::wire_enum! {
    /// KNX medium of an interface (device information).
    pub enum Medium {
        Tp1 = 0x02 => "TP1",
        Pl110 = 0x04 => "PL110",
        Rf = 0x10 => "RF",
        Ip = 0x20 => "KNX IP",
    }
}

/// Why a datagram is not a KNXnet/IP frame this link takes.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ProtoError {
    #[error("not a KNXnet/IP 1.0 header")]
    Header,
    #[error("the header says {said} octets, the datagram has {got}")]
    Length { said: usize, got: usize },
    #[error("service type 0x{0:04X} is not handled")]
    Service(u16),
    #[error("{0} body cut short")]
    Short(&'static str),
    #[error("the frame is longer than 65535 octets")]
    TooLong,
}

/// The endpoint an answer goes to. `0.0.0.0:0` asks the receiver to use
/// the address the datagram came from (NAT mode).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Hpai(pub SocketAddrV4);

impl Hpai {
    pub const NAT: Hpai = Hpai(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 0));

    fn write(self, out: &mut Vec<u8>) {
        out.extend([0x08, IPV4_UDP]);
        out.extend(self.0.ip().octets());
        out.extend(self.0.port().to_be_bytes());
    }

    fn read(b: &[u8]) -> Option<(Self, &[u8])> {
        let [0x08, IPV4_UDP, a, b1, c, d, p0, p1, rest @ ..] = b else {
            return None;
        };
        let addr = SocketAddrV4::new(
            Ipv4Addr::new(*a, *b1, *c, *d),
            u16::from_be_bytes([*p0, *p1]),
        );
        Some((Hpai(addr), rest))
    }

    /// Where to answer: this endpoint, or `from` when it is unset.
    pub fn or(self, from: SocketAddrV4) -> SocketAddrV4 {
        if self.0.ip().is_unspecified() || self.0.port() == 0 {
            from
        } else {
            self.0
        }
    }
}

/// What a search response says about an interface.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceInfo {
    pub medium: u8,
    pub address: IndividualAddr,
    pub serial: [u8; 6],
    pub mac: [u8; 6],
    pub name: String,
}

impl DeviceInfo {
    fn write(&self, out: &mut Vec<u8>) {
        out.extend([0x36, DIB_DEVICE_INFO, self.medium, 0]);
        out.extend(self.address.0.to_be_bytes());
        out.extend([0, 0]);
        out.extend(self.serial);
        out.extend(MULTICAST.octets());
        out.extend(self.mac);
        let mut name = [0u8; 30];
        // ISO 8859-1; a character outside it is shown as `?`
        for (slot, ch) in name.iter_mut().zip(self.name.chars().take(29)) {
            *slot = u8::try_from(u32::from(ch)).unwrap_or(b'?');
        }
        out.extend(name);
    }

    fn read(b: &[u8]) -> Option<Self> {
        let dib = b.get(..DIB_DEVICE_INFO_LEN)?;
        let [0x36, DIB_DEVICE_INFO, medium, _status, a0, a1, _p0, _p1, rest @ ..] = dib else {
            return None;
        };
        let serial: [u8; 6] = rest.get(..6)?.try_into().ok()?;
        let mac: [u8; 6] = rest.get(10..16)?.try_into().ok()?;
        let name = rest
            .get(16..46)?
            .iter()
            .take_while(|c| **c != 0)
            .map(|c| char::from(*c))
            .collect::<String>();
        Some(DeviceInfo {
            medium: *medium,
            address: IndividualAddr(u16::from_be_bytes([*a0, *a1])),
            serial,
            mac,
            name: name.trim().to_owned(),
        })
    }
}

/// One KNXnet/IP frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Frame {
    SearchRequest {
        discovery: Hpai,
    },
    SearchResponse {
        control: Hpai,
        device: DeviceInfo,
    },
    ConnectRequest {
        control: Hpai,
        data: Hpai,
    },
    ConnectResponse {
        channel: u8,
        status: u8,
        /// Our individual address on the bus, when the connection is made.
        address: Option<IndividualAddr>,
        data: Option<Hpai>,
    },
    ConnectionStateRequest {
        channel: u8,
        control: Hpai,
    },
    ConnectionStateResponse {
        channel: u8,
        status: u8,
    },
    DisconnectRequest {
        channel: u8,
        control: Hpai,
    },
    DisconnectResponse {
        channel: u8,
        status: u8,
    },
    TunnellingRequest {
        channel: u8,
        seq: u8,
        cemi: Vec<u8>,
    },
    TunnellingAck {
        channel: u8,
        seq: u8,
        status: u8,
    },
    RoutingIndication {
        cemi: Vec<u8>,
    },
    RoutingLostMessage {
        lost: u16,
    },
    RoutingBusy {
        wait_ms: u16,
    },
}

impl Frame {
    pub fn service(&self) -> Service {
        match self {
            Frame::SearchRequest { .. } => Service::SearchRequest,
            Frame::SearchResponse { .. } => Service::SearchResponse,
            Frame::ConnectRequest { .. } => Service::ConnectRequest,
            Frame::ConnectResponse { .. } => Service::ConnectResponse,
            Frame::ConnectionStateRequest { .. } => Service::ConnectionStateRequest,
            Frame::ConnectionStateResponse { .. } => Service::ConnectionStateResponse,
            Frame::DisconnectRequest { .. } => Service::DisconnectRequest,
            Frame::DisconnectResponse { .. } => Service::DisconnectResponse,
            Frame::TunnellingRequest { .. } => Service::TunnellingRequest,
            Frame::TunnellingAck { .. } => Service::TunnellingAck,
            Frame::RoutingIndication { .. } => Service::RoutingIndication,
            Frame::RoutingLostMessage { .. } => Service::RoutingLostMessage,
            Frame::RoutingBusy { .. } => Service::RoutingBusy,
        }
    }

    pub fn encode(&self) -> Result<Vec<u8>, ProtoError> {
        let service = self.service();
        let mut out = vec![HEADER_LEN, VERSION, service.family(), service.code(), 0, 0];
        match self {
            Frame::SearchRequest { discovery } => discovery.write(&mut out),
            Frame::SearchResponse { control, device } => {
                control.write(&mut out);
                device.write(&mut out);
                // supported service families: core 1, tunnelling 1, routing 1
                out.extend([0x08, 0x02, 0x02, 0x01, 0x04, 0x01, 0x05, 0x01]);
            }
            Frame::ConnectRequest { control, data } => {
                control.write(&mut out);
                data.write(&mut out);
                out.extend([0x04, TUNNEL_CONNECTION, TUNNEL_LINKLAYER, 0x00]);
            }
            Frame::ConnectResponse {
                channel,
                status,
                address,
                data,
            } => {
                out.extend([*channel, *status]);
                if let (Some(address), Some(data)) = (address, data) {
                    data.write(&mut out);
                    out.extend([0x04, TUNNEL_CONNECTION]);
                    out.extend(address.0.to_be_bytes());
                }
            }
            Frame::ConnectionStateRequest { channel, control }
            | Frame::DisconnectRequest { channel, control } => {
                out.extend([*channel, 0]);
                control.write(&mut out);
            }
            Frame::ConnectionStateResponse { channel, status }
            | Frame::DisconnectResponse { channel, status } => out.extend([*channel, *status]),
            Frame::TunnellingRequest { channel, seq, cemi } => {
                out.extend([0x04, *channel, *seq, 0]);
                out.extend(cemi);
            }
            Frame::TunnellingAck {
                channel,
                seq,
                status,
            } => out.extend([0x04, *channel, *seq, *status]),
            Frame::RoutingIndication { cemi } => out.extend(cemi),
            Frame::RoutingLostMessage { lost } => {
                out.extend([0x04, 0]);
                out.extend(lost.to_be_bytes());
            }
            Frame::RoutingBusy { wait_ms } => {
                out.extend([0x06, 0]);
                out.extend(wait_ms.to_be_bytes());
                out.extend([0, 0]);
            }
        }
        let total = u16::try_from(out.len()).map_err(|_e| ProtoError::TooLong)?;
        if let Some(len) = out.get_mut(4..6) {
            len.copy_from_slice(&total.to_be_bytes());
        }
        Ok(out)
    }

    pub fn decode(b: &[u8]) -> Result<Self, ProtoError> {
        let [HEADER_LEN, VERSION, family, low, l0, l1, body @ ..] = b else {
            return Err(ProtoError::Header);
        };
        let said = usize::from(u16::from_be_bytes([*l0, *l1]));
        if said != b.len() {
            return Err(ProtoError::Length { said, got: b.len() });
        }
        let unknown = ProtoError::Service(u16::from_be_bytes([*family, *low]));
        let Ok(service) = Service::try_from(*low) else {
            return Err(unknown);
        };
        if service.family() != *family {
            return Err(unknown);
        }
        let short = ProtoError::Short(service.name());
        body_of(service, body).ok_or(short)
    }
}

/// The body of `service`; `None` when it is cut short or malformed.
fn body_of(service: Service, body: &[u8]) -> Option<Frame> {
    Some(match service {
        Service::SearchRequest => Frame::SearchRequest {
            discovery: Hpai::read(body)?.0,
        },
        Service::SearchResponse => {
            let (control, rest) = Hpai::read(body)?;
            Frame::SearchResponse {
                control,
                device: DeviceInfo::read(rest)?,
            }
        }
        Service::ConnectRequest => {
            let (control, rest) = Hpai::read(body)?;
            let (data, cri) = Hpai::read(rest)?;
            let [_len, TUNNEL_CONNECTION, ..] = cri else {
                return None;
            };
            Frame::ConnectRequest { control, data }
        }
        Service::ConnectResponse => {
            let [channel, status, rest @ ..] = body else {
                return None;
            };
            let made = Hpai::read(rest).and_then(|(data, crd)| match crd {
                [0x04, TUNNEL_CONNECTION, a0, a1, ..] => {
                    Some((data, IndividualAddr(u16::from_be_bytes([*a0, *a1]))))
                }
                _ => None,
            });
            Frame::ConnectResponse {
                channel: *channel,
                status: *status,
                address: made.map(|(_, a)| a),
                data: made.map(|(d, _)| d),
            }
        }
        Service::ConnectionStateRequest | Service::DisconnectRequest => {
            let [channel, _reserved, rest @ ..] = body else {
                return None;
            };
            let (control, _) = Hpai::read(rest)?;
            if service == Service::DisconnectRequest {
                Frame::DisconnectRequest {
                    channel: *channel,
                    control,
                }
            } else {
                Frame::ConnectionStateRequest {
                    channel: *channel,
                    control,
                }
            }
        }
        Service::ConnectionStateResponse => {
            let [channel, status, ..] = body else {
                return None;
            };
            Frame::ConnectionStateResponse {
                channel: *channel,
                status: *status,
            }
        }
        Service::DisconnectResponse => {
            let [channel, status, ..] = body else {
                return None;
            };
            Frame::DisconnectResponse {
                channel: *channel,
                status: *status,
            }
        }
        Service::TunnellingRequest => {
            let [0x04, channel, seq, _reserved, cemi @ ..] = body else {
                return None;
            };
            Frame::TunnellingRequest {
                channel: *channel,
                seq: *seq,
                cemi: cemi.to_vec(),
            }
        }
        Service::TunnellingAck => {
            let [0x04, channel, seq, status, ..] = body else {
                return None;
            };
            Frame::TunnellingAck {
                channel: *channel,
                seq: *seq,
                status: *status,
            }
        }
        Service::RoutingIndication => Frame::RoutingIndication {
            cemi: body.to_vec(),
        },
        Service::RoutingLostMessage => {
            let [_len, _state, l0, l1, ..] = body else {
                return None;
            };
            Frame::RoutingLostMessage {
                lost: u16::from_be_bytes([*l0, *l1]),
            }
        }
        Service::RoutingBusy => {
            let [_len, _state, w0, w1, ..] = body else {
                return None;
            };
            Frame::RoutingBusy {
                wait_ms: u16::from_be_bytes([*w0, *w1]),
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hpai() -> Hpai {
        Hpai(SocketAddrV4::new(Ipv4Addr::new(192, 168, 1, 20), 50100))
    }

    fn both_ways(f: Frame) -> Vec<u8> {
        let b = f.encode().unwrap();
        assert_eq!(Frame::decode(&b).unwrap(), f, "{b:02X?}");
        b
    }

    #[test]
    fn connect_request_as_the_standard_writes_it() {
        let b = both_ways(Frame::ConnectRequest {
            control: hpai(),
            data: hpai(),
        });
        assert_eq!(
            b,
            [
                0x06, 0x10, 0x02, 0x05, 0x00, 0x1A, // header, 26 octets
                0x08, 0x01, 192, 168, 1, 20, 0xC3, 0xB4, // control endpoint
                0x08, 0x01, 192, 168, 1, 20, 0xC3, 0xB4, // data endpoint
                0x04, 0x04, 0x02, 0x00, // CRI: tunnel, link layer
            ]
        );
    }

    #[test]
    fn connect_responses() {
        let b = both_ways(Frame::ConnectResponse {
            channel: 21,
            status: 0,
            address: Some(IndividualAddr(0x11FA)),
            data: Some(hpai()),
        });
        assert_eq!(b[..8], [0x06, 0x10, 0x02, 0x06, 0x00, 0x14, 21, 0]);
        assert_eq!(b[16..], [0x04, 0x04, 0x11, 0xFA]);
        // a refusal has no endpoint and no CRD
        let b = both_ways(Frame::ConnectResponse {
            channel: 0,
            status: ErrorCode::NoMoreConnections.code(),
            address: None,
            data: None,
        });
        assert_eq!(b, [0x06, 0x10, 0x02, 0x06, 0x00, 0x08, 0x00, 0x24]);
        assert_eq!(status_text(0x24), "all tunnels of the interface are in use");
        assert_eq!(status_text(0x77), "status 0x77");
    }

    #[test]
    fn tunnelling_frames() {
        let cemi = vec![0x11, 0x00, 0xBC, 0xE0, 0, 0, 0x0A, 0x03, 0x01, 0x00, 0x81];
        let b = both_ways(Frame::TunnellingRequest {
            channel: 21,
            seq: 7,
            cemi: cemi.clone(),
        });
        assert_eq!(
            b[..10],
            [0x06, 0x10, 0x04, 0x20, 0x00, 0x15, 0x04, 21, 7, 0]
        );
        assert_eq!(b[10..], cemi[..]);
        let b = both_ways(Frame::TunnellingAck {
            channel: 21,
            seq: 7,
            status: 0,
        });
        assert_eq!(b, [0x06, 0x10, 0x04, 0x21, 0x00, 0x0A, 0x04, 21, 7, 0]);
    }

    #[test]
    fn connection_state_and_disconnect() {
        let b = both_ways(Frame::ConnectionStateRequest {
            channel: 21,
            control: Hpai::NAT,
        });
        assert_eq!(
            b,
            [0x06, 0x10, 0x02, 0x07, 0x00, 0x10, 21, 0, 0x08, 0x01, 0, 0, 0, 0, 0, 0]
        );
        both_ways(Frame::ConnectionStateResponse {
            channel: 21,
            status: 0x21,
        });
        let b = both_ways(Frame::DisconnectRequest {
            channel: 21,
            control: hpai(),
        });
        assert_eq!(b[..6], [0x06, 0x10, 0x02, 0x09, 0x00, 0x10]);
        both_ways(Frame::DisconnectResponse {
            channel: 21,
            status: 0,
        });
    }

    #[test]
    fn routing_frames() {
        let b = both_ways(Frame::RoutingIndication {
            cemi: vec![
                0x29, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x80,
            ],
        });
        assert_eq!(b[..6], [0x06, 0x10, 0x05, 0x30, 0x00, 0x11]);
        let b = both_ways(Frame::RoutingBusy { wait_ms: 100 });
        assert_eq!(
            b,
            [0x06, 0x10, 0x05, 0x32, 0x00, 0x0C, 0x06, 0, 0x00, 0x64, 0, 0]
        );
        let b = both_ways(Frame::RoutingLostMessage { lost: 3 });
        assert_eq!(b, [0x06, 0x10, 0x05, 0x31, 0x00, 0x0A, 0x04, 0, 0x00, 0x03]);
    }

    #[test]
    fn search_frames() {
        let b = both_ways(Frame::SearchRequest { discovery: hpai() });
        assert_eq!(b[..6], [0x06, 0x10, 0x02, 0x01, 0x00, 0x0E]);
        let device = DeviceInfo {
            medium: Medium::Tp1.code(),
            address: IndividualAddr(0x1100),
            serial: [0, 1, 2, 3, 4, 5],
            mac: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF],
            name: "Line coupler 1".into(),
        };
        let b = both_ways(Frame::SearchResponse {
            control: hpai(),
            device,
        });
        assert_eq!(b.len(), 6 + 8 + 54 + 8);
        assert_eq!(b[14..16], [0x36, 0x01]);
    }

    #[test]
    fn hpai_falls_back_to_the_sender() {
        let from = SocketAddrV4::new(Ipv4Addr::new(10, 0, 0, 9), 40000);
        assert_eq!(Hpai::NAT.or(from), from);
        assert_eq!(hpai().or(from), hpai().0);
    }

    #[test]
    fn refused_datagrams() {
        assert_eq!(Frame::decode(&[1, 2, 3]), Err(ProtoError::Header));
        assert_eq!(
            Frame::decode(&[0x06, 0x10, 0x02, 0x05, 0x00, 0x1A]),
            Err(ProtoError::Length { said: 26, got: 6 })
        );
        // a description request: a service this link does not speak
        assert_eq!(
            Frame::decode(&[0x06, 0x10, 0x02, 0x03, 0x00, 0x06]),
            Err(ProtoError::Service(0x0203))
        );
        // a routing code under the tunnelling family
        assert_eq!(
            Frame::decode(&[0x06, 0x10, 0x04, 0x30, 0x00, 0x06]),
            Err(ProtoError::Service(0x0430))
        );
        assert_eq!(
            Frame::decode(&[0x06, 0x10, 0x04, 0x21, 0x00, 0x08, 0x04, 21]),
            Err(ProtoError::Short("TUNNELLING_ACK"))
        );
    }
}
