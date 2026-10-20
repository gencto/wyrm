//! C ABI over `wyrm-client` for Dart (`dart/wyrm_ffi`) and C. Header:
//! `include/wyrm.h`.
//!
//! # Model
//! * [`wyrm_open`] connects a Zenoh client session to an endpoint and
//!   returns a handle. Each handle owns its own tokio runtime.
//! * Requests (`wyrm_meta`, `wyrm_children`, `wyrm_list`, `wyrm_subscribe`,
//!   `wyrm_set`, `wyrm_invoke`, `wyrm_unsubscribe`) carry a caller-chosen
//!   request id and return at once. Their results come as events.
//! * [`wyrm_next_event`] blocks up to a timeout and hands out one event: a
//!   canonical CBOR map in the frame format of the user gateway WebSocket
//!   (`crates/wyrm-gateway/src/ws.rs`): `{id, ok: true, result?}`,
//!   `{id, ok: false, error: {status, message}}` or `{id, event: {type, …}}`.
//!   So one client implementation serves both the gateway and this library.
//! * Values cross the boundary as canonical CBOR (`wyrm_core::Value`).
//!
//! # Ownership
//! * A handle lives from `wyrm_open*` to [`wyrm_free`]. Call
//!   [`wyrm_shutdown`] first: it stops every request and makes every
//!   blocked or later [`wyrm_next_event`] return [`WYRM_ERR_CLOSED`]. Call
//!   [`wyrm_free`] only when no other thread uses the handle any more.
//! * An event buffer from [`wyrm_next_event`] belongs to the caller; free
//!   it with [`wyrm_buf_free`] (same pointer and length).
//! * An error string from `wyrm_open*` belongs to the caller; free it with
//!   [`wyrm_string_free`].
//! * Input pointers are borrowed for the duration of the call only.
//!
//! No panic crosses the boundary: every entry point catches unwinds and
//! returns [`WYRM_ERR_PANIC`] (or null).

use std::collections::{BTreeMap, HashMap};
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::runtime::Runtime;
use tokio::sync::{mpsc, Notify};
use tokio::task::JoinHandle;
use wyrm_client::endpoint::{client_config, is_tls, plaintext_off_loopback, TlsFiles};
use wyrm_client::{Child, ClientError, ListEvent, ValEvent, WyrmClient};
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::{NodeMeta, Status, Value};

/// Success (requests), or "no event before the timeout" (`wyrm_next_event`).
pub const WYRM_OK: i32 = 0;
/// `wyrm_next_event`: one event was written to the out parameters.
pub const WYRM_EVENT: i32 = 1;
/// A null or malformed argument (bad UTF-8, bad CBOR).
pub const WYRM_ERR_ARG: i32 = -1;
/// The handle is shut down.
pub const WYRM_ERR_CLOSED: i32 = -2;
/// A panic was caught; the handle may be inconsistent.
pub const WYRM_ERR_PANIC: i32 = -3;
/// A stream with this request id is open.
pub const WYRM_ERR_DUPLICATE: i32 = -4;

/// Events waiting for `wyrm_next_event`. Samples beyond this are dropped
/// (`~val` is Data + Drop); other events wait for room.
const QUEUE: usize = 4096;

/// An open session. Opaque to C.
pub struct WyrmHandle {
    rt: Runtime,
    inner: Arc<Inner>,
}

struct Inner {
    client: WyrmClient,
    tx: mpsc::Sender<Vec<u8>>,
    rx: tokio::sync::Mutex<mpsc::Receiver<Vec<u8>>>,
    streams: Mutex<HashMap<u64, JoinHandle<()>>>,
    closed: AtomicBool,
    wake: Notify,
    #[cfg(feature = "test-harness")]
    link: Mutex<Option<wyrm_link_sdk::LinkHandle<wyrm_link_mock::Mock>>>,
}

// ---------- boundary helpers ----------

fn guard(f: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(WYRM_ERR_PANIC)
}

/// # Safety
/// `p` is null or a NUL-terminated string valid for this call.
unsafe fn text<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok()
}

/// # Safety
/// `p` is null (then `len` must be 0) or valid for `len` bytes.
unsafe fn bytes<'a>(p: *const u8, len: usize) -> Option<&'a [u8]> {
    if p.is_null() {
        return (len == 0).then_some(&[]);
    }
    Some(std::slice::from_raw_parts(p, len))
}

/// # Safety
/// `h` is null or a live handle from `wyrm_open*`.
unsafe fn handle<'a>(h: *const WyrmHandle) -> Option<&'a WyrmHandle> {
    h.as_ref()
}

/// # Safety
/// `err` is null or a writable `char*` slot.
unsafe fn set_err(err: *mut *mut c_char, msg: &str) {
    if !err.is_null() {
        let s = CString::new(msg.replace('\0', " ")).unwrap_or_default();
        *err = s.into_raw();
    }
}

fn runtime() -> std::io::Result<Runtime> {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("wyrm-ffi")
        .enable_all()
        .build()
}

fn new_handle(rt: Runtime, client: WyrmClient) -> WyrmHandle {
    let (tx, rx) = mpsc::channel(QUEUE);
    WyrmHandle {
        rt,
        inner: Arc::new(Inner {
            client,
            tx,
            rx: tokio::sync::Mutex::new(rx),
            streams: Mutex::new(HashMap::new()),
            closed: AtomicBool::new(false),
            wake: Notify::new(),
            #[cfg(feature = "test-harness")]
            link: Mutex::new(None),
        }),
    }
}

// ---------- open / close ----------

/// Open a Zenoh client session to `endpoint`: plaintext (`tcp/127.0.0.1:7447`)
/// on loopback only; use [`wyrm_open_tls`] for any other host.
///
/// `seed` (32 bytes, may be null) is an Ed25519 key whose public half the
/// broker trusts (`admin_keys`); with it every request carries a `ptok`
/// for `site` (`wy/<site>/**`, `config`, 60 s). Without it, links refuse
/// `set` and `invoke`. Returns null on failure and, if `err` is not null,
/// a message to free with [`wyrm_string_free`].
///
/// # Safety
/// `endpoint` and `site` are NUL-terminated strings (`site` may be null
/// when `seed` is null); `seed` is null or points to 32 bytes; `err` is
/// null or a writable slot.
#[no_mangle]
pub unsafe extern "C" fn wyrm_open(
    endpoint: *const c_char,
    seed: *const u8,
    site: *const c_char,
    err: *mut *mut c_char,
) -> *mut WyrmHandle {
    open_handle(err, "wyrm_open", || {
        let endpoint = text(endpoint).ok_or("endpoint: UTF-8 string required")?;
        if is_tls(endpoint) {
            return Err(format!("{endpoint}: use wyrm_open_tls"));
        }
        open_session(endpoint, None, signer(seed, site)?)
    })
}

/// Like [`wyrm_open`], over mTLS (`tls/<host>:<port>` or `quic/…`): `ca` is
/// the broker CA (PEM file), `cert` and `key` a client certificate it
/// issued and its private key (PEM files).
///
/// # Safety
/// As [`wyrm_open`]; `ca`, `cert` and `key` are NUL-terminated paths.
#[no_mangle]
pub unsafe extern "C" fn wyrm_open_tls(
    endpoint: *const c_char,
    ca: *const c_char,
    cert: *const c_char,
    key: *const c_char,
    seed: *const u8,
    site: *const c_char,
    err: *mut *mut c_char,
) -> *mut WyrmHandle {
    open_handle(err, "wyrm_open_tls", || {
        let endpoint = text(endpoint).ok_or("endpoint: UTF-8 string required")?;
        if !is_tls(endpoint) {
            return Err(format!("{endpoint}: not a tls/ or quic/ endpoint"));
        }
        let path = |p: *const c_char, what: &str| {
            text(p)
                .map(std::path::PathBuf::from)
                .ok_or_else(|| format!("{what}: UTF-8 path required"))
        };
        let tls = TlsFiles {
            ca: path(ca, "ca")?,
            cert: path(cert, "cert")?,
            key: path(key, "key")?,
        };
        open_session(endpoint, Some(&tls), signer(seed, site)?)
    })
}

type Signer = Option<(ed25519_dalek::SigningKey, String)>;

/// # Safety
/// `seed` is null or points to 32 bytes; `site` is null or NUL-terminated.
unsafe fn signer(seed: *const u8, site: *const c_char) -> Result<Signer, String> {
    if seed.is_null() {
        return Ok(None);
    }
    let s: [u8; 32] = std::slice::from_raw_parts(seed, 32)
        .try_into()
        .map_err(|_| "seed: 32 bytes")?;
    let site = text(site).ok_or("site: required with a seed")?;
    Ok(Some((
        ed25519_dalek::SigningKey::from_bytes(&s),
        site.to_owned(),
    )))
}

/// Principle 6: plaintext only on loopback, `tls/`/`quic/` with mTLS.
fn open_session(endpoint: &str, tls: Option<&TlsFiles>, key: Signer) -> Result<WyrmHandle, String> {
    if plaintext_off_loopback(endpoint) {
        return Err(format!(
            "{endpoint}: plaintext off loopback; use a tls/ endpoint (wyrm_open_tls)"
        ));
    }
    let zc = client_config(endpoint, tls)?;
    let rt = runtime().map_err(|e| format!("runtime: {e}"))?;
    let session = rt
        .block_on(async { zenoh::open(zc).await })
        .map_err(|e| format!("open {endpoint}: {e}"))?;
    let mut client = WyrmClient::new(session);
    if let Some((k, site)) = key {
        client = client.with_tokens(Arc::new(wyrm_client::SigningTokens::new(k, site)));
    }
    Ok(new_handle(rt, client))
}

/// Run `f` without letting a panic cross the boundary.
///
/// # Safety
/// `err` is null or a writable slot.
unsafe fn open_handle(
    err: *mut *mut c_char,
    name: &str,
    f: impl FnOnce() -> Result<WyrmHandle, String>,
) -> *mut WyrmHandle {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(h)) => Box::into_raw(Box::new(h)),
        Ok(Err(e)) => {
            set_err(err, &e);
            std::ptr::null_mut()
        }
        Err(_) => {
            set_err(err, &format!("panic in {name}"));
            std::ptr::null_mut()
        }
    }
}

/// Test only (feature `test-harness`): an isolated in-process Zenoh peer
/// with the mock link on `wy/test/down/mock` (`points` points at `rate_hz`,
/// depth 1, fanout 2, writable) that trusts the harness test key, and a
/// client that signs with that key.
///
/// # Safety
/// `err` is null or a writable slot.
#[cfg(feature = "test-harness")]
#[no_mangle]
pub unsafe extern "C" fn wyrm_open_test_mock(
    points: u32,
    rate_hz: f64,
    err: *mut *mut c_char,
) -> *mut WyrmHandle {
    use wyrm_link_sdk::harness::{isolated_config, SITE, TEST_KEY_SEED};
    let r = catch_unwind(AssertUnwindSafe(|| -> Result<WyrmHandle, String> {
        let rt = runtime().map_err(|e| format!("runtime: {e}"))?;
        let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
        let (client, link) = rt.block_on(async {
            let session = zenoh::open(isolated_config())
                .await
                .map_err(|e| e.to_string())?;
            let mut lc = wyrm_link_sdk::LinkConfig::new(SITE, "mock");
            lc.admin_keys = vec![key.verifying_key()];
            lc.answer_val = true;
            let mock = wyrm_link_mock::MockConfig {
                points: points as usize,
                rate_hz,
                depth: 1,
                fanout: 2,
                writable: true,
            };
            let link = wyrm_link_sdk::spawn::<wyrm_link_mock::Mock>(session.clone(), lc, mock)
                .await
                .map_err(|e| e.to_string())?;
            let client = WyrmClient::new(session)
                .with_tokens(Arc::new(wyrm_client::SigningTokens::new(key, SITE)));
            Ok::<_, String>((client, link))
        })?;
        let h = new_handle(rt, client);
        *h.inner.link.lock().unwrap_or_else(|p| p.into_inner()) = Some(link);
        Ok(h)
    }));
    match r {
        Ok(Ok(h)) => Box::into_raw(Box::new(h)),
        Ok(Err(e)) => {
            set_err(err, &e);
            std::ptr::null_mut()
        }
        Err(_) => {
            set_err(err, "panic in wyrm_open_test_mock");
            std::ptr::null_mut()
        }
    }
}

/// Stop every request and stream, close the Zenoh session, and wake every
/// [`wyrm_next_event`] with [`WYRM_ERR_CLOSED`]. Idempotent.
///
/// # Safety
/// `h` is null or a live handle.
#[no_mangle]
pub unsafe extern "C" fn wyrm_shutdown(h: *const WyrmHandle) -> i32 {
    guard(|| {
        let Some(h) = handle(h) else {
            return WYRM_ERR_ARG;
        };
        if h.inner.closed.swap(true, Ordering::SeqCst) {
            return WYRM_OK;
        }
        h.inner.wake.notify_waiters();
        let streams: Vec<_> = h
            .inner
            .streams
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .drain()
            .collect();
        for (_, t) in streams {
            t.abort();
        }
        #[cfg(feature = "test-harness")]
        let link = h
            .inner
            .link
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .take();
        let session = h.inner.client.session().clone();
        h.rt.block_on(async move {
            #[cfg(feature = "test-harness")]
            if let Some(l) = link {
                l.stop().await;
            }
            let _ = tokio::time::timeout(Duration::from_secs(5), session.close()).await;
        });
        WYRM_OK
    })
}

/// Free a handle (shutting it down first if needed).
///
/// # Safety
/// `h` is null or a live handle that no other thread uses any more; it is
/// invalid afterwards.
#[no_mangle]
pub unsafe extern "C" fn wyrm_free(h: *mut WyrmHandle) {
    if h.is_null() {
        return;
    }
    let _ = guard(|| {
        wyrm_shutdown(h);
        let b = Box::from_raw(h);
        let WyrmHandle { rt, inner } = *b;
        drop(inner);
        rt.shutdown_background();
        WYRM_OK
    });
}

/// Free a buffer from [`wyrm_next_event`].
///
/// # Safety
/// `p`/`len` come from one `wyrm_next_event` call and are freed once.
#[no_mangle]
pub unsafe extern "C" fn wyrm_buf_free(p: *mut u8, len: usize) {
    if p.is_null() {
        return;
    }
    let _ = guard(|| {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)));
        WYRM_OK
    });
}

/// Free an error string from `wyrm_open*`.
///
/// # Safety
/// `s` comes from this library and is freed once.
#[no_mangle]
pub unsafe extern "C" fn wyrm_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    let _ = guard(|| {
        drop(CString::from_raw(s));
        WYRM_OK
    });
}

/// Library version (static string, do not free).
#[no_mangle]
pub extern "C" fn wyrm_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr().cast()
}

// ---------- events ----------

/// Wait up to `timeout_ms` for one event. Returns [`WYRM_EVENT`] and sets
/// `*out`/`*out_len` (free with [`wyrm_buf_free`]), [`WYRM_OK`] on timeout,
/// or [`WYRM_ERR_CLOSED`] once the handle is shut down. One thread at a
/// time; it may block, so call it off the UI thread.
///
/// # Safety
/// `h` is a live handle; `out` and `out_len` are writable.
#[no_mangle]
pub unsafe extern "C" fn wyrm_next_event(
    h: *const WyrmHandle,
    timeout_ms: u32,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        let Some(h) = handle(h) else {
            return WYRM_ERR_ARG;
        };
        if out.is_null() || out_len.is_null() {
            return WYRM_ERR_ARG;
        }
        let inner = h.inner.clone();
        let got = h.rt.block_on(async move {
            let woken = inner.wake.notified();
            tokio::pin!(woken);
            woken.as_mut().enable();
            if inner.closed.load(Ordering::SeqCst) {
                return Err(());
            }
            let mut rx = tokio::select! {
                g = inner.rx.lock() => g,
                _ = &mut woken => return Err(()),
                _ = tokio::time::sleep(Duration::from_millis(timeout_ms.into())) => return Ok(None),
            };
            tokio::select! {
                v = rx.recv() => Ok(v),
                _ = &mut woken => Err(()),
                _ = tokio::time::sleep(Duration::from_millis(timeout_ms.into())) => Ok(None),
            }
        });
        match got {
            Err(()) => WYRM_ERR_CLOSED,
            Ok(None) => WYRM_OK,
            Ok(Some(buf)) => {
                let b = buf.into_boxed_slice();
                *out_len = b.len();
                *out = Box::into_raw(b).cast();
                WYRM_EVENT
            }
        }
    })
}

// ---------- requests ----------

/// Common request prologue: live handle, UTF-8 key.
unsafe fn request<'a>(
    h: *const WyrmHandle,
    key: *const c_char,
) -> Result<(&'a WyrmHandle, String), i32> {
    let h = handle(h).ok_or(WYRM_ERR_ARG)?;
    if h.inner.closed.load(Ordering::SeqCst) {
        return Err(WYRM_ERR_CLOSED);
    }
    let key = text(key).filter(|k| !k.is_empty()).ok_or(WYRM_ERR_ARG)?;
    Ok((h, key.to_owned()))
}

/// `~meta` of `key`; result: the canonical `~meta` CBOR as a byte string.
///
/// # Safety
/// `h` is a live handle; `key` is a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn wyrm_meta(h: *const WyrmHandle, id: u64, key: *const c_char) -> i32 {
    guard(|| match request(h, key) {
        Err(e) => e,
        Ok((h, key)) => {
            let inner = h.inner.clone();
            h.rt.spawn(async move {
                let f = match inner.client.meta(&key).await {
                    Ok(m) => ok_frame(id, Some(meta_bytes(&m))),
                    Err(e) => client_err(id, &e),
                };
                inner.emit(f).await;
            });
            WYRM_OK
        }
    })
}

/// One-shot children; result: `[{name, meta}]`.
///
/// # Safety
/// `h` is a live handle; `key` is a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn wyrm_children(h: *const WyrmHandle, id: u64, key: *const c_char) -> i32 {
    guard(|| match request(h, key) {
        Err(e) => e,
        Ok((h, key)) => {
            let inner = h.inner.clone();
            h.rt.spawn(async move {
                let f = match inner.client.children(&key).await {
                    Ok(kids) => ok_frame(
                        id,
                        Some(Value::Array(kids.iter().map(child_value).collect())),
                    ),
                    Err(e) => client_err(id, &e),
                };
                inner.emit(f).await;
            });
            WYRM_OK
        }
    })
}

/// Write `value` (canonical CBOR of a `Value`) to `key/~set`.
///
/// # Safety
/// `h` is a live handle; `key` is a NUL-terminated string; `value` is valid
/// for `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn wyrm_set(
    h: *const WyrmHandle,
    id: u64,
    key: *const c_char,
    value: *const u8,
    len: usize,
) -> i32 {
    guard(|| {
        let (h, key) = match request(h, key) {
            Ok(x) => x,
            Err(e) => return e,
        };
        let Some(v) = bytes(value, len).and_then(|b| from_slice::<Value>(b).ok()) else {
            return WYRM_ERR_ARG;
        };
        let inner = h.inner.clone();
        h.rt.spawn(async move {
            let f = match inner.client.set(&key, v).await {
                Ok(()) => ok_frame(id, None),
                Err(e) => client_err(id, &e),
            };
            inner.emit(f).await;
        });
        WYRM_OK
    })
}

/// Invoke `action` on `key` with `args` (CBOR `Value`, may be null for
/// `{}`). Every result but the last comes as a `value {v}` event; the last
/// is the `result` of the final `ok`.
///
/// # Safety
/// `h` is a live handle; `key` and `action` are NUL-terminated strings;
/// `args` is null or valid for `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn wyrm_invoke(
    h: *const WyrmHandle,
    id: u64,
    key: *const c_char,
    action: *const c_char,
    args: *const u8,
    len: usize,
) -> i32 {
    guard(|| {
        let (h, key) = match request(h, key) {
            Ok(x) => x,
            Err(e) => return e,
        };
        let Some(action) = text(action).map(str::to_owned) else {
            return WYRM_ERR_ARG;
        };
        let args = if args.is_null() {
            Value::Map(BTreeMap::new())
        } else {
            match bytes(args, len).and_then(|b| from_slice::<Value>(b).ok()) {
                Some(v) => v,
                None => return WYRM_ERR_ARG,
            }
        };
        let inner = h.inner.clone();
        h.rt.spawn(async move {
            let f = match inner.client.invoke(&key, &action, args).await {
                Err(e) => client_err(id, &e),
                Ok(mut s) => {
                    let mut last: Option<Value> = None;
                    let mut failed = None;
                    while let Some(item) = s.next().await {
                        match item {
                            Ok(None) => {}
                            Ok(Some(v)) => {
                                if let Some(prev) = last.replace(v) {
                                    inner.emit(event_frame(id, "value", [("v", prev)])).await;
                                }
                            }
                            Err(e) => {
                                failed = Some(e);
                                break;
                            }
                        }
                    }
                    match failed {
                        Some(e) => client_err(id, &e),
                        None => ok_frame(id, last),
                    }
                }
            };
            inner.emit(f).await;
        });
        WYRM_OK
    })
}

/// Reactive `list` of `key`: `ok`, then `refreshed`, `added`, `changed`,
/// `removed`, `connected`, `disconnected` events, `closed` at the end.
///
/// # Safety
/// `h` is a live handle; `key` is a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn wyrm_list(h: *const WyrmHandle, id: u64, key: *const c_char) -> i32 {
    guard(|| match request(h, key) {
        Err(e) => e,
        Ok((h, key)) => h.open_stream(id, move |inner| async move {
            let mut s = match inner.client.list(&key).await {
                Ok(s) => s,
                Err(e) => return inner.emit(client_err(id, &e)).await,
            };
            inner.emit(ok_frame(id, None)).await;
            while let Some(ev) = s.next().await {
                let f = match ev {
                    ListEvent::Refreshed(kids) => event_frame(
                        id,
                        "refreshed",
                        [(
                            "children",
                            Value::Array(kids.iter().map(child_value).collect()),
                        )],
                    ),
                    ListEvent::Added(c) => event_frame(id, "added", child_fields(&c)),
                    ListEvent::Changed(c) => event_frame(id, "changed", child_fields(&c)),
                    ListEvent::Removed(n) => event_frame(id, "removed", [("name", Value::Str(n))]),
                    ListEvent::Connected(n) => {
                        event_frame(id, "connected", [("name", Value::Str(n))])
                    }
                    ListEvent::Disconnected(None) => event_frame(id, "disconnected", []),
                    ListEvent::Disconnected(Some(n)) => {
                        event_frame(id, "disconnected", [("name", Value::Str(n))])
                    }
                };
                inner.emit(f).await;
            }
            inner.emit(event_frame(id, "closed", [])).await;
        }),
    })
}

/// Values of a node or pattern: `ok`, then `sample {key, v, q, t, qual?}`
/// (`q` = quality name) and `removed {key}` events.
///
/// # Safety
/// `h` is a live handle; `pattern` is a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn wyrm_subscribe(
    h: *const WyrmHandle,
    id: u64,
    pattern: *const c_char,
) -> i32 {
    guard(|| match request(h, pattern) {
        Err(e) => e,
        Ok((h, key)) => h.open_stream(id, move |inner| async move {
            let mut s = match inner.client.subscribe(&key).await {
                Ok(s) => s,
                Err(e) => return inner.emit(client_err(id, &e)).await,
            };
            inner.emit(ok_frame(id, None)).await;
            while let Some(ev) = s.next().await {
                let f = match ev {
                    ValEvent::Sample { key, sample, qual } => {
                        let mut f = vec![
                            ("key", Value::Str(key)),
                            ("v", sample.v),
                            ("q", Value::from(sample.q.name())),
                            ("t", Value::UInt(sample.t)),
                        ];
                        if let Some(q) = qual {
                            f.push(("qual", Value::Str(q)));
                        }
                        event_frame(id, "sample", f)
                    }
                    ValEvent::Removed(key) => {
                        event_frame(id, "removed", [("key", Value::Str(key))])
                    }
                };
                // ~val is Data + Drop: a slow reader loses samples, not memory.
                if let Ok(b) = to_vec(&f) {
                    if let Err(mpsc::error::TrySendError::Closed(_)) = inner.tx.try_send(b) {
                        return;
                    }
                }
            }
            inner.emit(event_frame(id, "closed", [])).await;
        }),
    })
}

/// End the `list`/`subscribe` stream `sub`; the reply (`ok`, or
/// `not_found`) comes as an event for `id`.
///
/// # Safety
/// `h` is a live handle.
#[no_mangle]
pub unsafe extern "C" fn wyrm_unsubscribe(h: *const WyrmHandle, id: u64, sub: u64) -> i32 {
    guard(|| {
        let Some(h) = handle(h) else {
            return WYRM_ERR_ARG;
        };
        if h.inner.closed.load(Ordering::SeqCst) {
            return WYRM_ERR_CLOSED;
        }
        let t = h
            .inner
            .streams
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remove(&sub);
        let f = match t {
            Some(t) => {
                t.abort();
                ok_frame(id, None)
            }
            None => err_frame(id, Status::NotFound.code(), "no such stream"),
        };
        let inner = h.inner.clone();
        h.rt.spawn(async move { inner.emit(f).await });
        WYRM_OK
    })
}

impl WyrmHandle {
    fn open_stream<F, Fut>(&self, id: u64, body: F) -> i32
    where
        F: FnOnce(Arc<Inner>) -> Fut,
        Fut: std::future::Future<Output = ()> + Send + 'static,
    {
        let mut streams = self.inner.streams.lock().unwrap_or_else(|p| p.into_inner());
        streams.retain(|_, t| !t.is_finished());
        if streams.contains_key(&id) {
            return WYRM_ERR_DUPLICATE;
        }
        let t = self.rt.spawn(body(self.inner.clone()));
        streams.insert(id, t);
        WYRM_OK
    }
}

impl Inner {
    /// Queue a frame, waiting for room (replies and `~meta` events are
    /// never dropped).
    async fn emit(&self, v: Value) {
        if let Ok(b) = to_vec(&v) {
            let _ = self.tx.send(b).await;
        }
    }
}

// ---------- frames (same shapes as the gateway WebSocket) ----------

fn map<'a>(fields: impl IntoIterator<Item = (&'a str, Value)>) -> Value {
    Value::Map(fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

fn ok_frame(id: u64, result: Option<Value>) -> Value {
    let mut m = BTreeMap::from([
        ("id".to_owned(), Value::UInt(id)),
        ("ok".to_owned(), Value::Bool(true)),
    ]);
    if let Some(r) = result {
        m.insert("result".into(), r);
    }
    Value::Map(m)
}

fn err_frame(id: u64, status: u8, message: &str) -> Value {
    map([
        ("id", Value::UInt(id)),
        ("ok", Value::Bool(false)),
        (
            "error",
            map([
                ("status", Value::UInt(status.into())),
                ("message", Value::from(message)),
            ]),
        ),
    ])
}

fn client_err(id: u64, e: &ClientError) -> Value {
    err_frame(id, e.status.code(), &e.message)
}

fn event_frame<'a>(id: u64, ty: &str, fields: impl IntoIterator<Item = (&'a str, Value)>) -> Value {
    let mut ev: BTreeMap<String, Value> =
        fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect();
    ev.insert("type".into(), Value::from(ty));
    map([("id", Value::UInt(id)), ("event", Value::Map(ev))])
}

fn meta_bytes(m: &NodeMeta) -> Value {
    Value::Bytes(to_vec(m).unwrap_or_default())
}

fn child_fields(c: &Child) -> [(&'static str, Value); 2] {
    [
        ("name", Value::Str(c.name.clone())),
        ("meta", meta_bytes(&c.meta)),
    ]
}

fn child_value(c: &Child) -> Value {
    map(child_fields(c))
}
