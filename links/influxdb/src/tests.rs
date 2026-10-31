use super::*;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use wyrm_history_sync::testkit::TcpHost;

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
fn a_key_cannot_add_fields_or_tags() {
    let mut r = row(1, Value::Float(1.0));
    r.key = "wy/edge/p\n injected=1,x".into();
    r.site = "a=b c\\".into();
    let l = lines("m\nx", &[r]);
    assert_eq!(
        l,
        "m\\ x,site=a\\=b\\ c\\\\,key=wy/edge/p\\ \\ injected\\=1\\,x value=1.0,quality=0i 1700000000000001\n"
    );
    // one unescaped space between tags and fields, one before the time
    let unescaped = l
        .char_indices()
        .filter(|(i, c)| *c == ' ' && !l[..*i].ends_with('\\'))
        .count();
    assert_eq!(unescaped, 2, "{l}");
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

/// The whole app: a timer, `next` to the sink, the batch written to InfluxDB, then the next
/// request confirming it.
#[test]
fn the_app_moves_a_batch_from_the_sink_to_influxdb() {
    use wyrm_link_api::App;
    let (port, got, _) = server(vec![(204, false)]);
    let mut h = TcpHost::default();
    h.store.insert("secret".into(), b"tok".to_vec());
    let mut params = cfg(port);
    params.insert(
        "sink".into(),
        Value::from("wy/edge/sys/history/sinks/cloud"),
    );
    let mut app = InfluxSync::start(&mut h, Value::Map(params)).unwrap();
    let t = h.timers.pop().unwrap();
    app.on_timer(&mut h, t);
    let (id, key, action, _) = h.invokes.pop().unwrap();
    assert_eq!(
        (key.as_str(), action.as_str()),
        ("wy/edge/sys/history/sinks/cloud", "next")
    );
    let row = |seq: u64| {
        Value::Map(Map::from([
            ("seq".to_owned(), Value::UInt(seq)),
            ("key".to_owned(), Value::from("wy/edge/downstream/mock/p")),
            ("t".to_owned(), Value::UInt(1_000 + seq)),
            ("v".to_owned(), Value::Float(seq as f64)),
            ("q".to_owned(), Value::UInt(0)),
        ]))
    };
    let batch = Value::Map(Map::from([
        ("rows".to_owned(), Value::Array(vec![row(1), row(2)])),
        ("next".to_owned(), Value::UInt(2)),
    ]));
    app.on_reply(&mut h, id, Ok(batch));
    assert_eq!(h.values.get("rows_sent"), Some(&Value::UInt(2)));
    let t = h.timers.pop().unwrap();
    app.on_timer(&mut h, t);
    let (_, _, _, args) = h.invokes.pop().unwrap();
    let Value::Map(a) = args else { panic!() };
    assert_eq!(
        a.get("after"),
        Some(&Value::UInt(2)),
        "confirms the batch written"
    );
    let got = got.lock().unwrap();
    assert_eq!(got.len(), 1);
    assert!(got[0].head.contains("Authorization: Token tok"));
    assert_eq!(got[0].body.lines().count(), 2, "{}", got[0].body);
}
