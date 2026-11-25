//! cEMI L_Data frames (the bus telegram as KNXnet/IP carries it) with the
//! three group services: GroupValue_Read, GroupValue_Response and
//! GroupValue_Write.
//!
//! ```text
//! mc | add. info length | [add. info] | ctrl1 | ctrl2 | source (2) | destination (2)
//!    | L | TPCI + APCI high | APCI low + 6 data bits | [data: L - 1 octets]
//! ```

use crate::addr::{GroupAddr, IndividualAddr};

wyrm_core::wire_enum! {
    /// cEMI message code of the data link layer.
    pub enum MessageCode {
        /// A telegram to send.
        DataReq = 0x11 => "L_Data.req",
        /// A telegram seen on the bus.
        DataInd = 0x29 => "L_Data.ind",
        /// The confirmation of a sent telegram.
        DataCon = 0x2E => "L_Data.con",
    }
}

wyrm_core::wire_enum! {
    /// The group services: the upper four bits of the APCI.
    pub enum Apci {
        Read = 0 => "GroupValue_Read",
        Response = 1 => "GroupValue_Response",
        Write = 2 => "GroupValue_Write",
    }
}

/// Standard frame, repeat allowed, broadcast, priority low, no
/// acknowledge request, no error.
const CTRL1: u8 = 0xBC;
/// Group address, hop count 6, standard frame format.
const CTRL2: u8 = 0xE0;
/// `ctrl1` bit 0 of an L_Data.con: the telegram was not acknowledged.
const CONFIRM_ERROR: u8 = 0x01;
/// `ctrl2` bit 7: the destination is a group address.
const GROUP: u8 = 0x80;
/// Data octets of a standard frame at most (DPT 16 uses all of them).
pub const MAX_DATA: usize = 14;

/// Why a cEMI frame is not taken.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum FrameError {
    #[error("frame cut short at octet {0}")]
    Short(usize),
    #[error("message code 0x{} is not an L_Data service", wyrm_core::hex::encode_upper([*.0]))]
    MessageCode(u8),
    #[error("{0} data octets, more than a standard frame holds (14)")]
    TooLong(usize),
}

/// The value octets of a group telegram.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Data {
    /// The value is the six bits beside the APCI (datapoint types of main
    /// number 1, 2 and 3); `bytes` then holds that one octet.
    pub short: bool,
    pub bytes: Vec<u8>,
}

impl Data {
    /// A value of at most six bits.
    pub fn short(v: u8) -> Self {
        Data {
            short: true,
            bytes: vec![v & 0x3F],
        }
    }

    /// A value of whole octets.
    pub fn long(bytes: Vec<u8>) -> Self {
        Data {
            short: false,
            bytes,
        }
    }
}

/// What an L_Data frame carries.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Service {
    /// A group service with its value (empty for a read).
    Group(Apci, Data),
    /// Any other transport or application service (device management,
    /// connections to one device): its ten APCI bits, when it has any.
    Other(Option<u16>),
}

/// One L_Data frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LData {
    pub code: MessageCode,
    pub source: IndividualAddr,
    /// The destination as on the wire: a group address when `group`.
    pub destination: u16,
    pub group: bool,
    /// An L_Data.con says the telegram was not acknowledged on the bus.
    pub failed: bool,
    pub service: Service,
}

impl LData {
    /// A group telegram from `source` to `to`.
    pub fn group(
        code: MessageCode,
        source: IndividualAddr,
        to: GroupAddr,
        apci: Apci,
        data: Data,
    ) -> Self {
        LData {
            code,
            source,
            destination: to.0,
            group: true,
            failed: false,
            service: Service::Group(apci, data),
        }
    }

    /// The group address and service of a group telegram.
    pub fn as_group(&self) -> Option<(GroupAddr, Apci, &Data)> {
        match &self.service {
            Service::Group(apci, data) if self.group => {
                Some((GroupAddr(self.destination), *apci, data))
            }
            _ => None,
        }
    }

    /// The same telegram under another message code (a request confirmed
    /// or shown to the other side).
    pub fn with_code(&self, code: MessageCode) -> Self {
        LData {
            code,
            ..self.clone()
        }
    }

    pub fn encode(&self) -> Result<Vec<u8>, FrameError> {
        let ctrl1 = CTRL1 | if self.failed { CONFIRM_ERROR } else { 0 };
        let ctrl2 = if self.group { CTRL2 } else { CTRL2 & !GROUP };
        let mut out = vec![self.code.code(), 0, ctrl1, ctrl2];
        out.extend(self.source.0.to_be_bytes());
        out.extend(self.destination.to_be_bytes());
        match &self.service {
            Service::Group(apci, data) => {
                let code = apci.code();
                let (high, low) = (code >> 2, (code & 0x03) << 6);
                match (data.short, data.bytes.as_slice()) {
                    (_, []) => out.extend([1, high, low]),
                    (true, [v, ..]) => out.extend([1, high, low | (v & 0x3F)]),
                    (false, bytes) => {
                        if bytes.len() > MAX_DATA {
                            return Err(FrameError::TooLong(bytes.len()));
                        }
                        let len = u8::try_from(bytes.len() + 1)
                            .map_err(|_e| FrameError::TooLong(bytes.len()))?;
                        out.extend([len, high, low]);
                        out.extend(bytes);
                    }
                }
            }
            Service::Other(Some(apci)) => {
                let [high, low] = apci.to_be_bytes();
                out.extend([1, high & 0x03, low]);
            }
            Service::Other(None) => out.extend([0, 0]),
        }
        Ok(out)
    }

    pub fn decode(b: &[u8]) -> Result<Self, FrameError> {
        let [mc, add_len, rest @ ..] = b else {
            return Err(FrameError::Short(b.len()));
        };
        let code = MessageCode::try_from(*mc).map_err(FrameError::MessageCode)?;
        let rest = rest
            .get(usize::from(*add_len)..)
            .ok_or(FrameError::Short(b.len()))?;
        let [ctrl1, ctrl2, s0, s1, d0, d1, len, tpdu @ ..] = rest else {
            return Err(FrameError::Short(b.len()));
        };
        let len = usize::from(*len);
        let tpdu = tpdu.get(..=len).ok_or(FrameError::Short(b.len()))?;
        let group = ctrl2 & GROUP != 0;
        let service = match tpdu {
            // a data telegram to a group: TPCI 000000
            [t, a, data @ ..] if group && t & 0xFC == 0 => {
                let four = ((t & 0x03) << 2) | (a >> 6);
                match Apci::try_from(four) {
                    Ok(Apci::Read) => Service::Group(Apci::Read, Data::default()),
                    Ok(apci) if data.is_empty() => Service::Group(apci, Data::short(*a)),
                    Ok(apci) => Service::Group(apci, Data::long(data.to_vec())),
                    Err(_) => Service::Other(Some(u16::from_be_bytes([t & 0x03, *a]))),
                }
            }
            [t, a, ..] => Service::Other(Some(u16::from_be_bytes([t & 0x03, *a]))),
            _ => Service::Other(None),
        };
        Ok(LData {
            code,
            source: IndividualAddr(u16::from_be_bytes([*s0, *s1])),
            destination: u16::from_be_bytes([*d0, *d1]),
            group,
            failed: code == MessageCode::DataCon && ctrl1 & CONFIRM_ERROR != 0,
            service,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(apci: Apci, data: Data) -> LData {
        LData::group(
            MessageCode::DataReq,
            IndividualAddr(0x1105),
            GroupAddr(0x0A03),
            apci,
            data,
        )
    }

    #[test]
    fn a_read_is_two_octets_of_apdu() {
        let b = frame(Apci::Read, Data::default()).encode().unwrap();
        assert_eq!(
            b,
            [0x11, 0x00, 0xBC, 0xE0, 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x00]
        );
        assert_eq!(
            LData::decode(&b).unwrap(),
            frame(Apci::Read, Data::default())
        );
    }

    #[test]
    fn a_switch_write_rides_in_the_apci_octet() {
        let f = frame(Apci::Write, Data::short(1));
        let b = f.encode().unwrap();
        assert_eq!(b[8..], [0x01, 0x00, 0x81]);
        assert_eq!(LData::decode(&b).unwrap(), f);
    }

    #[test]
    fn a_two_octet_response_follows_the_apci() {
        let f = frame(Apci::Response, Data::long(vec![0x0C, 0x1A]));
        let b = f.encode().unwrap();
        assert_eq!(b[8..], [0x03, 0x00, 0x40, 0x0C, 0x1A]);
        assert_eq!(LData::decode(&b).unwrap(), f);
    }

    #[test]
    fn additional_info_is_skipped() {
        let mut b = frame(Apci::Write, Data::short(0)).encode().unwrap();
        b[1] = 3;
        b.splice(2..2, [0x03, 0x01, 0x00]);
        let f = LData::decode(&b).unwrap();
        assert_eq!(
            f.as_group(),
            Some((GroupAddr(0x0A03), Apci::Write, &Data::short(0)))
        );
    }

    #[test]
    fn a_negative_confirmation_is_told() {
        let mut b = frame(Apci::Write, Data::short(1))
            .with_code(MessageCode::DataCon)
            .encode()
            .unwrap();
        assert!(!LData::decode(&b).unwrap().failed);
        b[2] |= 0x01;
        assert!(LData::decode(&b).unwrap().failed);
    }

    #[test]
    fn other_services_are_not_group_values() {
        // a telegram to an individual address
        let mut b = frame(Apci::Write, Data::short(1)).encode().unwrap();
        b[3] = 0x60;
        assert_eq!(LData::decode(&b).unwrap().as_group(), None);
        // a numbered data packet to a group (TPCI not 0)
        let mut b = frame(Apci::Write, Data::short(1)).encode().unwrap();
        b[9] = 0x40;
        assert_eq!(LData::decode(&b).unwrap().as_group(), None);
        // an APCI that is no group service (IndividualAddress_Write)
        let mut b = frame(Apci::Write, Data::short(0)).encode().unwrap();
        b[10] = 0xC0;
        assert_eq!(
            LData::decode(&b).unwrap().service,
            Service::Other(Some(0x00C0))
        );
    }

    #[test]
    fn broken_frames_are_refused() {
        assert_eq!(LData::decode(&[0x11]), Err(FrameError::Short(1)));
        assert_eq!(
            LData::decode(&[0x2B, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            Err(FrameError::MessageCode(0x2B))
        );
        let b = frame(Apci::Response, Data::long(vec![1, 2, 3]))
            .encode()
            .unwrap();
        assert!(matches!(
            LData::decode(&b[..b.len() - 1]),
            Err(FrameError::Short(_))
        ));
        assert_eq!(
            frame(Apci::Write, Data::long(vec![0; 15])).encode(),
            Err(FrameError::TooLong(15))
        );
    }
}
