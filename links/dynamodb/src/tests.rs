use super::*;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use wyrm_core::Quality;
use wyrm_history_sync::testkit::TcpHost;

fn cfg(endpoint: &str) -> Map {
    Map::from([
        ("region".to_owned(), Value::from("eu-central-1")),
        ("table".to_owned(), Value::from("wyrm_history")),
        ("access_key_id".to_owned(), Value::from("AKIDEXAMPLE")),
        ("endpoint".to_owned(), Value::from(endpoint)),
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
    let mut c = cfg("http://127.0.0.1:8000");
    assert!(Dynamo::check(&c).is_ok());
    c.remove("endpoint");
    assert_eq!(
        parse(&c).unwrap().host,
        "dynamodb.eu-central-1.amazonaws.com",
        "the region's endpoint, over TLS"
    );
    let with = |k: &str, v: Value| {
        let mut c = cfg("http://127.0.0.1:8000");
        c.insert(k.into(), v);
        Dynamo::check(&c).unwrap_err()
    };
    assert!(with("oops", Value::UInt(1)).contains("oops"));
    assert!(with("endpoint", Value::from("http://10.1.1.1:8000")).contains("in the clear"));
    assert!(with("table", Value::from("a b")).contains("table"));
    assert!(with("region", Value::from("EU/1")).contains("region"));
    assert!(with("ttl_days", Value::Int(-1)).contains("ttl_days"));
    assert_eq!(
        parse(&{
            let mut c = cfg("http://127.0.0.1:8000");
            c.insert("ttl_days".into(), Value::UInt(2));
            c
        })
        .unwrap()
        .ttl_s,
        Some(172_800)
    );
}

#[test]
fn items_and_requests() {
    let mut rows = vec![
        row("wy/edge/a\"b", 1_000_000, Value::Float(1.5)),
        row("wy/edge/x", 2_000_000, Value::Float(1.0)),
        row("wy/edge/x", 2_000_000, Value::Float(2.0)),
        row("wy/edge/b", 3_000_000, Value::Bool(true)),
        row("wy/edge/s", 4_000_000, Value::from("line\nend")),
        row("wy/edge/n", 5_000_000, Value::Null),
        row("wy/edge/big", 6_000_000, Value::Float(1e200)),
        row("wy/edge/arr", 7_000_000, Value::Array(vec![])),
    ];
    let reqs = requests("t1", Some(60), &rows);
    assert_eq!(reqs.len(), 1);
    let r = &reqs[0];
    assert!(
        r.starts_with("{\"RequestItems\":{\"t1\":[{\"PutRequest\":{\"Item\":"),
        "{r}"
    );
    for part in [
        "{\"key\":{\"S\":\"wy/edge/a\\\"b\"},\"t\":{\"N\":\"1000000\"},\"site\":{\"S\":\"edge\"},\"value\":{\"N\":\"1.5\"},\"quality\":{\"N\":\"0\"},\"expiration\":{\"N\":\"61\"}}",
        "\"value\":{\"N\":\"2\"}",
        "\"value\":{\"BOOL\":true}",
        "\"value\":{\"S\":\"line\\nend\"}",
        "\"value\":{\"NULL\":true}",
    ] {
        assert!(r.contains(part), "{part}\nin {r}");
    }
    assert_eq!(
        r.matches("\"wy/edge/x\"").count(),
        1,
        "the last x at t=2s only"
    );
    assert!(!r.contains("big") && !r.contains("arr"), "{r}");
    // 25 puts per request
    rows = (0..60)
        .map(|i| row(&format!("wy/edge/p{i}"), 1, Value::UInt(i)))
        .collect();
    let reqs = requests("t1", None, &rows);
    assert_eq!(
        reqs.iter()
            .map(|r| r.matches("PutRequest").count())
            .collect::<Vec<_>>(),
        [25, 25, 10]
    );
    assert!(!reqs[0].contains("expiration"));
}

/// A DynamoDB stand-in: each request gets the next `(status, body)`.
fn server(script: Vec<(u16, &'static str)>) -> (u16, Arc<Mutex<Vec<String>>>) {
    let l = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    let got = Arc::new(Mutex::new(Vec::new()));
    let g = got.clone();
    std::thread::spawn(move || {
        let Ok((mut s, _)) = l.accept() else { return };
        let mut script = script.into_iter();
        loop {
            let mut buf = Vec::new();
            let mut b = [0u8; 8192];
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
            let len: usize = head
                .lines()
                .find_map(|l| l.strip_prefix("Content-Length: "))
                .and_then(|n| n.parse().ok())
                .unwrap_or(0);
            let mut body = buf[end + 4..].to_vec();
            while body.len() < len {
                let n = s.read(&mut b).unwrap();
                body.extend_from_slice(&b[..n]);
            }
            g.lock()
                .unwrap()
                .push(format!("{head}\n\n{}", String::from_utf8_lossy(&body)));
            let Some((status, answer)) = script.next() else {
                return;
            };
            let resp = format!(
                "HTTP/1.1 {status} X\r\nContent-Length: {}\r\n\r\n{answer}",
                answer.len()
            );
            s.write_all(resp.as_bytes()).unwrap();
        }
    });
    (port, got)
}

#[test]
fn signs_writes_and_classifies() {
    let (port, got) = server(vec![
        (200, "{\"UnprocessedItems\":{\"wyrm_history\":[{}]}}"),
        (200, "{\"UnprocessedItems\": {}}"),
        (400, "{\"__type\":\"com.amazonaws.dynamodb.v20120810#ThrottlingException\",\"message\":\"slow\"}"),
        (400, "{\"__type\":\"com.amazon.coral.service#UnrecognizedClientException\",\"message\":\"bad key\"}"),
        (400, "{\"__type\":\"com.amazon.coral.validate#ValidationException\",\"message\":\"Item size has exceeded the maximum allowed size\"}"),
        (200, "{\"Table\":{}}"),
    ]);
    let mut h = TcpHost::default();
    let mut d = Dynamo::connect(
        &mut h,
        &cfg(&format!("http://127.0.0.1:{port}")),
        Some("SECRET"),
    )
    .unwrap();
    // left unprocessed once: sent again in the same write
    d.write(&mut h, &[row("wy/edge/p", 1, Value::Float(1.0))])
        .unwrap();
    let e = d
        .write(&mut h, &[row("wy/edge/p", 2, Value::Float(2.0))])
        .unwrap_err();
    assert!(matches!(e, TargetError::Retry(_)), "throttled: {e}");
    let e = d
        .write(&mut h, &[row("wy/edge/p", 3, Value::Float(3.0))])
        .unwrap_err();
    assert!(matches!(e, TargetError::Fatal(_)), "bad key: {e}");
    // an item over the size limit refuses that row (review HS-1)
    let e = d
        .write(&mut h, &[row("wy/edge/p", 4, Value::Float(4.0))])
        .unwrap_err();
    assert!(matches!(e, TargetError::Refused(_)), "too large: {e}");
    d.ping(&mut h).unwrap();
    let got = got.lock().unwrap();
    assert_eq!(got.len(), 6);
    let first = &got[0];
    assert!(first.starts_with("POST / HTTP/1.1"), "{first}");
    assert!(
        first.contains(&format!("Host: 127.0.0.1:{port}")),
        "{first}"
    );
    assert!(first.contains("X-Amz-Target: DynamoDB_20120810.BatchWriteItem"));
    assert!(
        first.contains("Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/")
            && first.contains("/eu-central-1/dynamodb/aws4_request, SignedHeaders=content-type;host;x-amz-date;x-amz-target, Signature="),
        "{first}"
    );
    assert!(!first.contains("SECRET"), "the secret never leaves");
    assert_eq!(
        got[0].split("\n\n").nth(1),
        got[1].split("\n\n").nth(1),
        "the same request again"
    );
    assert!(got[5].contains("DescribeTable"));
}

#[test]
fn needs_the_secret() {
    let mut h = TcpHost::default();
    let e = Dynamo::connect(&mut h, &cfg("http://127.0.0.1:1"), None)
        .err()
        .unwrap();
    assert!(
        matches!(e, TargetError::Fatal(_)) && e.message().contains("Set Password"),
        "{e}"
    );
}
