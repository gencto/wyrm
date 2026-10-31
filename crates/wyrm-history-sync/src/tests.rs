use super::*;
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use wyrm_link_api::{ConnId, SubId};

/// A host that records what the app asks for; timers and requests are
/// fired by the test.
#[derive(Default)]
struct Fake {
    values: HashMap<String, Value>,
    store: HashMap<String, Vec<u8>>,
    timers: Vec<(TimerId, u64)>,
    invokes: Vec<(ReqId, String, String, Value)>,
    next: u64,
    /// What `tcp_recv` hands out, in order; then the connection is closed.
    recv: Vec<Vec<u8>>,
    sent: Vec<u8>,
}

impl Host for Fake {
    fn declare_node(&mut self, _path: &str, _meta: NodeMeta) {}
    fn declare_action(&mut self, _path: &str, _name: &str, _action: ActionMeta) {}
    fn remove_node(&mut self, _path: &str) {}
    fn update(&mut self, path: &str, sample: Sample) {
        self.values.insert(path.to_owned(), sample.v);
    }
    fn now_us(&self) -> u64 {
        1
    }
    fn set_timer(&mut self, after_ms: u64) -> Result<TimerId, AppError> {
        self.next += 1;
        let t = TimerId(self.next);
        self.timers.push((t, after_ms));
        Ok(t)
    }
    fn cancel_timer(&mut self, t: TimerId) {
        self.timers.retain(|(x, _)| *x != t);
    }
    fn store_get(&self, key: &str) -> Option<Vec<u8>> {
        self.store.get(key).cloned()
    }
    fn store_put(&mut self, key: &str, value: &[u8]) -> Result<(), AppError> {
        self.store.insert(key.to_owned(), value.to_vec());
        Ok(())
    }
    fn store_delete(&mut self, key: &str) {
        self.store.remove(key);
    }
    fn subscribe(&mut self, _key: &str) -> Result<SubId, AppError> {
        Err(AppError::new(Status::NotSupported, "subscribe"))
    }
    fn unsubscribe(&mut self, _sub: SubId) {}
    fn set(&mut self, _key: &str, _value: Value) -> Result<ReqId, AppError> {
        Err(AppError::new(Status::NotSupported, "set"))
    }
    fn invoke(&mut self, key: &str, action: &str, args: Value) -> Result<ReqId, AppError> {
        self.next += 1;
        let id = ReqId(self.next);
        self.invokes
            .push((id, key.to_owned(), action.to_owned(), args));
        Ok(id)
    }
    fn tcp_connect(&mut self, _a: &str, _p: u16, _t: u32) -> Result<ConnId, AppError> {
        Err(AppError::new(Status::NotSupported, "tcp"))
    }
    fn tcp_send(&mut self, _c: ConnId, d: &[u8]) -> Result<(), AppError> {
        self.sent.extend_from_slice(d);
        Ok(())
    }
    fn tcp_recv(&mut self, _c: ConnId, _m: u32, _t: u32) -> Result<Vec<u8>, AppError> {
        Ok(if self.recv.is_empty() {
            Vec::new()
        } else {
            self.recv.remove(0)
        })
    }
    fn tcp_close(&mut self, _c: ConnId) {}
    fn log(&mut self, _level: Level, _msg: &str) {}
}

/// What the fake target saw, and the errors it gives next.
#[derive(Default)]
struct Seen {
    connects: u32,
    secret: Option<String>,
    written: Vec<u64>,
    fail: Vec<TargetError>,
    connect_fail: Vec<TargetError>,
}

thread_local! {
    static SEEN: Rc<RefCell<Seen>> = Rc::default();
}

fn seen() -> Rc<RefCell<Seen>> {
    SEEN.with(|s| s.clone())
}

struct FakeTarget;

impl Target for FakeTarget {
    const KIND: &'static str = "fake";
    const VERSION: &'static str = "0";
    fn check(cfg: &Map) -> Result<(), String> {
        match cfg.keys().find(|k| *k != "url") {
            Some(k) => Err(format!("params.{k}: unknown")),
            None => Ok(()),
        }
    }
    fn connect(_net: &mut dyn Host, _cfg: &Map, secret: Option<&str>) -> Result<Self, TargetError> {
        let s = seen();
        let mut s = s.borrow_mut();
        s.connects += 1;
        s.secret = secret.map(str::to_owned);
        if !s.connect_fail.is_empty() {
            return Err(s.connect_fail.remove(0));
        }
        Ok(FakeTarget)
    }
    fn write(&mut self, _net: &mut dyn Host, rows: &[Row]) -> Result<(), TargetError> {
        let s = seen();
        let mut s = s.borrow_mut();
        if !s.fail.is_empty() {
            return Err(s.fail.remove(0));
        }
        s.written.extend(rows.iter().map(|r| r.seq));
        Ok(())
    }
    fn ping(&mut self, _net: &mut dyn Host) -> Result<(), TargetError> {
        Ok(())
    }
}

const SINK: &str = "wy/edge/sys/history/sinks/cloud";

fn config(extra: &[(&str, Value)]) -> Value {
    let mut m = Map::from([("sink".to_owned(), Value::from(SINK))]);
    for (k, v) in extra {
        m.insert((*k).to_owned(), v.clone());
    }
    Value::Map(m)
}

fn batch(seqs: &[u64], next: u64) -> Value {
    let rows = seqs
        .iter()
        .map(|s| {
            Value::Map(Map::from([
                ("seq".to_owned(), Value::UInt(*s)),
                ("key".to_owned(), Value::from("wy/edge/downstream/mock/p")),
                ("t".to_owned(), Value::UInt(*s * 10)),
                ("v".to_owned(), Value::Float(*s as f64)),
                ("q".to_owned(), Value::UInt(0)),
            ]))
        })
        .collect();
    Value::Map(Map::from([
        ("rows".to_owned(), Value::Array(rows)),
        ("next".to_owned(), Value::UInt(next)),
    ]))
}

/// Fire the last timer the app armed.
fn fire(app: &mut SyncApp<FakeTarget>, h: &mut Fake) -> u64 {
    let (t, ms) = h.timers.pop().expect("a timer");
    app.on_timer(h, t);
    ms
}

/// The last `next` request: its id and its `after`.
fn last_next(h: &Fake) -> (ReqId, Option<u64>) {
    let (id, key, action, args) = h.invokes.last().expect("a request").clone();
    assert_eq!((key.as_str(), action.as_str()), (SINK, "next"));
    let Value::Map(m) = args else { panic!() };
    let after = match m.get("after") {
        Some(Value::UInt(a)) => Some(*a),
        _ => None,
    };
    (id, after)
}

fn status(h: &Fake) -> &str {
    match h.values.get("status") {
        Some(Value::Str(s)) => s,
        _ => "",
    }
}

#[test]
fn params_are_checked() {
    let mut h = Fake::default();
    for (cfg, why) in [
        (Value::Null, "sink"),
        (
            Value::Map(Map::from([("sink".to_owned(), Value::from("wy/edge/sys"))])),
            "sink",
        ),
        (config(&[("batch", Value::UInt(0))]), "batch"),
        (config(&[("batch", Value::UInt(5001))]), "batch"),
        (config(&[("idle_s", Value::UInt(0))]), "idle_s"),
        (config(&[("oops", Value::UInt(1))]), "oops"),
    ] {
        let e = SyncApp::<FakeTarget>::start(&mut h, cfg)
            .err()
            .expect("refused");
        assert!(e.msg.contains(why), "{why}: {}", e.msg);
    }
    SyncApp::<FakeTarget>::start(&mut h, config(&[("url", Value::from("x"))])).unwrap();
}

#[test]
fn batches_are_written_then_confirmed() {
    let mut h = Fake::default();
    h.store.insert(SECRET.into(), b"pw".to_vec());
    let mut app =
        SyncApp::<FakeTarget>::start(&mut h, config(&[("batch", Value::UInt(2))])).unwrap();
    fire(&mut app, &mut h);
    assert_eq!(seen().borrow().secret.as_deref(), Some("pw"));
    // the first request carries no cursor: the sink starts from its own
    let (id, after) = last_next(&h);
    assert_eq!(after, None);
    let Value::Map(m) = &h.invokes[0].3 else {
        panic!()
    };
    assert_eq!(m.get("max"), Some(&Value::UInt(2)));
    app.on_reply(&mut h, id, Ok(batch(&[1, 2], 2)));
    assert_eq!(seen().borrow().written, [1, 2]);
    assert_eq!(h.values.get("rows_sent"), Some(&Value::UInt(2)));
    // the next request at once, confirming the batch written
    assert_eq!(fire(&mut app, &mut h), 1);
    let (id, after) = last_next(&h);
    assert_eq!(after, Some(2));
    // nothing new: wait idle_s, the cursor still moves
    app.on_reply(&mut h, id, Ok(batch(&[], 7)));
    assert_eq!(status(&h), "idle");
    assert_eq!(fire(&mut app, &mut h), DEFAULT_IDLE_S * 1000);
    assert_eq!(last_next(&h).1, Some(7));
    // a reply to an old request is ignored
    app.on_reply(&mut h, ReqId(999), Ok(batch(&[8], 8)));
    assert_eq!(seen().borrow().written, [1, 2]);
}

#[test]
fn failures_back_off_reconnect_or_stop() {
    let mut h = Fake::default();
    let mut app = SyncApp::<FakeTarget>::start(&mut h, config(&[])).unwrap();
    fire(&mut app, &mut h);
    // a write the target refuses for now: the same batch again, after a wait
    seen()
        .borrow_mut()
        .fail
        .push(TargetError::Retry("busy".into()));
    let (id, _) = last_next(&h);
    app.on_reply(&mut h, id, Ok(batch(&[1], 1)));
    assert_eq!(status(&h), "waiting");
    assert_eq!(h.values.get("error"), Some(&Value::from("busy")));
    assert_eq!(fire(&mut app, &mut h), FIRST_RETRY_MS);
    let (id, after) = last_next(&h);
    assert_eq!(after, None, "not confirmed: the sink sends it again");
    // a lost connection: connect again; the wait doubles
    seen()
        .borrow_mut()
        .fail
        .push(TargetError::Reconnect("reset".into()));
    app.on_reply(&mut h, id, Ok(batch(&[1], 1)));
    let connects = seen().borrow().connects;
    assert_eq!(fire(&mut app, &mut h), 2 * FIRST_RETRY_MS);
    assert_eq!(seen().borrow().connects, connects + 1);
    // the sink refuses (no key yet): back off
    let (id, _) = last_next(&h);
    app.on_reply(&mut h, id, Err(AppError::new(Status::PermissionDenied, "")));
    assert_eq!(status(&h), "waiting");
    fire(&mut app, &mut h);
    // fatal: stopped until the password changes
    seen()
        .borrow_mut()
        .fail
        .push(TargetError::Fatal("401".into()));
    let (id, _) = last_next(&h);
    app.on_reply(&mut h, id, Ok(batch(&[1], 1)));
    assert_eq!(status(&h), "failed");
    assert!(h.timers.is_empty(), "no retry after a fatal error");
    let who = Who::default();
    let args = Value::Map(Map::from([("password".to_owned(), Value::from("new"))]));
    app.on_invoke(&mut h, "", "set_password", args, &who)
        .unwrap();
    assert_eq!(h.store.get(SECRET).map(Vec::as_slice), Some(&b"new"[..]));
    fire(&mut app, &mut h);
    assert_eq!(seen().borrow().secret.as_deref(), Some("new"));
    let (id, _) = last_next(&h);
    app.on_reply(&mut h, id, Ok(batch(&[1], 1)));
    assert_eq!(seen().borrow().written, [1]);
}

#[test]
fn pause_survives_a_restart_and_resume_goes_on() {
    let mut h = Fake::default();
    let who = Who::default();
    let mut app = SyncApp::<FakeTarget>::start(&mut h, config(&[])).unwrap();
    app.on_invoke(&mut h, "", "pause", Value::Null, &who)
        .unwrap();
    assert_eq!(status(&h), "paused");
    assert!(h.timers.is_empty());
    let mut app = SyncApp::<FakeTarget>::start(&mut h, config(&[])).unwrap();
    assert_eq!(status(&h), "paused", "kept in the store");
    assert!(h.timers.is_empty());
    app.on_invoke(&mut h, "", "resume", Value::Null, &who)
        .unwrap();
    fire(&mut app, &mut h);
    assert_eq!(status(&h), "reading");
    // a connect that fails is a wait, then a new try
    seen()
        .borrow_mut()
        .connect_fail
        .push(TargetError::Retry("down".into()));
    let r = app
        .on_invoke(&mut h, "", "test_connection", Value::Null, &who)
        .unwrap();
    let Value::Map(m) = r else { panic!() };
    assert_eq!(m.get("success"), Some(&Value::Bool(false)));
    assert_eq!(m.get("message"), Some(&Value::from("down")));
}

#[test]
fn urls_and_queries() {
    use crate::http::{loopback, parse_url, query_value};
    assert_eq!(
        parse_url("https://eu.influx.cloud").unwrap(),
        (true, "eu.influx.cloud".into(), 443, String::new())
    );
    assert_eq!(
        parse_url("http://127.0.0.1:8086/base/").unwrap(),
        (false, "127.0.0.1".into(), 8086, "/base".into())
    );
    assert_eq!(parse_url("http://[::1]:8086").unwrap().1, "::1");
    for bad in [
        "ftp://x",
        "https://u:p@x",
        "https://x:99999",
        "https://x/a b",
    ] {
        assert!(parse_url(bad).is_err(), "{bad}");
    }
    assert_eq!(query_value("my org/1"), "my%20org%2F1");
    assert!(loopback("localhost") && loopback("127.0.0.1") && loopback("::1"));
    assert!(!loopback("10.0.0.1"));
}

fn get(h: &mut Fake) -> Result<crate::http::Response, TargetError> {
    let req = crate::http::Request {
        method: "GET",
        path: "/x",
        host: "h",
        headers: &[],
        body: b"",
    };
    crate::http::send(h, ConnId(1), &req, 100)
}

#[test]
fn http_bodies_and_bounds() {
    // chunked, split across reads, with a trailer; the bytes after it stay
    let mut h = Fake {
        recv: vec![
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nab".to_vec(),
            b"cd\r\n2;x=1\r\nef\r\n0\r\nX-T: 1\r\n\r\n".to_vec(),
        ],
        ..Fake::default()
    };
    let r = get(&mut h).unwrap();
    assert_eq!((r.status, r.body.as_slice()), (200, &b"abcdef"[..]));
    assert!(String::from_utf8_lossy(&h.sent).starts_with("GET /x HTTP/1.1\r\nHost: h\r\n"));
    // Content-Length, and 204 without one
    let mut h = Fake {
        recv: vec![
            b"HTTP/1.1 400 Bad\r\nContent-Length: 3\r\nConnection: close\r\n\r\nno!".to_vec(),
        ],
        ..Fake::default()
    };
    let r = get(&mut h).unwrap();
    assert_eq!((r.status, r.text(10).as_str(), r.close), (400, "no!", true));
    let mut h = Fake {
        recv: vec![b"HTTP/1.1 204 No Content\r\n\r\n".to_vec()],
        ..Fake::default()
    };
    assert_eq!(get(&mut h).unwrap().body, b"");
    // bounds: a huge chunk size, an endless size line, a long body, a bad chunk end
    for (bytes, why) in [
        (
            &b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nffffffffffffffff\r\n"[..],
            "too long",
        ),
        (
            &b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"[..],
            "chunk line",
        ),
        (
            &b"HTTP/1.1 200 OK\r\nContent-Length: 99999999\r\n\r\n"[..],
            "too long",
        ),
        (
            &b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nabc\r\n"[..],
            "chunk end",
        ),
    ] {
        let mut recv = vec![bytes.to_vec()];
        if why == "chunk line" {
            recv.push(vec![b'1'; 2000]);
        }
        let mut h = Fake {
            recv,
            ..Fake::default()
        };
        let e = get(&mut h).unwrap_err();
        assert!(e.message().contains(why), "{why}: {e}");
    }
    // no line breaks in a request
    let mut h = Fake::default();
    let req = crate::http::Request {
        method: "GET",
        path: "/x",
        host: "h",
        headers: &[("X", "a\r\nEvil: 1")],
        body: b"",
    };
    assert!(matches!(
        crate::http::send(&mut h, ConnId(1), &req, 100),
        Err(TargetError::Fatal(_))
    ));
    assert!(h.sent.is_empty());
}
