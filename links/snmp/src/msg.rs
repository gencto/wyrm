//! SNMP messages: the community form of v2c (RFC 3416, 1901) and the v3
//! message with USM security parameters (RFC 3412, 3414). PDUs are the
//! v2 PDUs (RFC 3416).

use crate::ber::{self, BerError, Oid, Reader, Result, SnmpValue};

pub const GET: u8 = 0xA0;
pub const GET_NEXT: u8 = 0xA1;
pub const RESPONSE: u8 = 0xA2;
pub const SET: u8 = 0xA3;
pub const GET_BULK: u8 = 0xA5;
pub const INFORM: u8 = 0xA6;
pub const TRAP_V2: u8 = 0xA7;
pub const REPORT: u8 = 0xA8;

pub const VERSION_2C: i64 = 1;
pub const VERSION_3: i64 = 3;

/// USM (RFC 3414).
pub const SECURITY_MODEL_USM: i64 = 3;

/// `msgFlags` bits.
pub const FLAG_AUTH: u8 = 0x01;
pub const FLAG_PRIV: u8 = 0x02;
pub const FLAG_REPORTABLE: u8 = 0x04;

/// Our `msgMaxSize` (and the receive buffer).
pub const MAX_MESSAGE: usize = 65_507;

/// Error status names (RFC 3416), by value.
pub const ERROR_NAMES: [&str; 19] = [
    "noError",
    "tooBig",
    "noSuchName",
    "badValue",
    "readOnly",
    "genErr",
    "noAccess",
    "wrongType",
    "wrongLength",
    "wrongEncoding",
    "wrongValue",
    "noCreation",
    "inconsistentValue",
    "resourceUnavailable",
    "commitFailed",
    "undoFailed",
    "authorizationError",
    "notWritable",
    "inconsistentName",
];

pub const TOO_BIG: i32 = 1;
pub const NO_SUCH_NAME: i32 = 2;
pub const GEN_ERR: i32 = 5;
pub const NO_ACCESS: i32 = 6;
pub const WRONG_TYPE: i32 = 7;
pub const NOT_WRITABLE: i32 = 17;
pub const AUTHORIZATION_ERROR: i32 = 16;

pub fn error_name(status: i32) -> String {
    usize::try_from(status)
        .ok()
        .and_then(|i| ERROR_NAMES.get(i))
        .map_or_else(|| format!("error {status}"), |n| (*n).to_owned())
}

/// A v2 PDU. For GetBulk, `error_status` is `non-repeaters` and
/// `error_index` is `max-repetitions`.
#[derive(Debug, Clone, PartialEq)]
pub struct Pdu {
    pub ty: u8,
    pub request_id: i32,
    pub error_status: i32,
    pub error_index: i32,
    pub varbinds: Vec<(Oid, SnmpValue)>,
}

impl Pdu {
    /// A request for `oids` (values NULL).
    pub fn request(ty: u8, request_id: i32, oids: impl IntoIterator<Item = Oid>) -> Pdu {
        Pdu {
            ty,
            request_id,
            error_status: 0,
            error_index: 0,
            varbinds: oids.into_iter().map(|o| (o, SnmpValue::Null)).collect(),
        }
    }

    pub fn encode(&self, out: &mut Vec<u8>) {
        let mut c = Vec::with_capacity(32 + self.varbinds.len() * 24);
        ber::put_int(&mut c, ber::INTEGER, self.request_id.into());
        ber::put_int(&mut c, ber::INTEGER, self.error_status.into());
        ber::put_int(&mut c, ber::INTEGER, self.error_index.into());
        let mut list = Vec::with_capacity(self.varbinds.len() * 24);
        for (oid, v) in &self.varbinds {
            let mut vb = Vec::with_capacity(24);
            ber::put_oid(&mut vb, oid);
            ber::put_value(&mut vb, v);
            ber::tlv(&mut list, ber::SEQUENCE, &vb);
        }
        ber::tlv(&mut c, ber::SEQUENCE, &list);
        ber::tlv(out, self.ty, &c);
    }

    pub fn decode(ty: u8, content: &[u8]) -> Result<Pdu> {
        if !matches!(
            ty,
            GET | GET_NEXT | RESPONSE | SET | GET_BULK | INFORM | TRAP_V2 | REPORT
        ) {
            return Err(BerError("unknown PDU type"));
        }
        let mut r = Reader::new(content);
        let request_id = r.int32("request-id")?;
        let error_status = r.int32("error-status")?;
        let error_index = r.int32("error-index")?;
        let mut list = r.sequence("varbind list")?;
        let mut varbinds = Vec::new();
        while !list.is_empty() {
            let mut vb = list.sequence("varbind")?;
            let oid = ber::decode_oid(vb.expect(ber::OBJECT_ID, "varbind name")?)?;
            let (tag, c) = vb.tlv()?;
            // The framing is strict; a value that does not fit its type
            // fails only its own varbind (its point).
            let v = ber::decode_value(tag, c).unwrap_or(SnmpValue::Malformed(tag));
            varbinds.push((oid, v));
        }
        Ok(Pdu {
            ty,
            request_id,
            error_status,
            error_index,
            varbinds,
        })
    }
}

/// A v2c message.
pub fn encode_community(community: &[u8], pdu: &Pdu) -> Vec<u8> {
    let mut c = Vec::with_capacity(64 + community.len());
    ber::put_int(&mut c, ber::INTEGER, VERSION_2C);
    ber::tlv(&mut c, ber::OCTET_STRING, community);
    pdu.encode(&mut c);
    let mut out = Vec::with_capacity(c.len() + 4);
    ber::tlv(&mut out, ber::SEQUENCE, &c);
    out
}

/// The `contextEngineID`, `contextName` and PDU of a v3 message.
#[derive(Debug, Clone, PartialEq)]
pub struct ScopedPdu {
    pub engine_id: Vec<u8>,
    pub context: Vec<u8>,
    pub pdu: Pdu,
}

impl ScopedPdu {
    pub fn encode(&self) -> Vec<u8> {
        let mut c = Vec::with_capacity(64);
        ber::tlv(&mut c, ber::OCTET_STRING, &self.engine_id);
        ber::tlv(&mut c, ber::OCTET_STRING, &self.context);
        self.pdu.encode(&mut c);
        let mut out = Vec::with_capacity(c.len() + 4);
        ber::tlv(&mut out, ber::SEQUENCE, &c);
        out
    }

    /// From the first TLV of `buf` (decrypted data may carry padding).
    pub fn decode(buf: &[u8]) -> Result<ScopedPdu> {
        let mut r = Reader::new(buf).sequence("scopedPDU")?;
        let engine_id = r.octets("contextEngineID")?.to_vec();
        let context = r.octets("contextName")?.to_vec();
        let (ty, c) = r.tlv()?;
        Ok(ScopedPdu {
            engine_id,
            context,
            pdu: Pdu::decode(ty, c)?,
        })
    }
}

/// USM security parameters to send. `auth_len` zero octets stand in for
/// the MAC, which is put at [`V3Out::auth_at`] once the message is built.
pub struct UsmOut<'a> {
    pub engine_id: &'a [u8],
    pub boots: u32,
    pub time: u32,
    pub user: &'a [u8],
    pub auth_len: usize,
    pub priv_params: &'a [u8],
}

/// A built v3 message and where its MAC goes.
pub struct V3Out {
    pub bytes: Vec<u8>,
    pub auth_at: usize,
}

/// Header octets of a TLV with `n` content octets.
fn header_len(n: usize) -> usize {
    1 + if n < 0x80 {
        1
    } else {
        1 + (usize::BITS - n.leading_zeros()).div_ceil(8) as usize
    }
}

/// A v3 message. `data` is the scopedPDU TLV, or the OCTET STRING TLV of
/// the encrypted one.
pub fn encode_v3(msg_id: i32, flags: u8, usm: &UsmOut<'_>, data: &[u8]) -> V3Out {
    let mut global = Vec::with_capacity(16);
    ber::put_int(&mut global, ber::INTEGER, msg_id.into());
    ber::put_int(&mut global, ber::INTEGER, MAX_MESSAGE as i64);
    ber::tlv(&mut global, ber::OCTET_STRING, &[flags]);
    ber::put_int(&mut global, ber::INTEGER, SECURITY_MODEL_USM);

    let mut sp = Vec::with_capacity(64);
    ber::tlv(&mut sp, ber::OCTET_STRING, usm.engine_id);
    ber::put_int(&mut sp, ber::INTEGER, usm.boots.into());
    ber::put_int(&mut sp, ber::INTEGER, usm.time.into());
    ber::tlv(&mut sp, ber::OCTET_STRING, usm.user);
    let auth_in_sp = sp.len() + header_len(usm.auth_len);
    ber::tlv(&mut sp, ber::OCTET_STRING, &vec![0u8; usm.auth_len]);
    ber::tlv(&mut sp, ber::OCTET_STRING, usm.priv_params);
    let mut sp_seq = Vec::with_capacity(sp.len() + 4);
    ber::tlv(&mut sp_seq, ber::SEQUENCE, &sp);

    let mut c = Vec::with_capacity(64 + sp_seq.len() + data.len());
    ber::put_int(&mut c, ber::INTEGER, VERSION_3);
    ber::tlv(&mut c, ber::SEQUENCE, &global);
    let sp_at = c.len() + header_len(sp_seq.len()) + header_len(sp.len());
    ber::tlv(&mut c, ber::OCTET_STRING, &sp_seq);
    c.extend_from_slice(data);
    let mut bytes = Vec::with_capacity(c.len() + 4);
    ber::tlv(&mut bytes, ber::SEQUENCE, &c);
    let auth_at = header_len(c.len()) + sp_at + auth_in_sp;
    V3Out { bytes, auth_at }
}

/// Received USM parameters (borrowed from the datagram).
#[derive(Debug, Clone)]
pub struct UsmIn<'a> {
    pub engine_id: &'a [u8],
    pub boots: u32,
    pub time: u32,
    pub user: &'a [u8],
    pub auth: &'a [u8],
    /// Offset of `auth` in the datagram (zeroed to check the MAC).
    pub auth_at: usize,
    pub priv_params: &'a [u8],
}

/// The scoped PDU of a v3 message, plain or encrypted.
#[derive(Debug, Clone)]
pub enum ScopedData<'a> {
    Plain(ScopedPdu),
    Encrypted(&'a [u8]),
}

/// A received v3 message.
#[derive(Debug, Clone)]
pub struct V3In<'a> {
    pub msg_id: i32,
    pub max_size: i64,
    pub flags: u8,
    pub usm: UsmIn<'a>,
    pub data: ScopedData<'a>,
}

/// A received message.
#[derive(Debug, Clone)]
pub enum Message<'a> {
    Community {
        version: i64,
        community: &'a [u8],
        pdu: Pdu,
    },
    V3(V3In<'a>),
}

fn int_u32(v: i64, what: &'static str) -> Result<u32> {
    u32::try_from(v).map_err(|_| BerError(what))
}

pub fn decode(buf: &[u8]) -> Result<Message<'_>> {
    let mut outer = Reader::new(buf);
    let mut r = outer.sequence("message")?;
    let version = r.int("msgVersion")?;
    if version != VERSION_3 {
        let community = r.octets("community")?;
        let (ty, c) = r.tlv()?;
        return Ok(Message::Community {
            version,
            community,
            pdu: Pdu::decode(ty, c)?,
        });
    }
    let mut g = r.sequence("msgGlobalData")?;
    let msg_id = g.int32("msgID")?;
    let max_size = g.int("msgMaxSize")?;
    let flags = match g.octets("msgFlags")? {
        [f] => *f,
        _ => return Err(BerError("msgFlags is one octet")),
    };
    if g.int("msgSecurityModel")? != SECURITY_MODEL_USM {
        return Err(BerError("not the USM security model"));
    }
    let sp = r.octets("msgSecurityParameters")?;
    let mut s = Reader::new(sp).sequence("UsmSecurityParameters")?;
    let engine_id = s.octets("msgAuthoritativeEngineID")?;
    let boots = int_u32(s.int("engineBoots")?, "engineBoots")?;
    let time = int_u32(s.int("engineTime")?, "engineTime")?;
    let user = s.octets("msgUserName")?;
    let auth = s.octets("msgAuthenticationParameters")?;
    let priv_params = s.octets("msgPrivacyParameters")?;
    // Both slices borrow `buf`: the offset is their distance.
    let auth_at = (auth.as_ptr() as usize).wrapping_sub(buf.as_ptr() as usize);
    if auth_at
        .checked_add(auth.len())
        .is_none_or(|end| end > buf.len())
    {
        return Err(BerError("auth parameters outside the message"));
    }
    let (tag, c) = r.tlv()?;
    let data = match tag {
        ber::SEQUENCE => {
            let mut whole = Vec::with_capacity(c.len() + 4);
            ber::tlv(&mut whole, ber::SEQUENCE, c);
            ScopedData::Plain(ScopedPdu::decode(&whole)?)
        }
        ber::OCTET_STRING => ScopedData::Encrypted(c),
        _ => return Err(BerError("msgData")),
    };
    Ok(Message::V3(V3In {
        msg_id,
        max_size,
        flags,
        usm: UsmIn {
            engine_id,
            boots,
            time,
            user,
            auth,
            auth_at,
            priv_params,
        },
        data,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pdu() -> Pdu {
        Pdu {
            ty: RESPONSE,
            request_id: -77,
            error_status: 0,
            error_index: 0,
            varbinds: vec![
                (
                    Oid::parse("1.3.6.1.2.1.1.3.0").unwrap(),
                    SnmpValue::TimeTicks(100),
                ),
                (
                    Oid::parse("1.3.6.1.2.1.1.5.0").unwrap(),
                    SnmpValue::OctetString(b"x".to_vec()),
                ),
            ],
        }
    }

    #[test]
    fn community_roundtrip() {
        let b = encode_community(b"public", &pdu());
        match decode(&b).unwrap() {
            Message::Community {
                version,
                community,
                pdu: p,
            } => {
                assert_eq!((version, community, p), (1, &b"public"[..], pdu()));
            }
            Message::V3(_) => panic!("v2c"),
        }
    }

    /// The MAC offset found while building is the one the decoder finds,
    /// for short and long length forms.
    #[test]
    fn v3_roundtrip_and_auth_offset() {
        for (nvb, user) in [(1usize, &b"u"[..]), (40, &b"a-long-user-name"[..])] {
            let mut p = pdu();
            p.varbinds = std::iter::repeat_n(p.varbinds[1].clone(), nvb).collect();
            let sp = ScopedPdu {
                engine_id: vec![0x80, 0, 1, 2],
                context: b"ctx".to_vec(),
                pdu: p.clone(),
            };
            let usm = UsmOut {
                engine_id: &[0x80, 0, 1, 2],
                boots: 3,
                time: 300_000,
                user,
                auth_len: 24,
                priv_params: &[],
            };
            let mut out = encode_v3(9, FLAG_AUTH | FLAG_REPORTABLE, &usm, &sp.encode());
            out.bytes[out.auth_at..out.auth_at + 24].copy_from_slice(&[0xAB; 24]);
            let Message::V3(m) = decode(&out.bytes).unwrap() else {
                panic!("v3")
            };
            assert_eq!(m.msg_id, 9);
            assert_eq!(m.flags, FLAG_AUTH | FLAG_REPORTABLE);
            assert_eq!(m.usm.auth_at, out.auth_at);
            assert_eq!(m.usm.auth, &[0xAB; 24]);
            assert_eq!((m.usm.boots, m.usm.time, m.usm.user), (3, 300_000, user));
            match m.data {
                ScopedData::Plain(s) => assert_eq!(s, sp),
                ScopedData::Encrypted(_) => panic!("plain"),
            }
        }
    }

    #[test]
    fn header_lengths() {
        for n in [0usize, 1, 127, 128, 255, 256, 65_535, 65_536] {
            let mut out = Vec::new();
            ber::tlv(&mut out, 4, &vec![0; n]);
            assert_eq!(out.len() - n, header_len(n), "{n}");
        }
    }

    /// A 5-octet INTEGER and a Counter32 above 2^32 among good varbinds:
    /// those two are `Malformed`, the others keep their values.
    #[test]
    fn a_malformed_value_is_one_varbind() {
        let good = |oid: &str, v: SnmpValue| {
            let mut vb = Vec::new();
            ber::put_oid(&mut vb, &Oid::parse(oid).unwrap());
            ber::put_value(&mut vb, &v);
            vb
        };
        let raw = |oid: &str, value: &[u8]| {
            let mut vb = Vec::new();
            ber::put_oid(&mut vb, &Oid::parse(oid).unwrap());
            vb.extend_from_slice(value);
            vb
        };
        let vbs = [
            good("1.3.6.1.2.1.1.5.0", SnmpValue::OctetString(b"x".to_vec())),
            raw(
                "1.3.6.1.2.1.1.7.0",
                &[0x02, 0x05, 0x00, 0xFF, 0xFF, 0xFF, 0xFF],
            ),
            raw("1.3.6.1.2.1.2.2.1.10.1", &[0x41, 0x05, 0x01, 0, 0, 0, 0]),
            good("1.3.6.1.2.1.1.3.0", SnmpValue::TimeTicks(7)),
        ];
        let mut list = Vec::new();
        for vb in &vbs {
            ber::tlv(&mut list, ber::SEQUENCE, vb);
        }
        let mut c = Vec::new();
        ber::put_int(&mut c, ber::INTEGER, 5);
        ber::put_int(&mut c, ber::INTEGER, 0);
        ber::put_int(&mut c, ber::INTEGER, 0);
        ber::tlv(&mut c, ber::SEQUENCE, &list);
        let p = Pdu::decode(RESPONSE, &c).unwrap();
        let values: Vec<SnmpValue> = p.varbinds.into_iter().map(|(_, v)| v).collect();
        assert_eq!(
            values,
            [
                SnmpValue::OctetString(b"x".to_vec()),
                SnmpValue::Malformed(ber::INTEGER),
                SnmpValue::Malformed(ber::COUNTER32),
                SnmpValue::TimeTicks(7),
            ]
        );
        // the framing stays strict: a varbind without a name
        let mut c2 = Vec::new();
        ber::put_int(&mut c2, ber::INTEGER, 5);
        ber::put_int(&mut c2, ber::INTEGER, 0);
        ber::put_int(&mut c2, ber::INTEGER, 0);
        let mut l2 = Vec::new();
        ber::tlv(&mut l2, ber::SEQUENCE, &[0x02, 0x01, 0x00]);
        ber::tlv(&mut c2, ber::SEQUENCE, &l2);
        assert!(Pdu::decode(RESPONSE, &c2).is_err());
    }

    #[test]
    fn garbage_is_an_error() {
        assert!(decode(&[0x30, 0x03, 0x02, 0x01, 0x01]).is_err());
        assert!(decode(&[0x30, 0x00]).is_err());
        assert_eq!(error_name(16), "authorizationError");
        assert_eq!(error_name(99), "error 99");
    }
}
