//! MQTT 3.1.1 (OASIS, 2014) as a client, over bytes the host moves (ADR 0035): the packets a
//! publisher sends (CONNECT, PUBLISH, SUBSCRIBE, PINGREQ, DISCONNECT, PUBACK) and a parser of what
//! a broker answers (CONNACK, PUBACK, SUBACK, PINGRESP, PUBLISH). Nothing here does I/O.

/// Packet types (the high nibble of the first byte).
pub const CONNECT: u8 = 1;
pub const CONNACK: u8 = 2;
pub const PUBLISH: u8 = 3;
pub const PUBACK: u8 = 4;
pub const SUBSCRIBE: u8 = 8;
pub const SUBACK: u8 = 9;
pub const PINGREQ: u8 = 12;
pub const PINGRESP: u8 = 13;
pub const DISCONNECT: u8 = 14;

/// The largest packet taken from a broker (a command payload is small; a bigger one is a fault).
pub const MAX_PACKET: usize = 1 << 20;
/// The longest topic or string sent (the protocol's bound).
pub const MAX_STRING: usize = 65_535;

/// What CONNECT carries.
pub struct Connect<'a> {
    pub client_id: &'a str,
    pub username: Option<&'a str>,
    pub password: Option<&'a [u8]>,
    pub keep_alive_s: u16,
    pub clean_session: bool,
    pub will: Option<Will<'a>>,
}

pub struct Will<'a> {
    pub topic: &'a str,
    pub payload: &'a [u8],
    pub qos: u8,
    pub retain: bool,
}

/// A packet from the broker.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Packet {
    ConnAck {
        session_present: bool,
        code: u8,
    },
    PubAck(u16),
    SubAck {
        id: u16,
        codes: Vec<u8>,
    },
    PingResp,
    Publish {
        topic: String,
        payload: Vec<u8>,
        qos: u8,
        retain: bool,
        id: Option<u16>,
    },
    /// Anything else (PUBREC, UNSUBACK, …): skipped.
    Other(u8),
}

/// The CONNACK return codes (3.2.2.3).
pub fn connack_text(code: u8) -> &'static str {
    match code {
        0 => "accepted",
        1 => "unacceptable protocol version",
        2 => "identifier rejected",
        3 => "server unavailable",
        4 => "bad user name or password",
        5 => "not authorized",
        _ => "unknown return code",
    }
}

fn remaining_length(out: &mut Vec<u8>, mut n: usize) {
    loop {
        let mut b = (n % 128) as u8;
        n /= 128;
        if n > 0 {
            b |= 0x80;
        }
        out.push(b);
        if n == 0 {
            return;
        }
    }
}

/// A length-prefixed UTF-8 string (1.5.3); the caller keeps it under [`MAX_STRING`].
fn string(out: &mut Vec<u8>, s: &[u8]) {
    let n = s.len().min(MAX_STRING);
    out.extend((n as u16).to_be_bytes());
    out.extend(&s[..n]);
}

fn packet(ty: u8, flags: u8, body: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(body.len() + 5);
    out.push((ty << 4) | (flags & 0x0f));
    remaining_length(&mut out, body.len());
    out.extend(body);
    out
}

pub fn connect(c: &Connect<'_>) -> Vec<u8> {
    let mut body = Vec::new();
    string(&mut body, b"MQTT");
    body.push(4); // protocol level 3.1.1
    let mut flags = 0u8;
    if c.clean_session {
        flags |= 0x02;
    }
    if let Some(w) = &c.will {
        flags |= 0x04 | ((w.qos.min(2)) << 3);
        if w.retain {
            flags |= 0x20;
        }
    }
    if c.password.is_some() {
        flags |= 0x40;
    }
    if c.username.is_some() {
        flags |= 0x80;
    }
    body.push(flags);
    body.extend(c.keep_alive_s.to_be_bytes());
    string(&mut body, c.client_id.as_bytes());
    if let Some(w) = &c.will {
        string(&mut body, w.topic.as_bytes());
        string(&mut body, w.payload);
    }
    if let Some(u) = c.username {
        string(&mut body, u.as_bytes());
    }
    if let Some(p) = c.password {
        string(&mut body, p);
    }
    packet(CONNECT, 0, &body)
}

/// PUBLISH; `id` only with QoS 1 or 2.
pub fn publish(topic: &str, payload: &[u8], qos: u8, retain: bool, id: Option<u16>) -> Vec<u8> {
    let mut body = Vec::with_capacity(topic.len() + payload.len() + 4);
    string(&mut body, topic.as_bytes());
    if qos > 0 {
        body.extend(id.unwrap_or(1).to_be_bytes());
    }
    body.extend(payload);
    let mut flags = (qos.min(2)) << 1;
    if retain {
        flags |= 0x01;
    }
    packet(PUBLISH, flags, &body)
}

pub fn subscribe(id: u16, topics: &[(&str, u8)]) -> Vec<u8> {
    let mut body = Vec::new();
    body.extend(id.to_be_bytes());
    for (t, q) in topics {
        string(&mut body, t.as_bytes());
        body.push(q.min(&2).to_owned());
    }
    packet(SUBSCRIBE, 0x02, &body)
}

pub fn puback(id: u16) -> Vec<u8> {
    packet(PUBACK, 0, &id.to_be_bytes())
}

pub fn pingreq() -> Vec<u8> {
    packet(PINGREQ, 0, &[])
}

pub fn disconnect() -> Vec<u8> {
    packet(DISCONNECT, 0, &[])
}

/// Bytes from the broker, cut into packets.
#[derive(Default, Debug)]
pub struct Parser {
    buf: Vec<u8>,
}

impl Parser {
    pub fn feed(&mut self, bytes: &[u8]) -> Result<(), String> {
        if self.buf.len() + bytes.len() > MAX_PACKET + 5 {
            return Err("packet over 1 MiB".into());
        }
        self.buf.extend(bytes);
        Ok(())
    }

    /// The next whole packet, `None` while one is incomplete.
    pub fn packet(&mut self) -> Result<Option<Packet>, String> {
        if self.buf.len() < 2 {
            return Ok(None);
        }
        let Some((len, n)) = varint(&self.buf[1..]) else {
            return Ok(None);
        };
        if len > MAX_PACKET {
            return Err("bad remaining length".into());
        }
        let head = 1 + n;
        if self.buf.len() < head + len {
            return Ok(None);
        }
        let first = self.buf[0];
        let body: Vec<u8> = self.buf[head..head + len].to_vec();
        self.buf.drain(..head + len);
        let (ty, flags) = (first >> 4, first & 0x0f);
        let be16 = |b: &[u8], at: usize| -> Result<u16, String> {
            b.get(at..at + 2)
                .map(|x| u16::from_be_bytes([x[0], x[1]]))
                .ok_or_else(|| "short packet".to_owned())
        };
        Ok(Some(match ty {
            CONNACK => Packet::ConnAck {
                session_present: body.first().is_some_and(|f| f & 1 == 1),
                code: *body.get(1).ok_or("short CONNACK")?,
            },
            PUBACK => Packet::PubAck(be16(&body, 0)?),
            SUBACK => Packet::SubAck {
                id: be16(&body, 0)?,
                codes: body.get(2..).map(<[u8]>::to_vec).unwrap_or_default(),
            },
            PINGRESP => Packet::PingResp,
            PUBLISH => {
                let qos = (flags >> 1) & 0x03;
                let tlen = be16(&body, 0)? as usize;
                let topic = body
                    .get(2..2 + tlen)
                    .ok_or("short PUBLISH")
                    .and_then(|t| std::str::from_utf8(t).map_err(|_| "topic not UTF-8"))?
                    .to_owned();
                let mut at = 2 + tlen;
                let id = if qos > 0 {
                    at += 2;
                    Some(be16(&body, at - 2)?)
                } else {
                    None
                };
                Packet::Publish {
                    topic,
                    payload: body.get(at..).unwrap_or_default().to_vec(),
                    qos,
                    retain: flags & 1 == 1,
                    id,
                }
            }
            other => Packet::Other(other),
        }))
    }
}

/// A remaining-length varint: `(value, bytes)`, or `None` while incomplete (≤ 4 bytes).
fn varint(b: &[u8]) -> Option<(usize, usize)> {
    let mut v = 0usize;
    let mut mul = 1usize;
    for (i, x) in b.iter().take(4).enumerate() {
        v += usize::from(x & 0x7f) * mul;
        if x & 0x80 == 0 {
            return Some((v, i + 1));
        }
        mul *= 128;
    }
    if b.len() >= 4 {
        // a fifth byte is malformed: give it back as a huge length
        return Some((MAX_PACKET + 1, 4));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connect_with_everything() {
        let c = connect(&Connect {
            client_id: "wyrm",
            username: Some("u"),
            password: Some(b"p"),
            keep_alive_s: 60,
            clean_session: true,
            will: Some(Will {
                topic: "w",
                payload: b"x",
                qos: 1,
                retain: false,
            }),
        });
        assert_eq!(c[0], 0x10);
        // flags: user, pass, will qos 1, will, clean
        assert_eq!(c[9], 0x80 | 0x40 | 0x08 | 0x04 | 0x02);
        assert_eq!(&c[10..12], &[0, 60]);
        assert_eq!(c.len() as u8, c[1] + 2);
    }

    #[test]
    fn publish_and_parse_round_trip() {
        let p = publish("a/b", b"hello", 1, true, Some(7));
        assert_eq!(p[0], 0x33);
        let mut parser = Parser::default();
        parser.feed(&p[..3]).unwrap();
        assert_eq!(parser.packet().unwrap(), None);
        parser.feed(&p[3..]).unwrap();
        parser.feed(&[0x40, 2, 0, 7, 0xd0, 0]).unwrap();
        assert_eq!(
            parser.packet().unwrap(),
            Some(Packet::Publish {
                topic: "a/b".into(),
                payload: b"hello".to_vec(),
                qos: 1,
                retain: true,
                id: Some(7)
            })
        );
        assert_eq!(parser.packet().unwrap(), Some(Packet::PubAck(7)));
        assert_eq!(parser.packet().unwrap(), Some(Packet::PingResp));
        assert_eq!(parser.packet().unwrap(), None);
    }

    #[test]
    fn long_lengths_and_bad_ones() {
        let big = publish("t", &vec![0u8; 200_000], 0, false, None);
        let mut parser = Parser::default();
        parser.feed(&big).unwrap();
        assert!(
            matches!(parser.packet().unwrap(), Some(Packet::Publish { payload, .. }) if payload.len() == 200_000)
        );
        let mut bad = Parser::default();
        bad.feed(&[0x30, 0xff, 0xff, 0xff, 0xff, 0x7f]).unwrap();
        assert!(bad.packet().is_err());
        assert_eq!(
            subscribe(3, &[("spBv1.0/g/NCMD/n", 0)])[0],
            0x82,
            "SUBSCRIBE has the reserved flags"
        );
        assert_eq!(connack_text(5), "not authorized");
    }
}
