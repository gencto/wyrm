use super::*;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_core::{ActionMeta, NodeMeta, Sample, Status};
use wyrm_link_api::{AppError, Level, ReqId, SubId, TimerId};

/// A host with real TCP (tests run natively; TLS is the portable host's own test).
#[derive(Default)]
struct TcpHost {
    conns: HashMap<u32, TcpStream>,
    next: u32,
}

fn unsupported<T>() -> Result<T, AppError> {
    Err(AppError::new(Status::NotSupported, "not in this test"))
}

impl Host for TcpHost {
    fn declare_node(&mut self, _p: &str, _m: NodeMeta) {}
    fn declare_action(&mut self, _p: &str, _n: &str, _a: ActionMeta) {}
    fn remove_node(&mut self, _p: &str) {}
    fn update(&mut self, _p: &str, _s: Sample) {}
    fn now_us(&self) -> u64 {
        0
    }
    fn set_timer(&mut self, _ms: u64) -> Result<TimerId, AppError> {
        unsupported()
    }
    fn cancel_timer(&mut self, _t: TimerId) {}
    fn store_get(&self, _k: &str) -> Option<Vec<u8>> {
        None
    }
    fn store_put(&mut self, _k: &str, _v: &[u8]) -> Result<(), AppError> {
        unsupported()
    }
    fn store_delete(&mut self, _k: &str) {}
    fn subscribe(&mut self, _k: &str) -> Result<SubId, AppError> {
        unsupported()
    }
    fn unsubscribe(&mut self, _s: SubId) {}
    fn set(&mut self, _k: &str, _v: Value) -> Result<ReqId, AppError> {
        unsupported()
    }
    fn invoke(&mut self, _k: &str, _a: &str, _v: Value) -> Result<ReqId, AppError> {
        unsupported()
    }
    fn tcp_connect(&mut self, addr: &str, port: u16, _t: u32) -> Result<ConnId, AppError> {
        let s = TcpStream::connect((addr, port))
            .map_err(|e| AppError::new(Status::Disconnected, e.to_string()))?;
        s.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        self.next += 1;
        self.conns.insert(self.next, s);
        Ok(ConnId(self.next))
    }
    fn tcp_send(&mut self, c: ConnId, d: &[u8]) -> Result<(), AppError> {
        let s = self
            .conns
            .get_mut(&c.0)
            .ok_or(AppError::new(Status::NotFound, "conn"))?;
        s.write_all(d)
            .map_err(|e| AppError::new(Status::Disconnected, e.to_string()))
    }
    fn tcp_recv(&mut self, c: ConnId, max: u32, _t: u32) -> Result<Vec<u8>, AppError> {
        let s = self
            .conns
            .get_mut(&c.0)
            .ok_or(AppError::new(Status::NotFound, "conn"))?;
        let mut b = vec![0u8; max as usize];
        let n = s
            .read(&mut b)
            .map_err(|e| AppError::new(Status::Disconnected, e.to_string()))?;
        b.truncate(n);
        Ok(b)
    }
    fn tcp_close(&mut self, c: ConnId) {
        self.conns.remove(&c.0);
    }
    fn log(&mut self, _l: Level, _m: &str) {}
}

/// One request as the fake server got it.
#[derive(Debug, Clone)]
struct Got {
    line: String,
    head: String,
    body: String,
}

/// An InfluxDB stand-in: answers each request with the next status of
/// `script` (`close` sends `Connection: close` and ends the connection).
/// The fake server's port, the requests it got and how many connections it took.
type Server = (u16, Arc<Mutex<Vec<Got>>>, Arc<Mutex<u32>>);

fn server(script: Vec<(u16, bool)>) -> Server {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    let got = Arc::new(Mutex::new(Vec::new()));
    let accepted = Arc::new(Mutex::new(0u32));
    let (g, a) = (got.clone(), accepted.clone());
    std::thread::spawn(move || {
        let mut script = script.into_iter();
        for mut s in l.incoming().flatten() {
            *a.lock().unwrap() += 1;
            loop {
                let mut buf = Vec::new();
                let mut b = [0u8; 4096];
                let end = loop {
                    if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                        break i;
                    }
                    match s.read(&mut b) {
                        Ok(0) | Err(_) => return,
                        Ok(n) => buf.extend_from_slice(&b[..n]),
                    }
                };
                let head = String::from_utf8_lossy(&buf[..end]).into_owned();
                let len = head
                    .lines()
                    .find_map(|l| l.strip_prefix("Content-Length: "))
                    .and_then(|n| n.parse::<usize>().ok())
                    .unwrap_or(0);
                let mut body = buf[end + 4..].to_vec();
                while body.len() < len {
                    let n = s.read(&mut b).unwrap();
                    body.extend_from_slice(&b[..n]);
                }
                g.lock().unwrap().push(Got {
                    line: head.lines().next().unwrap_or_default().to_owned(),
                    head: head.clone(),
                    body: String::from_utf8_lossy(&body).into_owned(),
                });
                let Some((status, close)) = script.next() else {
                    return;
                };
                let msg = if status >= 300 {
                    "{\"message\":\"no\"}"
                } else {
                    ""
                };
                let conn = if close { "Connection: close\r\n" } else { "" };
                let resp = format!(
                    "HTTP/1.1 {status} X\r\nContent-Length: {}\r\n{conn}\r\n{msg}",
                    msg.len()
                );
                s.write_all(resp.as_bytes()).unwrap();
                if close {
                    break;
                }
            }
        }
    });
    (port, got, accepted)
}

fn cfg(port: u16) -> Map {
    Map::from([
        (
            "url".to_owned(),
            Value::from(format!("http://127.0.0.1:{port}")),
        ),
        ("org".to_owned(), Value::from("my org")),
        ("bucket".to_owned(), Value::from("plant")),
    ])
}

fn row(seq: u64, v: Value) -> Row {
    Row {
        seq,
        site: "edge".into(),
        key: "wy/edge/downstream/mock/g0/p 1".into(),
        t: 1_700_000_000_000_000 + seq,
        v,
        q: Quality::Good,
    }
}

#[test]
fn params_are_checked() {
    assert!(Influx::check(&cfg(8086)).is_ok());
    let with = |k: &str, v: Value| {
        let mut c = cfg(8086);
        c.insert(k.into(), v);
        Influx::check(&c).unwrap_err()
    };
    assert!(with("oops", Value::UInt(1)).contains("oops"));
    assert!(with("url", Value::from("http://10.0.0.5:8086")).contains("in the clear"));
    assert!(with("url", Value::from("ftp://x")).contains("http"));
    assert!(with("timeout_ms", Value::UInt(5)).contains("timeout_ms"));
    let mut c = cfg(8086);
    c.insert("url".into(), Value::from("http://10.0.0.5:8086"));
    c.insert("insecure_plaintext".into(), Value::Bool(true));
    assert!(Influx::check(&c).is_ok());
    c.remove("org");
    assert!(Influx::check(&c).unwrap_err().contains("org"));
}

#[test]
fn line_protocol() {
    let rows = [
        row(1, Value::Float(21.5)),
        row(2, Value::Int(-3)),
        row(3, Value::UInt(7)),
        row(4, Value::Bool(true)),
        row(5, Value::from("a \"b\"\nc")),
        row(6, Value::Null),
        row(7, Value::Float(f64::NAN)),
        row(8, Value::Float(2.0)),
    ];
    let text = lines("my m,x", &rows);
    let l: Vec<&str> = text.lines().collect();
    let tags = "my\\ m\\,x,site=edge,key=wy/edge/downstream/mock/g0/p\\ 1";
    assert_eq!(
        l,
        [
            format!("{tags} value=21.5,quality=0i 1700000000000001"),
            format!("{tags} value=-3i,quality=0i 1700000000000002"),
            format!("{tags} value=7u,quality=0i 1700000000000003"),
            format!("{tags} value=true,quality=0i 1700000000000004"),
            format!("{tags} value=\"a \\\"b\\\" c\",quality=0i 1700000000000005"),
            format!("{tags} value=2.0,quality=0i 1700000000000008"),
        ],
        "null and NaN are left out"
    );
}

#[test]
fn writes_and_classifies_answers() {
    let (port, got, accepted) = server(vec![
        (204, false),
        (204, false),
        (503, false),
        (401, true),
        (204, false),
    ]);
    let mut h = TcpHost::default();
    let mut t = Influx::connect(&mut h, &cfg(port), Some("tok")).unwrap();
    t.ping(&mut h).unwrap();
    t.write(&mut h, &[row(1, Value::Float(1.0))]).unwrap();
    let e = t.write(&mut h, &[row(2, Value::Float(2.0))]).unwrap_err();
    assert!(matches!(e, TargetError::Retry(_)), "503: {e}");
    let e = t.write(&mut h, &[row(3, Value::Float(3.0))]).unwrap_err();
    assert!(matches!(e, TargetError::Fatal(_)), "401: {e}");
    assert!(e.message().contains("401"), "{e}");
    // the server closed after the 401: the next write opens a new connection
    t.write(&mut h, &[row(4, Value::Float(4.0))]).unwrap();
    assert_eq!(*accepted.lock().unwrap(), 2);
    // nothing to write: no request
    t.write(&mut h, &[row(5, Value::Null)]).unwrap();
    let got = got.lock().unwrap();
    assert_eq!(got.len(), 5);
    assert_eq!(got[0].line, "GET /ping HTTP/1.1");
    assert_eq!(
        got[1].line,
        "POST /api/v2/write?org=my%20org&bucket=plant&precision=us HTTP/1.1"
    );
    assert!(
        got[1].head.contains("\r\nAuthorization: Token tok"),
        "{}",
        got[1].head
    );
    assert!(
        got[1].body.ends_with(" 1700000000000001\n"),
        "{}",
        got[1].body
    );
}

#[test]
fn a_refused_connection_is_reconnect() {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    drop(l);
    let mut h = TcpHost::default();
    let e = Influx::connect(&mut h, &cfg(port), None).err().unwrap();
    assert!(matches!(e, TargetError::Reconnect(_)), "{e}");
}
