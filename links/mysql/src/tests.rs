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
        ("ssl".to_owned(), Value::from("disable")),
    ])
}

fn row(key: &str, t: u64, v: Value) -> Row {
    Row {
        seq: 1,
        site: "edge".into(),
        key: key.into(),
        t,
        v,
        q: Quality::Good,
    }
}

#[test]
fn params_are_checked() {
    assert!(My::check(&cfg(3306)).is_ok());
    let with = |k: &str, v: Value| {
        let mut c = cfg(3306);
        c.insert(k.into(), v);
        My::check(&c).unwrap_err()
    };
    assert!(with("oops", Value::UInt(1)).contains("oops"));
    assert!(with("host", Value::from("db.example.com")).contains("in the clear"));
    assert!(with("table", Value::from("t`; DROP")).contains("table"));
    assert!(with("database", Value::from("a-b")).contains("database"));
    assert!(with("ssl", Value::from("prefer")).contains("ssl"));
}

#[test]
fn upsert_uses_hex_text_and_dedups() {
    let rows = [
        row("wy/edge/p'\\", 1, Value::Float(1.5)),
        row("wy/edge/q", 2, Value::Float(1.0)),
        row("wy/edge/q", 2, Value::Float(2.0)),
        row("wy/edge/s", 3, Value::from("a'b")),
        row(&"k".repeat(701), 4, Value::Float(1.0)),
        row("wy/edge/m", 5, Value::Map(Map::new())),
    ];
    let sql = upsert("`h`", &rows).unwrap();
    let hex = |s: &str| hex_text(s);
    assert!(sql.starts_with("INSERT INTO `h` (site, `key`, t, value, value_text, quality) VALUES "));
    assert!(sql.contains(&format!(
        "({}, {}, TIMESTAMP '1970-01-01 00:00:00' + INTERVAL 1 MICROSECOND, 1.5, NULL, 0)",
        hex("edge"),
        hex("wy/edge/p'\\")
    )));
    assert!(sql.contains(&hex("a'b")) && !sql.contains("a'b"), "{sql}");
    assert_eq!(sql.matches(&hex("wy/edge/q")).count(), 1, "the last q only");
    assert!(sql.contains("INTERVAL 2 MICROSECOND, 2.0"));
    assert!(
        !sql.contains("INTERVAL 4 ") && !sql.contains("INTERVAL 5 "),
        "{sql}"
    );
    assert_eq!(hex_text("é"), "CONVERT(X'C3A9' USING utf8mb4)");
}

/// How the fake server checks the login.
#[derive(Clone, Copy, PartialEq)]
enum Login {
    Native,
    Sha2Fast,
    Sha2Full,
    SwitchToNative,
}

fn packet(seq: u8, p: &[u8]) -> Vec<u8> {
    let mut out = (p.len() as u32).to_le_bytes()[..3].to_vec();
    out.push(seq);
    out.extend_from_slice(p);
    out
}

fn read_packet(s: &mut TcpStream) -> Option<(u8, Vec<u8>)> {
    let mut h = [0u8; 4];
    s.read_exact(&mut h).ok()?;
    let len = u32::from_le_bytes([h[0], h[1], h[2], 0]) as usize;
    let mut p = vec![0u8; len];
    s.read_exact(&mut p).ok()?;
    Some((h[3], p))
}

const NONCE: &[u8; 20] = b"abcdefghijklmnopqrst";
const NONCE2: &[u8; 20] = b"ABCDEFGHIJKLMNOPQRST";

/// The server's own check, from the stored hash only (as MySQL keeps it).
fn native_ok(password: &str, nonce: &[u8], answer: &[u8]) -> bool {
    let stored = Sha1::digest(Sha1::digest(password.as_bytes()));
    let mut h = Sha1::new();
    h.update(nonce);
    h.update(stored);
    let p1: Vec<u8> = answer
        .iter()
        .zip(h.finalize())
        .map(|(a, b)| a ^ b)
        .collect();
    Sha1::digest(&p1)[..] == stored[..]
}

fn sha2_ok(password: &str, nonce: &[u8], answer: &[u8]) -> bool {
    let stored = Sha256::digest(Sha256::digest(password.as_bytes()));
    let mut h = Sha256::new();
    h.update(stored);
    h.update(nonce);
    let p1: Vec<u8> = answer
        .iter()
        .zip(h.finalize())
        .map(|(a, b)| a ^ b)
        .collect();
    Sha256::digest(&p1)[..] == stored[..]
}

const OK: &[u8] = &[0, 0, 0, 2, 0, 0, 0];

fn err(code: u16) -> Vec<u8> {
    let mut e = vec![0xff];
    e.extend_from_slice(&code.to_le_bytes());
    e.extend_from_slice(b"#HY000no");
    e
}

/// A MySQL stand-in for one connection: greeting, the login of `how`, then each query answered
/// with the next code of `script` (0 = OK).
fn server(how: Login, script: Vec<u16>) -> (u16, Arc<Mutex<Vec<String>>>) {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    let got = Arc::new(Mutex::new(Vec::new()));
    let g = got.clone();
    std::thread::spawn(move || {
        let Ok((mut s, _)) = l.accept() else { return };
        let plugin: &[u8] = if how == Login::Native {
            b"mysql_native_password"
        } else {
            b"caching_sha2_password"
        };
        let caps: u32 = 0x200 | 0x8000 | 0x8_0000 | 0x8 | 0x2000;
        let mut gr = vec![10u8];
        gr.extend_from_slice(b"8.0.36\0");
        gr.extend_from_slice(&7u32.to_le_bytes());
        gr.extend_from_slice(&NONCE[..8]);
        gr.push(0);
        gr.extend_from_slice(&(caps as u16).to_le_bytes());
        gr.push(45);
        gr.extend_from_slice(&2u16.to_le_bytes());
        gr.extend_from_slice(&((caps >> 16) as u16).to_le_bytes());
        gr.push(21);
        gr.extend_from_slice(&[0u8; 10]);
        gr.extend_from_slice(&NONCE[8..]);
        gr.push(0);
        gr.extend_from_slice(plugin);
        gr.push(0);
        s.write_all(&packet(0, &gr)).unwrap();
        let Some((_, resp)) = read_packet(&mut s) else {
            return;
        };
        // caps 4, max 4, charset 1, 23 zeros, user NUL, len + answer, db NUL, plugin NUL
        let mut i = 32;
        let user_end = i + resp[i..].iter().position(|b| *b == 0).unwrap();
        let user = String::from_utf8_lossy(&resp[i..user_end]).into_owned();
        i = user_end + 1;
        let alen = resp[i] as usize;
        let answer = resp[i + 1..i + 1 + alen].to_vec();
        g.lock().unwrap().push(format!("login {user}"));
        let pw = "s3cret";
        let mut seq = 2;
        let ok = match how {
            Login::Native => native_ok(pw, NONCE, &answer),
            Login::Sha2Fast => {
                let ok = sha2_ok(pw, NONCE, &answer);
                s.write_all(&packet(seq, &[1, 3])).unwrap();
                seq += 1;
                ok
            }
            Login::Sha2Full => {
                s.write_all(&packet(seq, &[1, 4])).unwrap();
                // the client must stop: nothing more is read
                let _ = read_packet(&mut s);
                return;
            }
            Login::SwitchToNative => {
                let mut sw = vec![0xfe];
                sw.extend_from_slice(b"mysql_native_password\0");
                sw.extend_from_slice(NONCE2);
                sw.push(0);
                s.write_all(&packet(seq, &sw)).unwrap();
                let Some((_, a)) = read_packet(&mut s) else {
                    return;
                };
                seq += 2;
                native_ok(pw, NONCE2, &a)
            }
        };
        if !ok {
            s.write_all(&packet(seq, &err(1045))).unwrap();
            return;
        }
        s.write_all(&packet(seq, OK)).unwrap();
        let mut script = script.into_iter();
        while let Some((_, p)) = read_packet(&mut s) {
            match p.first() {
                Some(3) => g
                    .lock()
                    .unwrap()
                    .push(String::from_utf8_lossy(&p[1..]).into_owned()),
                Some(0x0e) => g.lock().unwrap().push("PING".into()),
                _ => return,
            }
            let code = script.next().unwrap_or(0);
            let answer = if code == 0 { OK.to_vec() } else { err(code) };
            s.write_all(&packet(1, &answer)).unwrap();
        }
    });
    (port, got)
}

#[test]
fn logs_in_every_way() {
    for how in [Login::Native, Login::Sha2Fast, Login::SwitchToNative] {
        let (port, got) = server(how, vec![]);
        let mut h = TcpHost::default();
        let mut my = My::connect(&mut h, &cfg(port), Some("s3cret")).unwrap();
        my.ping(&mut h).unwrap();
        assert_eq!(*got.lock().unwrap(), ["login wyrm", "PING"]);
    }
    // a wrong password: the server's ERR 1045 stops the link
    let (port, _) = server(Login::Native, vec![]);
    let mut h = TcpHost::default();
    let e = My::connect(&mut h, &cfg(port), Some("wrong"))
        .err()
        .unwrap();
    assert!(
        matches!(e, TargetError::Fatal(_)) && e.message().contains("1045"),
        "{e}"
    );
    // caching_sha2's full login wants the password itself: never without TLS
    let (port, _) = server(Login::Sha2Full, vec![]);
    let e = My::connect(&mut h, &cfg(port), Some("s3cret"))
        .err()
        .unwrap();
    assert!(
        matches!(e, TargetError::Fatal(_)) && e.message().contains("TLS"),
        "{e}"
    );
}

#[test]
fn writes_and_classifies_errors() {
    let (port, got) = server(Login::Native, vec![0, 0, 1213, 1146]);
    let mut h = TcpHost::default();
    let mut my = My::connect(&mut h, &cfg(port), Some("s3cret")).unwrap();
    my.prepare(&mut h).unwrap();
    my.write(&mut h, &[row("wy/edge/p", 1, Value::Float(1.0))])
        .unwrap();
    let e = my
        .write(&mut h, &[row("wy/edge/p", 2, Value::Float(2.0))])
        .unwrap_err();
    assert!(matches!(e, TargetError::Retry(_)), "deadlock: {e}");
    let e = my
        .write(&mut h, &[row("wy/edge/p", 3, Value::Float(3.0))])
        .unwrap_err();
    assert!(matches!(e, TargetError::Fatal(_)), "no table: {e}");
    let got = got.lock().unwrap();
    assert!(
        got[1].starts_with("CREATE TABLE IF NOT EXISTS `wyrm_history`"),
        "{}",
        got[1]
    );
    assert!(got[2].starts_with("INSERT INTO `wyrm_history`"));
}

#[test]
fn nothing_in_the_clear_passes_for_tls() {
    // a greeting that offers TLS, followed at once by a forged OK in the clear
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    std::thread::spawn(move || {
        let Ok((mut s, _)) = l.accept() else { return };
        let caps: u32 = 0x200 | 0x8000 | 0x8_0000 | 0x8 | 0x2000 | 0x800;
        let mut gr = vec![10u8];
        gr.extend_from_slice(b"8.0.36\0");
        gr.extend_from_slice(&7u32.to_le_bytes());
        gr.extend_from_slice(&NONCE[..8]);
        gr.push(0);
        gr.extend_from_slice(&(caps as u16).to_le_bytes());
        gr.push(45);
        gr.extend_from_slice(&2u16.to_le_bytes());
        gr.extend_from_slice(&((caps >> 16) as u16).to_le_bytes());
        gr.push(21);
        gr.extend_from_slice(&[0u8; 10]);
        gr.extend_from_slice(&NONCE[8..]);
        gr.push(0);
        gr.extend_from_slice(b"mysql_native_password\0");
        let mut out = packet(0, &gr);
        out.extend(packet(2, OK));
        s.write_all(&out).unwrap();
        let _ = read_packet(&mut s);
    });
    let mut c = cfg(port);
    c.insert("ssl".into(), Value::from("require"));
    let mut h = TcpHost::default();
    let e = My::connect(&mut h, &c, Some("s3cret")).err().unwrap();
    assert!(e.message().contains("before TLS"), "{e}");
}
