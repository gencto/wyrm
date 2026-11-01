use super::*;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use wyrm_core::Quality;
use wyrm_history_sync::testkit::TcpHost;

fn cfg(port: u16) -> Map {
    Map::from([
        ("host".to_owned(), Value::from("127.0.0.1")),
        ("port".to_owned(), Value::UInt(port.into())),
        ("database".to_owned(), Value::from("plant")),
        ("user".to_owned(), Value::from("wyrm")),
        ("sslmode".to_owned(), Value::from("disable")),
    ])
}

fn row(seq: u64, key: &str, t: u64, v: Value) -> Row {
    Row {
        seq,
        site: "edge".into(),
        key: key.into(),
        t,
        v,
        q: Quality::Good,
    }
}

#[test]
fn params_are_checked() {
    assert!(Pg::check(&cfg(5432)).is_ok());
    let with = |k: &str, v: Value| {
        let mut c = cfg(5432);
        c.insert(k.into(), v);
        Pg::check(&c).unwrap_err()
    };
    assert!(with("oops", Value::UInt(1)).contains("oops"));
    assert!(with("host", Value::from("db.example.com")).contains("in the clear"));
    assert!(with("sslmode", Value::from("prefer")).contains("sslmode"));
    assert!(with("port", Value::UInt(0)).contains("port"));
    for bad in ["a-b", "x.y.z", "1t", "t;drop", "\"t\""] {
        assert!(with("table", Value::from(bad)).contains("table"), "{bad}");
    }
    assert_eq!(table_ident("s1.t_2").unwrap(), "\"s1\".\"t_2\"");
    let mut c = cfg(5432);
    c.insert("host".into(), Value::from("db.example.com"));
    c.insert("sslmode".into(), Value::from("require"));
    assert!(Pg::check(&c).is_ok());
}

#[test]
fn upsert_escapes_and_dedups() {
    let rows = [
        row(1, "wy/edge/p'; DROP TABLE x; --", 10, Value::Float(1.5)),
        row(2, "wy/edge/q", 10, Value::Float(1.0)),
        row(3, "wy/edge/q", 10, Value::Float(2.0)),
        row(4, "wy/edge/b", 11, Value::Bool(true)),
        row(5, "wy/edge/s", 12, Value::from("it's\0ok")),
        row(6, "wy/edge/n", 13, Value::Null),
        row(7, "wy/edge/x", 14, Value::Float(f64::INFINITY)),
        row(8, "wy/edge/m", 15, Value::Array(vec![])),
    ];
    let sql = upsert("\"wyrm_history\"", &rows).unwrap();
    let ts = |t| format!("TIMESTAMPTZ 'epoch' + {t} * INTERVAL '1 microsecond'");
    assert!(sql.starts_with(
        "INSERT INTO \"wyrm_history\" (site, key, t, value, value_text, quality) VALUES "
    ));
    for part in [
        format!(
            "('edge', 'wy/edge/p''; DROP TABLE x; --', {}, 1.5, NULL, 0)",
            ts(10)
        ),
        format!("('edge', 'wy/edge/q', {}, 2.0, NULL, 0)", ts(10)),
        format!("('edge', 'wy/edge/b', {}, 1, 'true', 0)", ts(11)),
        format!("('edge', 'wy/edge/s', {}, NULL, 'it''sok', 0)", ts(12)),
        format!("('edge', 'wy/edge/n', {}, NULL, NULL, 0)", ts(13)),
    ] {
        assert!(sql.contains(&part), "{part}\nin {sql}");
    }
    assert!(
        !sql.contains(", 1.0, NULL"),
        "the earlier q at 10 is dropped: {sql}"
    );
    assert!(
        !sql.contains("wy/edge/x") && !sql.contains("wy/edge/m"),
        "{sql}"
    );
    assert!(sql.ends_with("ON CONFLICT (key, t) DO UPDATE SET site = EXCLUDED.site, value = EXCLUDED.value, value_text = EXCLUDED.value_text, quality = EXCLUDED.quality"));
    assert_eq!(upsert("t", &[row(1, "k", 1, Value::Bytes(vec![1]))]), None);
}

/// One backend message.
fn msg(kind: u8, body: &[u8]) -> Vec<u8> {
    frame(kind, body)
}

fn read_exact(s: &mut TcpStream, n: usize) -> Option<Vec<u8>> {
    let mut b = vec![0u8; n];
    s.read_exact(&mut b).ok()?;
    Some(b)
}

/// A frontend message (`kind` and body), or the startup (kind 0).
fn read_msg(s: &mut TcpStream, startup: bool) -> Option<(u8, Vec<u8>)> {
    let kind = if startup { 0 } else { read_exact(s, 1)?[0] };
    let l = read_exact(s, 4)?;
    let len = u32::from_be_bytes([l[0], l[1], l[2], l[3]]) as usize;
    Some((kind, read_exact(s, len - 4)?))
}

#[derive(Default, Debug)]
struct Seen {
    startup: Vec<u8>,
    password: String,
    queries: Vec<String>,
}

/// A PostgreSQL stand-in: cleartext password, `conforming` strings, then each query answered
/// with the next code of `script` (`""` = success).
fn server(conforming: bool, script: Vec<&'static str>) -> (u16, Arc<Mutex<Seen>>) {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    let seen = Arc::new(Mutex::new(Seen::default()));
    let s2 = seen.clone();
    std::thread::spawn(move || {
        let Ok((mut s, _)) = l.accept() else { return };
        let Some((_, startup)) = read_msg(&mut s, true) else {
            return;
        };
        s2.lock().unwrap().startup = startup;
        s.write_all(&msg(b'R', &3u32.to_be_bytes())).unwrap();
        let Some((b'p', pw)) = read_msg(&mut s, false) else {
            return;
        };
        s2.lock().unwrap().password = String::from_utf8_lossy(&pw).trim_end_matches('\0').into();
        let mut out = msg(b'R', &0u32.to_be_bytes());
        let v: &[u8] = if conforming { b"on" } else { b"off" };
        out.extend(msg(
            b'S',
            &[&b"standard_conforming_strings\0"[..], v, b"\0"].concat(),
        ));
        out.extend(msg(b'Z', b"I"));
        s.write_all(&out).unwrap();
        let mut script = script.into_iter();
        while let Some((kind, body)) = read_msg(&mut s, false) {
            if kind != b'Q' {
                break;
            }
            s2.lock()
                .unwrap()
                .queries
                .push(String::from_utf8_lossy(&body).trim_end_matches('\0').into());
            let code = script.next().unwrap_or("");
            let mut out = if code.is_empty() {
                msg(b'C', b"INSERT 0 1\0")
            } else {
                msg(b'E', format!("SERROR\0C{code}\0Mno\0\0").as_bytes())
            };
            out.extend(msg(b'Z', b"I"));
            s.write_all(&out).unwrap();
        }
    });
    (port, seen)
}

#[test]
fn talks_the_protocol_and_classifies_errors() {
    let (port, seen) = server(true, vec!["", "", "40001", "08006"]);
    let mut h = TcpHost::default();
    let mut pg = Pg::connect(&mut h, &cfg(port), Some("s3cret")).unwrap();
    pg.prepare(&mut h).unwrap();
    pg.write(&mut h, &[row(1, "wy/edge/p", 5, Value::Float(1.0))])
        .unwrap();
    let e = pg
        .write(&mut h, &[row(2, "wy/edge/p", 6, Value::Float(2.0))])
        .unwrap_err();
    assert!(matches!(e, TargetError::Retry(_)), "40001: {e}");
    let e = pg.ping(&mut h).unwrap_err();
    assert!(matches!(e, TargetError::Reconnect(_)), "08006: {e}");
    let s = seen.lock().unwrap();
    assert_eq!(s.password, "s3cret");
    let startup = String::from_utf8_lossy(&s.startup);
    assert!(
        startup.contains("user\0wyrm\0database\0plant\0"),
        "{startup:?}"
    );
    assert!(
        s.queries[0].starts_with("CREATE TABLE IF NOT EXISTS \"wyrm_history\""),
        "{:?}",
        s.queries[0]
    );
    assert!(s.queries[1].starts_with("INSERT INTO \"wyrm_history\""));
    assert_eq!(s.queries[3], "SELECT 1");
}

#[test]
fn refuses_unsafe_servers() {
    // backslashes in literals would mean something: refused
    let (port, _) = server(false, vec![]);
    let mut h = TcpHost::default();
    let e = Pg::connect(&mut h, &cfg(port), Some("pw")).err().unwrap();
    assert!(e.message().contains("standard_conforming_strings"), "{e}");
    // no password set: the server's question is fatal, not a retry loop
    let (port, _) = server(true, vec![]);
    let e = Pg::connect(&mut h, &cfg(port), None).err().unwrap();
    assert!(
        matches!(e, TargetError::Fatal(_)) && e.message().contains("Set Password"),
        "{e}"
    );
    // sslmode require and a server without TLS
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    std::thread::spawn(move || {
        if let Ok((mut s, _)) = l.accept() {
            let _ = read_exact(&mut s, 8);
            let _ = s.write_all(b"N");
            let _ = read_exact(&mut s, 1);
        }
    });
    let mut c = cfg(port);
    c.insert("sslmode".into(), Value::from("require"));
    let e = Pg::connect(&mut h, &c, Some("pw")).err().unwrap();
    assert!(
        matches!(e, TargetError::Fatal(_)) && e.message().contains("refuses TLS"),
        "{e}"
    );
}

/// Review HS-1: data errors refuse the rows; the rest keeps its class.
#[test]
fn data_errors_refuse_rows() {
    let class = |c: &str| {
        PgError {
            code: c.into(),
            message: "m".into(),
        }
        .class()
    };
    assert!(matches!(class("22001"), TargetError::Refused(_)));
    assert!(matches!(class("23502"), TargetError::Refused(_)));
    assert!(matches!(class("54000"), TargetError::Refused(_)));
    assert!(matches!(class("42P01"), TargetError::Fatal(_)));
    assert!(matches!(class("28P01"), TargetError::Fatal(_)));
    assert!(matches!(class("08006"), TargetError::Reconnect(_)));
}
