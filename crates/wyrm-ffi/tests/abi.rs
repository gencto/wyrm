//! The C ABI end to end through the extern functions, against the
//! in-process mock (feature `test-harness`).

use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::time::{Duration, Instant};
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::{NodeMeta, Value};
use wyrm_ffi::*;

const ROOT: &str = "wy/test/down/mock";

struct H(*mut WyrmHandle);

impl Drop for H {
    fn drop(&mut self) {
        unsafe { wyrm_free(self.0) }
    }
}

fn open() -> H {
    let mut err = std::ptr::null_mut();
    let h = unsafe { wyrm_open_test_mock(6, 20.0, &mut err) };
    assert!(
        !h.is_null(),
        "open: {}",
        unsafe { CStr::from_ptr(err) }.to_string_lossy()
    );
    H(h)
}

fn c(s: &str) -> CString {
    CString::new(s).unwrap()
}

fn get<'a>(v: &'a Value, k: &str) -> &'a Value {
    match v {
        Value::Map(m) => m.get(k).unwrap_or(&Value::Null),
        _ => &Value::Null,
    }
}

/// Next frame for request `id` (frames of other ids are skipped).
fn next_for(h: &H, id: u64) -> Value {
    let end = Instant::now() + Duration::from_secs(10);
    while Instant::now() < end {
        let mut p = std::ptr::null_mut();
        let mut n = 0usize;
        let r = unsafe { wyrm_next_event(h.0, 200, &mut p, &mut n) };
        assert!(r >= 0, "next_event: {r}");
        if r == WYRM_EVENT {
            let v: Value = from_slice(unsafe { std::slice::from_raw_parts(p, n) }).unwrap();
            unsafe { wyrm_buf_free(p, n) };
            if get(&v, "id") == &Value::UInt(id) {
                return v;
            }
        }
    }
    panic!("no frame for {id}");
}

fn is_ok(v: &Value) -> bool {
    get(v, "ok") == &Value::Bool(true)
}

#[test]
fn meta_children_list_subscribe_set_invoke() {
    let h = open();
    unsafe {
        // meta
        assert_eq!(
            wyrm_meta(h.0, 1, c(&format!("{ROOT}/g0/p0")).as_ptr()),
            WYRM_OK
        );
        let f = next_for(&h, 1);
        assert!(is_ok(&f), "{f:?}");
        let Value::Bytes(b) = get(&f, "result") else {
            panic!("{f:?}")
        };
        let m: NodeMeta = from_slice(b).unwrap();
        assert_eq!(m.ty, Some(wyrm_core::TypeCode::Number));

        // children
        assert_eq!(wyrm_children(h.0, 2, c(ROOT).as_ptr()), WYRM_OK);
        let f = next_for(&h, 2);
        let Value::Array(kids) = get(&f, "result") else {
            panic!("{f:?}")
        };
        let names: Vec<_> = kids.iter().map(|k| get(k, "name").clone()).collect();
        assert_eq!(names, vec![Value::from("g0"), Value::from("g1")]);

        // list: ok, then refreshed; a second list on the same id is refused
        assert_eq!(wyrm_list(h.0, 3, c(ROOT).as_ptr()), WYRM_OK);
        assert_eq!(wyrm_list(h.0, 3, c(ROOT).as_ptr()), WYRM_ERR_DUPLICATE);
        assert!(is_ok(&next_for(&h, 3)));
        let f = next_for(&h, 3);
        assert_eq!(get(get(&f, "event"), "type"), &Value::from("refreshed"));
        assert_eq!(wyrm_unsubscribe(h.0, 4, 3), WYRM_OK);
        assert!(is_ok(&next_for(&h, 4)));
        assert_eq!(wyrm_unsubscribe(h.0, 5, 3), WYRM_OK);
        assert!(!is_ok(&next_for(&h, 5)));

        // set, then subscribe sees the value
        let v = to_vec(&Value::Float(42.5)).unwrap();
        let key = c(&format!("{ROOT}/g1/p1"));
        assert_eq!(wyrm_set(h.0, 6, key.as_ptr(), v.as_ptr(), v.len()), WYRM_OK);
        let f = next_for(&h, 6);
        assert!(is_ok(&f), "{f:?}");
        assert_eq!(wyrm_subscribe(h.0, 7, key.as_ptr()), WYRM_OK);
        assert!(is_ok(&next_for(&h, 7)));
        loop {
            let f = next_for(&h, 7);
            let ev = get(&f, "event");
            if get(ev, "type") == &Value::from("sample") && get(ev, "v") == &Value::Float(42.5) {
                assert_eq!(get(ev, "q"), &Value::from("good"));
                break;
            }
        }

        // invoke count {n: 3}: value 0, value 1, ok 2
        let args = to_vec(&Value::Map(BTreeMap::from([("n".into(), Value::UInt(3))]))).unwrap();
        let act = c("count");
        assert_eq!(
            wyrm_invoke(
                h.0,
                8,
                c(ROOT).as_ptr(),
                act.as_ptr(),
                args.as_ptr(),
                args.len()
            ),
            WYRM_OK
        );
        let a = next_for(&h, 8);
        let b = next_for(&h, 8);
        let last = next_for(&h, 8);
        assert_eq!(get(get(&a, "event"), "v"), &Value::UInt(0));
        assert_eq!(get(get(&b, "event"), "v"), &Value::UInt(1));
        assert!(is_ok(&last));
        assert_eq!(get(&last, "result"), &Value::UInt(2));

        // errors come as frames with a spec-04 status
        let bad = to_vec(&Value::from("text")).unwrap();
        assert_eq!(
            wyrm_set(h.0, 9, key.as_ptr(), bad.as_ptr(), bad.len()),
            WYRM_OK
        );
        let f = next_for(&h, 9);
        assert!(!is_ok(&f));
        assert!(matches!(get(get(&f, "error"), "status"), Value::UInt(s) if *s >= 0x20));
    }
}

#[test]
fn bad_arguments_and_shutdown() {
    let h = open();
    unsafe {
        assert_eq!(wyrm_meta(h.0, 1, std::ptr::null()), WYRM_ERR_ARG);
        assert_eq!(
            wyrm_meta(std::ptr::null(), 1, c(ROOT).as_ptr()),
            WYRM_ERR_ARG
        );
        let junk = [0xffu8];
        assert_eq!(
            wyrm_set(h.0, 2, c(ROOT).as_ptr(), junk.as_ptr(), junk.len()),
            WYRM_ERR_ARG
        );
        assert!(!CStr::from_ptr(wyrm_version()).to_bytes().is_empty());

        // A blocked poller wakes with CLOSED on shutdown.
        let raw = h.0 as usize;
        let poller = std::thread::spawn(move || {
            let mut p = std::ptr::null_mut();
            let mut n = 0;
            loop {
                let r = wyrm_next_event(raw as *const WyrmHandle, 5_000, &mut p, &mut n);
                if r == WYRM_EVENT {
                    wyrm_buf_free(p, n);
                    continue;
                }
                return r;
            }
        });
        assert_eq!(
            wyrm_subscribe(h.0, 3, c(&format!("{ROOT}/**")).as_ptr()),
            WYRM_OK
        );
        std::thread::sleep(Duration::from_millis(300));
        let t = Instant::now();
        assert_eq!(wyrm_shutdown(h.0), WYRM_OK);
        assert_eq!(poller.join().unwrap(), WYRM_ERR_CLOSED);
        assert!(t.elapsed() < Duration::from_secs(5));
        assert_eq!(wyrm_meta(h.0, 4, c(ROOT).as_ptr()), WYRM_ERR_CLOSED);
        assert_eq!(wyrm_shutdown(h.0), WYRM_OK);
    }
}

#[test]
fn open_failure_reports_an_error() {
    let mut err = std::ptr::null_mut();
    let h = unsafe {
        wyrm_open(
            c("bogus").as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            &mut err,
        )
    };
    assert!(h.is_null());
    assert!(!err.is_null());
    unsafe { wyrm_string_free(err) };
    let mut err = std::ptr::null_mut();
    let h = unsafe {
        wyrm_open(
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            &mut err,
        )
    };
    assert!(h.is_null());
    unsafe { wyrm_string_free(err) };
}

/// The production entry point: a client session over TCP to a router that
/// serves the mock, with ptoks signed from the seed.
#[test]
fn open_over_tcp_with_a_seed() {
    use wyrm_link_sdk::harness::{isolated_config, SITE, TEST_KEY_SEED};
    let port = std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port();
    let rt = tokio::runtime::Runtime::new().unwrap();
    let (_session, link) = rt.block_on(async {
        let mut zc = isolated_config();
        zc.insert_json5("mode", r#""router""#).unwrap();
        zc.insert_json5("listen/endpoints", &format!(r#"["tcp/127.0.0.1:{port}"]"#))
            .unwrap();
        let session = zenoh::open(zc).await.unwrap();
        let mut lc = wyrm_link_sdk::LinkConfig::new(SITE, "mock");
        lc.admin_keys = vec![ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED).verifying_key()];
        lc.answer_val = true;
        let mock = wyrm_link_mock::MockConfig {
            points: 4,
            rate_hz: 20.0,
            depth: 1,
            fanout: 2,
            writable: true,
        };
        let link = wyrm_link_sdk::spawn::<wyrm_link_mock::Mock>(session.clone(), lc, mock)
            .await
            .unwrap();
        (session, link)
    });

    let mut err = std::ptr::null_mut();
    let ep = c(&format!("tcp/127.0.0.1:{port}"));
    let site = c(SITE);
    let raw = unsafe { wyrm_open(ep.as_ptr(), TEST_KEY_SEED.as_ptr(), site.as_ptr(), &mut err) };
    assert!(
        !raw.is_null(),
        "open: {}",
        unsafe { CStr::from_ptr(err) }.to_string_lossy()
    );
    let h = H(raw);
    unsafe {
        // set needs a ptok from the seed
        let key = c(&format!("{ROOT}/g1/p1"));
        let v = to_vec(&Value::Float(7.5)).unwrap();
        assert_eq!(wyrm_set(h.0, 1, key.as_ptr(), v.as_ptr(), v.len()), WYRM_OK);
        let f = next_for(&h, 1);
        assert!(is_ok(&f), "{f:?}");

        let args = to_vec(&Value::Map(BTreeMap::from([("n".into(), Value::UInt(2))]))).unwrap();
        let act = c("count");
        assert_eq!(
            wyrm_invoke(
                h.0,
                2,
                c(ROOT).as_ptr(),
                act.as_ptr(),
                args.as_ptr(),
                args.len()
            ),
            WYRM_OK
        );
        assert_eq!(get(get(&next_for(&h, 2), "event"), "v"), &Value::UInt(0));
        assert_eq!(get(&next_for(&h, 2), "result"), &Value::UInt(1));

        assert_eq!(
            wyrm_subscribe(h.0, 3, c(&format!("{ROOT}/**")).as_ptr()),
            WYRM_OK
        );
        assert!(is_ok(&next_for(&h, 3)));
        for _ in 0..4 {
            let f = next_for(&h, 3);
            assert_eq!(get(get(&f, "event"), "type"), &Value::from("sample"));
        }
    }
    drop(h);
    rt.block_on(link.stop());
}
