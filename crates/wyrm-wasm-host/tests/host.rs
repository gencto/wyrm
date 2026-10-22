//! Host limits, sandbox and hot reload on WAT test guests.

mod guests;

use std::time::{Duration, Instant};
use wyrm_wasm_host::{
    sha256_hex, DriverWorld, Error, FlowNode, Host, Limits, LinkDriver, NetPolicy, NodeWorld,
    PointDriver, PointWorld, Slot,
};

/// `~val` payload `{0: v, 1: good, 2: 1}` with a one-byte uint `v`.
fn sample(v: u8) -> Vec<u8> {
    assert!(v < 24);
    vec![0xa3, 0x00, v, 0x01, 0x00, 0x02, 0x01]
}

/// `[["out", sample(v)]]`.
fn emits(v: u8) -> Vec<u8> {
    let mut e = vec![0x81, 0x82, 0x63, b'o', b'u', b't'];
    e.extend(sample(v));
    e
}

fn node(host: &Host, bytes: &[u8], limits: Limits) -> FlowNode {
    let art = host.load::<NodeWorld>(bytes).expect("load");
    FlowNode::new(Slot::new(art), vec![0xf6], limits)
}

#[test]
fn node_computes_output_and_state() {
    let host = Host::new().unwrap();
    let bytes = guests::add(1);
    let art = host.load::<NodeWorld>(&bytes).unwrap();
    assert_eq!(art.sha256(), sha256_hex(&bytes));
    let mut n = FlowNode::new(Slot::new(art), vec![0xf6], Limits::default());
    n.start().unwrap();
    let (out, st) = n.process("in", &sample(5), &[]).unwrap();
    assert_eq!(out, emits(6));
    assert_eq!(st, vec![1]);
    let (out, st) = n.process("in", &sample(9), &st).unwrap();
    assert_eq!(out, emits(10));
    assert_eq!(st, vec![2]);
    assert!(n.fuel_used() > 0);
}

#[test]
fn fuel_limit_traps_and_instance_recovers() {
    let host = Host::new().unwrap();
    let limits = Limits {
        fuel: 100_000,
        time: Duration::from_secs(1),
        ..Limits::default()
    };
    let mut n = node(&host, &guests::spin(), limits);
    let t = Instant::now();
    assert_eq!(n.process("in", &sample(1), &[]), Err(Error::Fuel(100_000)));
    assert!(t.elapsed() < Duration::from_millis(900), "fuel, not time");
    // the next call runs on a fresh instance and traps the same way
    assert_eq!(n.process("in", &sample(1), &[]), Err(Error::Fuel(100_000)));

    // a well-behaved node stays usable after its own trap: swap in `add`
    // after a spin trap on the same runner
    n.slot()
        .swap(host.load::<NodeWorld>(&guests::add(2)).unwrap());
    assert_eq!(
        n.process("in", &sample(1), &[]).unwrap(),
        (emits(3), vec![1])
    );
}

#[test]
fn time_limit_interrupts() {
    let host = Host::new().unwrap();
    let limits = Limits {
        fuel: u64::MAX / 2,
        time: Duration::from_millis(50),
        ..Limits::default()
    };
    let mut n = node(&host, &guests::spin(), limits);
    let t = Instant::now();
    assert_eq!(
        n.process("in", &sample(1), &[]),
        Err(Error::Time(Duration::from_millis(50)))
    );
    assert!(t.elapsed() < Duration::from_secs(2));
}

#[test]
fn memory_limit_traps() {
    let host = Host::new().unwrap();
    let limits = Limits {
        memory_bytes: 1 << 20,
        ..Limits::default()
    };
    // 64 pages = 4 MiB above the 1 MiB limit
    let mut n = node(&host, &guests::grow(64), limits);
    assert_eq!(
        n.process("in", &sample(1), &[]),
        Err(Error::Memory(1 << 20))
    );
    // within the limit the guest runs and answers its own error
    let mut n = node(&host, &guests::grow(4), limits);
    assert_eq!(
        n.process("in", &sample(1), &[]),
        Err(Error::Guest("grown".into()))
    );
}

#[test]
fn hot_reload_swaps_behavior_and_keeps_state() {
    let host = Host::new().unwrap();
    let mut n = node(&host, &guests::add(1), Limits::default());
    let (out, st) = n.process("in", &sample(5), &[]).unwrap();
    assert_eq!(out, emits(6));
    let old = n
        .slot()
        .swap(host.load::<NodeWorld>(&guests::add(10)).unwrap());
    assert_eq!(old.sha256(), sha256_hex(&guests::add(1)));
    assert_eq!(n.slot().sha256(), sha256_hex(&guests::add(10)));
    // same runner, same state blob, new code
    let (out, st) = n.process("in", &sample(5), &st).unwrap();
    assert_eq!(out, emits(15));
    assert_eq!(st, vec![2]);
}

#[test]
fn no_filesystem_or_network_imports() {
    let host = Host::new().unwrap();
    for import in [
        "wasi:filesystem/types@0.2.0",
        "wasi:filesystem/preopens@0.2.0",
        "wasi:sockets/tcp@0.2.0",
        "wasi:sockets/udp@0.2.0",
        "wasi:http/outgoing-handler@0.2.0",
        "wyrm:any/thing",
    ] {
        match host.load::<NodeWorld>(&guests::importing(import)) {
            Err(Error::Denied(name)) => assert_eq!(name, import),
            Err(e) => panic!("{import}: {e}"),
            Ok(_) => panic!("{import}: loaded"),
        }
    }
}

#[test]
fn rejects_non_components_and_wrong_worlds() {
    let host = Host::new().unwrap();
    // a core module, not a component
    let core = wat::parse_str("(module)").unwrap();
    assert!(matches!(
        host.load::<NodeWorld>(&core),
        Err(Error::Invalid(_))
    ));
    assert!(matches!(
        host.load::<NodeWorld>(b"not wasm"),
        Err(Error::Invalid(_))
    ));
    // a point driver is not a flow node and vice versa
    assert!(matches!(
        host.load::<NodeWorld>(&guests::register()),
        Err(Error::Invalid(_))
    ));
    assert!(matches!(
        host.load::<PointWorld>(&guests::add(1)),
        Err(Error::Invalid(_))
    ));
}

#[test]
fn point_driver_reads_and_writes() {
    let host = Host::new().unwrap();
    let art = host.load::<PointWorld>(&guests::register()).unwrap();
    let mut d = PointDriver::new(Slot::new(art), vec![0xa0], Limits::default());
    d.start().unwrap();
    let read = |v: u8| vec![0xa3, 0x00, v, 0x01, 0x00, 0x02, 0x00];
    assert_eq!(d.read(&[0xa0]).unwrap(), read(7));
    d.write(&[0xa0], &[12]).unwrap();
    assert_eq!(d.read(&[0xa0]).unwrap(), read(12));
    assert_eq!(
        d.write(&[0xa0], &[0x18, 100]),
        Err(Error::Guest("range".into()))
    );
    assert_eq!(d.read(&[0xa0]).unwrap(), read(12));
}

// ---------- wyrm:link/driver: network (ADR 0012) ----------

/// An echo server on loopback; `None` replies (accepts and stays silent).
fn tcp_server(echo: bool) -> u16 {
    use std::io::{Read, Write};
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for s in l.incoming().flatten() {
            std::thread::spawn(move || {
                let mut s = s;
                let mut buf = [0u8; 64];
                while let Ok(n) = s.read(&mut buf) {
                    if n == 0 {
                        return;
                    }
                    if echo {
                        let _ = s.write_all(&buf[..n]);
                    }
                }
            });
        }
    });
    port
}

fn pinger(net: &str, port: u16, limits: Limits) -> LinkDriver {
    let host = Host::new().unwrap();
    let art = host.load::<DriverWorld>(&guests::tcp_ping()).unwrap();
    LinkDriver::new(
        Slot::new(art),
        port.to_be_bytes().to_vec(),
        limits,
        NetPolicy::parse(net).unwrap(),
    )
}

#[test]
fn driver_reaches_only_listed_addresses() {
    let port = tcp_server(true);
    let mut d = pinger(&format!("127.0.0.1/32:{port}"), port, Limits::LINK);
    assert_eq!(d.read(b"").unwrap(), b"ping");
    assert_eq!(d.read(b"").unwrap(), b"ping", "again on the same instance");
    for net in [
        format!("10.0.0.0/8:{port}"),         // not the address
        format!("127.0.0.1/32:{}", port ^ 1), // not the port
        format!("0.0.0.0/0:{port}"),          // loopback needs an explicit entry
        String::new(),                        // no network
    ] {
        let mut d = pinger(&net, port, Limits::LINK);
        match d.read(b"") {
            Err(Error::Guest(m)) => assert!(m.contains("not in the link's net list"), "{net}: {m}"),
            other => panic!("{net}: {other:?}"),
        }
    }
}

#[test]
fn driver_io_ends_with_the_call() {
    let port = tcp_server(false);
    let limits = Limits {
        time: Duration::from_millis(300),
        ..Limits::LINK
    };
    let mut d = pinger(&format!("127.0.0.1:{port}"), port, limits);
    for _ in 0..2 {
        let t = Instant::now();
        // the guest asks recv for 5 s; the host gives it what is left of 300 ms
        let r = d.read(b"");
        assert!(
            t.elapsed() < Duration::from_millis(1500),
            "{:?}",
            t.elapsed()
        );
        assert!(
            matches!(&r, Err(Error::Guest(m)) if m.contains("timeout") || m.contains("no time left"))
                || matches!(r, Err(Error::Time(_))),
            "{r:?}"
        );
    }
}

#[test]
fn driver_world_takes_point_components_and_refuses_other_imports() {
    let host = Host::new().unwrap();
    // a `point` component (no imports) runs as a driver too
    let art = host.load::<DriverWorld>(&guests::register()).unwrap();
    let mut d = LinkDriver::new(Slot::new(art), vec![], Limits::LINK, NetPolicy::default());
    assert_eq!(d.read(b"").unwrap(), vec![0xa3, 0, 7, 1, 0, 2, 0]);
    for import in [
        "wasi:sockets/tcp@0.2.0",
        "wyrm:link/tcp@9.9.9",
        "wyrm:any/thing",
    ] {
        match host.load::<DriverWorld>(&guests::importing(import)) {
            Err(Error::Denied(name)) => assert_eq!(name, import),
            Err(e) => panic!("{import}: {e}"),
            Ok(_) => panic!("{import}: loaded"),
        }
    }
    // and the flow and point worlds still refuse the tcp import
    assert!(matches!(
        host.load::<PointWorld>(&guests::tcp_ping()),
        Err(Error::Denied(_))
    ));
}

#[test]
fn net_policy() {
    let p = NetPolicy::parse("10.0.5.0/24:502, 192.168.1.20:1502\n[fd00::]/64:502 127.0.0.1:9")
        .unwrap();
    let ip = |s: &str| s.parse::<std::net::IpAddr>().unwrap();
    assert!(p.allows(ip("10.0.5.77"), 502));
    assert!(!p.allows(ip("10.0.6.1"), 502));
    assert!(!p.allows(ip("10.0.5.77"), 503));
    assert!(p.allows(ip("192.168.1.20"), 1502));
    assert!(!p.allows(ip("192.168.1.21"), 1502));
    assert!(p.allows(ip("fd00::1:2"), 502));
    assert!(p.allows(ip("127.0.0.1"), 9));
    assert!(p.allows(ip("::ffff:10.0.5.1"), 502), "v4-mapped is v4");
    let any = NetPolicy::parse("0.0.0.0/0:502, [::]/0:502").unwrap();
    assert!(any.allows(ip("8.8.8.8"), 502));
    for special in [
        "127.0.0.1",
        "169.254.1.1",
        "0.0.0.0",
        "224.0.0.1",
        "::1",
        "fe80::1",
        "::ffff:127.0.0.1",
    ] {
        assert!(!any.allows(ip(special), 502), "{special}");
    }
    for bad in [
        "10.0.0.1",
        "host.example:502",
        "10.0.0.0/33:502",
        "10.0.0.1:99999",
    ] {
        assert!(NetPolicy::parse(bad).is_err(), "{bad}");
    }
}
