//! One OPC UA session per connection (the driver's `Transport`): open with
//! the configured security and identity, batched Read, Write with the
//! server's data type, Browse and GetEndpoints.
//!
//! The library's own reconnect is off (`session_retry_limit(0)`): when the
//! connection is lost, the session's event loop ends and every later call
//! answers `Transport`, so the framework reopens with its own backoff and a
//! new session reads the namespace array again. Secure channel renewals
//! happen inside the event loop and never end it.

use crate::conv::{self, NodeRef};
use crate::pki::{self, Trust};
use crate::{Conn, Dev, Identity, Mode, Point, Policy};
use futures_util::StreamExt;
use opcua::client::{Client, ClientBuilder, IdentityToken, Session, SessionPollResult};
use opcua::crypto::{PrivateKey, SecurityPolicy, X509};
use opcua::types::{
    AttributeId, BrowseDescription, BrowseDirection, BrowseResultMask, DataValue,
    EndpointDescription, MessageSecurityMode, NamespaceMap, NodeClass, NodeId, ReadValueId,
    ReferenceTypeId, StatusCode, SubStatusCode, TimestampsToReturn, UserTokenType, VariableId,
    Variant, VariantScalarTypeId, WriteValue,
};
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::net::IpAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::{oneshot, watch};
use tokio::task::JoinHandle;
use tracing::debug;
use wyrm_core::{Status, Value};
use wyrm_link_sdk::driver::{DriverError, Outcome, PointId};
use wyrm_link_sdk::LinkError;

/// The server's `MaxNodesPerRead` by endpoint ([`endpoint_key`]), as the
/// last open read it, for [`crate::OpcuaDriver::poll_timeout`] (which gets
/// no transport).
static LIMITS: Mutex<BTreeMap<String, usize>> = Mutex::new(BTreeMap::new());

/// The server limit last read at `url` (0: none known or no limit).
pub fn server_limit(url: &str) -> usize {
    LIMITS
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .get(&endpoint_key(url))
        .copied()
        .unwrap_or(0)
}

fn set_server_limit(url: &str, n: usize) {
    LIMITS
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .insert(endpoint_key(url), n);
}

/// The open session of one connection.
pub struct Transport {
    client: Client,
    session: Arc<Session>,
    /// The event loop task; aborted on drop.
    task: Option<JoinHandle<()>>,
    /// `Some(code)` once the event loop ended (connection lost).
    dead: watch::Receiver<Option<StatusCode>>,
    nss: NamespaceMap,
    /// The server's MaxNodesPerRead (0: no limit given).
    max_read: usize,
    url: String,
    request_timeout: Duration,
    /// Write target types by node: (type, array).
    types: HashMap<NodeId, (VariantScalarTypeId, bool)>,
    outcomes: Vec<Outcome>,
    note: Option<String>,
    /// The use of a supplied certificate's files, while the session lives
    /// (the library reads the key on channel renewals). Dropped last.
    _lease: Option<pki::KeyLease>,
}

impl Drop for Transport {
    fn drop(&mut self) {
        let Some(task) = self.task.take() else {
            return;
        };
        // Close the session politely when the loop still runs, then stop it.
        let alive = self.dead.borrow().is_none();
        match tokio::runtime::Handle::try_current() {
            Ok(rt) if alive => {
                let session = self.session.clone();
                rt.spawn(async move {
                    let _ =
                        tokio::time::timeout(Duration::from_secs(2), session.disconnect()).await;
                    task.abort();
                });
            }
            _ => task.abort(),
        }
    }
}

/// Aborts the event loop task if `open` is dropped half-way (its timeout).
struct AbortOnDrop(Option<JoinHandle<()>>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        if let Some(t) = self.0.take() {
            t.abort();
        }
    }
}

/// Parse an endpoint URL with the parser the library connects with
/// (`url::Url`, host from `host_str`), so that the host checked here is the
/// host it connects to. Refused: another scheme than `opc.tcp`, no host,
/// user info (`opc.tcp://127.0.0.1@evil/`), a query or a fragment.
pub fn parse_endpoint(s: &str) -> Result<url::Url, String> {
    let u = url::Url::parse(s).map_err(|e| format!("not a URL: {e}"))?;
    if u.scheme() != "opc.tcp" {
        return Err("expected opc.tcp://host:port/path".into());
    }
    if u.host_str().is_none_or(str::is_empty) {
        return Err("no host".into());
    }
    if !u.username().is_empty() || u.password().is_some() {
        return Err("user info (user@host) is not allowed".into());
    }
    if u.query().is_some() || u.fragment().is_some() {
        return Err("a query or fragment is not allowed".into());
    }
    Ok(u)
}

/// The endpoint as one key for the files and limits kept per endpoint:
/// `opc.tcp://<host, lower case>:<port, 4840 when absent><path, / when
/// empty>`, so that `opc.tcp://PLC1:4840` and `opc.tcp://plc1/` are one
/// endpoint. (The URL parser keeps a non-special scheme's host and path as
/// written.) A URL that is not an endpoint is its own key.
pub fn endpoint_key(url: &str) -> String {
    let Ok(u) = parse_endpoint(url) else {
        return url.to_owned();
    };
    let host = u.host_str().unwrap_or_default().to_ascii_lowercase();
    let path = match u.path() {
        "" => "/",
        p => p,
    };
    format!("opc.tcp://{host}:{}{path}", u.port().unwrap_or(4840))
}

/// The host the library connects to (IPv6 without brackets); empty when
/// the URL is not a valid endpoint.
pub fn host_of(url: &str) -> String {
    parse_endpoint(url)
        .ok()
        .and_then(|u| u.host_str().map(|h| h.trim_matches(['[', ']']).to_owned()))
        .unwrap_or_default()
}

/// The endpoint's host is this machine (`localhost`, 127.0.0.0/8, ::1).
pub fn is_loopback(url: &str) -> bool {
    let host = host_of(url);
    host.eq_ignore_ascii_case("localhost") || host.parse::<IpAddr>().is_ok_and(|a| a.is_loopback())
}

/// A user identity leaves this host only over a channel with security. On
/// a channel without it, how a token is protected comes from the endpoint
/// description of GetEndpoints, which arrives before any trusted channel: a
/// man in the middle could name its own certificate and get the password
/// (or a signature with the user's key). Loopback is the exception.
pub fn identity_allowed(identity: Identity, mode: Mode, url: &str) -> Result<(), String> {
    if identity == Identity::Anonymous || mode != Mode::None || is_loopback(url) {
        return Ok(());
    }
    Err(format!(
        "identity {} to {} needs security mode sign or sign_and_encrypt (only loopback \
         takes a user identity without one)",
        match identity {
            Identity::Username => "username",
            _ => "certificate",
        },
        host_of(url)
    ))
}

fn policy_of(p: Policy) -> SecurityPolicy {
    match p {
        Policy::None => SecurityPolicy::None,
        Policy::Basic256Sha256 => SecurityPolicy::Basic256Sha256,
        Policy::Aes128Sha256RsaOaep => SecurityPolicy::Aes128Sha256RsaOaep,
        Policy::Aes256Sha256RsaPss => SecurityPolicy::Aes256Sha256RsaPss,
    }
}

fn mode_of(m: Mode) -> MessageSecurityMode {
    match m {
        Mode::None => MessageSecurityMode::None,
        Mode::Sign => MessageSecurityMode::Sign,
        Mode::SignAndEncrypt => MessageSecurityMode::SignAndEncrypt,
    }
}

fn transport(e: impl std::fmt::Display) -> DriverError {
    DriverError::Transport(e.to_string())
}

/// Why an open failed, for the connection's `error` leaf. On a secured
/// connection the advice comes from the server's certificate (from
/// GetEndpoints) and this client's trust store, not from file times: a
/// certificate the store does not trust names the server's thumbprint on
/// every attempt; a trusted one that fails a check names both; otherwise
/// the server refused this client, and the advice names the client's.
fn open_error(
    code: StatusCode,
    conn: &Conn,
    prep: Option<&pki::Prepared>,
    server: Option<&X509>,
) -> String {
    let sub = code.sub_code();
    let name = sub.name();
    let mut msg = format!("connect to {}: {name}", conn.p.endpoint);
    let Some(prep) = prep.filter(|_| conn.p.security_policy != Policy::None) else {
        return msg;
    };
    let Some(cert) = server else {
        return msg;
    };
    let server_thumb = cert.thumbprint().as_hex_string();
    tracing::info!(
        endpoint = %conn.p.endpoint,
        server = %server_thumb,
        client = %prep.thumbprint,
        "opc ua secured open failed: {name}"
    );
    if !prep.trusts(cert) {
        msg.push_str(&format!(
            "; the server certificate (thumbprint {server_thumb}) is not trusted: pin it \
             (server_cert_pem) or set trust_on_first_use"
        ));
    } else if matches!(
        sub,
        SubStatusCode::BadCertificateTimeInvalid
            | SubStatusCode::BadCertificateIssuerTimeInvalid
            | SubStatusCode::BadCertificateHostNameInvalid
            | SubStatusCode::BadCertificateUriInvalid
            | SubStatusCode::BadCertificateInvalid
    ) {
        msg.push_str(&format!(
            "; a certificate check failed: the server certificate (thumbprint \
             {server_thumb}) needs this host name, the server's application URI and a \
             valid date, and so does this client's (thumbprint {}) on the server",
            prep.thumbprint
        ));
    } else {
        msg.push_str(&format!(
            "; if the server does not trust this client yet, trust its application \
             certificate (thumbprint {}) on the server",
            prep.thumbprint
        ));
    }
    msg
}

fn identity(conn: &Conn) -> Result<IdentityToken, DriverError> {
    let p = &conn.p;
    Ok(match p.identity {
        Identity::Anonymous => IdentityToken::Anonymous,
        Identity::Username => IdentityToken::new_user_name(p.username.clone(), p.password.clone()),
        Identity::Certificate => {
            let cert = X509::from_pem(p.user_cert_pem.as_bytes())
                .map_err(|_| transport("user_cert_pem: not a PEM certificate"))?;
            let key = PrivateKey::from_pem(p.user_key_pem.as_bytes())
                .map_err(|_| transport("user_key_pem: not a PEM RSA private key"))?;
            IdentityToken::new_x509(cert, key)
        }
    })
}

impl Transport {
    pub async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let p = &conn.p;
        let policy = policy_of(p.security_policy);
        let mode = mode_of(p.security_mode);
        identity_allowed(p.identity, p.security_mode, &p.endpoint).map_err(transport)?;
        let prep = match (&conn.pki, p.security_policy) {
            (Some(root), _) => {
                let root = root.clone();
                let url = endpoint_key(&p.endpoint);
                let uri = p.application_uri.clone();
                let own = (!p.cert_pem.is_empty()).then(|| (p.cert_pem.clone(), p.key_pem.clone()));
                let pin = p.server_cert_pem.clone();
                let tofu = p.trust_on_first_use;
                // Key generation and file I/O: off the async workers. A cut
                // open lets it finish, and the next open finds the files.
                let prep = tokio::task::spawn_blocking(move || {
                    let trust = if !pin.is_empty() {
                        Trust::Pin(&pin)
                    } else if tofu {
                        Trust::FirstUse
                    } else {
                        Trust::Strict
                    };
                    pki::prepare(
                        &root,
                        &pki::Request {
                            url: &url,
                            application_uri: &uri,
                            own: own.as_ref().map(|(c, k)| (c.as_str(), k.as_str())),
                            trust,
                        },
                    )
                })
                .await
                .map_err(transport)?
                .map_err(transport)?;
                Some(prep)
            }
            (None, Policy::None) => None,
            (None, _) => {
                return Err(transport(
                    "a secured connection needs the link's data_dir for its certificates",
                ))
            }
        };
        let request_timeout = Duration::from_millis(p.request_timeout_ms.into());
        let mut b = ClientBuilder::new()
            .application_name("WYRM OPC UA Client")
            .application_uri(p.application_uri.clone())
            .product_uri("urn:wyrm:opcua")
            .session_name("wyrm")
            .create_sample_keypair(false)
            .verify_server_certs(true)
            .session_retry_limit(0)
            .session_timeout(p.session_timeout_ms)
            .request_timeout(request_timeout)
            .keep_alive_interval(Duration::from_millis(
                (u64::from(p.session_timeout_ms) / 3).clamp(1000, 30_000),
            ));
        match &prep {
            Some(prep) => {
                b = b
                    .pki_dir(prep.store.clone())
                    .certificate_path(prep.cert.clone())
                    .private_key_path(prep.key.clone())
                    .trust_server_certs(prep.trust_unknown);
            }
            None => {
                b = b
                    .pki_dir(pki::plain_store().map_err(transport)?)
                    .trust_server_certs(false);
            }
        }
        let mut client = b.client().map_err(|e| transport(e.join("; ")))?;
        let id = identity(conn)?;

        // GetEndpoints, then the endpoint of the configured policy and mode,
        // reached at the configured URL (a server behind NAT or a relay
        // advertises an address the client cannot reach).
        let eps = client
            .get_server_endpoints_from_url(p.endpoint.as_str())
            .await
            .map_err(|e| transport(open_error(e.status(), conn, prep.as_ref(), None)))?;
        let mut ep =
            Client::find_matching_endpoint(&eps, &p.endpoint, policy, mode).ok_or_else(|| {
                transport(format!(
                    "the server has no endpoint {} / {mode:?} at {}",
                    policy.to_str(),
                    p.endpoint
                ))
            })?;
        ep.endpoint_url = p.endpoint.as_str().into();
        // The certificate the server will present (CreateSession checks it
        // is the same), for the advice when the open fails.
        let server_cert = X509::from_byte_string(&ep.server_certificate).ok();
        let fail = |code: StatusCode| {
            transport(open_error(code, conn, prep.as_ref(), server_cert.as_ref()))
        };
        let (session, event_loop) = client
            .connect_to_endpoint_directly(ep, id)
            .map_err(|e| fail(e.status()))?;
        let (up_tx, up_rx) = oneshot::channel::<Result<(), StatusCode>>();
        let (dead_tx, dead_rx) = watch::channel(None);
        let task = tokio::spawn(async move {
            let events = event_loop.enter();
            let mut events = std::pin::pin!(events);
            let mut up = Some(up_tx);
            let end = loop {
                match events.next().await {
                    Some(Ok(SessionPollResult::Reconnected(_))) => {
                        if let Some(tx) = up.take() {
                            let _ = tx.send(Ok(()));
                        }
                    }
                    Some(Ok(SessionPollResult::ConnectionLost(code))) => break code,
                    Some(Ok(_)) => {}
                    Some(Err(code)) => break code,
                    None => break StatusCode::BadConnectionClosed,
                }
            };
            debug!("opc ua session ended: {end}");
            if let Some(tx) = up.take() {
                let _ = tx.send(Err(end));
            }
            let _ = dead_tx.send(Some(end));
        });
        let mut guard = AbortOnDrop(Some(task));
        match up_rx.await {
            Ok(Ok(())) => {}
            Ok(Err(code)) => return Err(fail(code)),
            Err(_) => return Err(transport("session event loop stopped")),
        }
        if let Some(prep) = &prep {
            prep.opened();
        }
        let nss = session
            .read_namespace_array()
            .await
            .map_err(|e| transport(format!("read the namespace array: {}", e.status())))?;
        let max_read = read_max_nodes(&session).await;
        set_server_limit(&p.endpoint, max_read);
        let note = (p.security_mode == Mode::None && !is_loopback(&p.endpoint)).then(|| {
            format!(
                "security mode None to {}: values travel unsigned and unencrypted",
                host_of(&p.endpoint)
            )
        });
        Ok(Transport {
            client,
            session,
            task: guard.0.take(),
            dead: dead_rx,
            nss,
            max_read,
            url: p.endpoint.clone(),
            request_timeout,
            types: HashMap::new(),
            outcomes: Vec::new(),
            note,
            _lease: prep.and_then(|p| p.lease),
        })
    }

    pub fn note(&self) -> Option<String> {
        self.note.clone()
    }

    pub fn take_outcomes(&mut self) -> Vec<Outcome> {
        std::mem::take(&mut self.outcomes)
    }

    fn check_alive(&self) -> Result<(), DriverError> {
        match *self.dead.borrow() {
            Some(code) => Err(DriverError::Transport(format!(
                "session lost: {}",
                code.sub_code().name()
            ))),
            None => Ok(()),
        }
    }

    /// Nodes per Read request: the device's limit, lowered to the server's.
    pub fn chunk(&self, dev: &Dev) -> usize {
        let d = dev.max_nodes_per_read.max(1) as usize;
        if self.max_read == 0 {
            d
        } else {
            d.min(self.max_read)
        }
    }

    /// One Read request; counts its outcome.
    async fn read(&mut self, ids: &[ReadValueId]) -> Result<Vec<DataValue>, DriverError> {
        self.check_alive()?;
        let t0 = Instant::now();
        let r = self
            .session
            .read(ids, TimestampsToReturn::Neither, 0.0)
            .await;
        match r {
            Ok(v) if v.len() == ids.len() => {
                self.outcomes.push(Outcome::Reply(t0.elapsed()));
                Ok(v)
            }
            Ok(v) => {
                self.outcomes.push(Outcome::Error);
                Err(DriverError::Device(format!(
                    "read: {} results for {} nodes",
                    v.len(),
                    ids.len()
                )))
            }
            Err(e) => {
                let err = conv::service_error(e.status(), "read");
                self.outcomes.push(match err {
                    DriverError::Device(_) => Outcome::Timeout,
                    DriverError::Point(_) => Outcome::Exception(t0.elapsed()),
                    DriverError::Transport(_) => Outcome::Error,
                });
                Err(self.check_alive().err().unwrap_or(err))
            }
        }
    }

    /// Liveness: read `Server_ServerStatus_State` (i=2259). Any answer is
    /// alive.
    pub async fn ping(&mut self) -> Result<(), DriverError> {
        let id = ReadValueId::from(NodeId::from(VariableId::Server_ServerStatus_State));
        match self.read(&[id]).await {
            Ok(_) | Err(DriverError::Point(_)) => Ok(()),
            Err(e) => Err(e),
        }
    }

    /// Read every point of `points` in Read requests of at most `chunk`
    /// nodes.
    pub async fn poll(
        &mut self,
        dev: &Dev,
        points: &[(PointId, Point)],
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let mut out = Vec::with_capacity(points.len());
        let mut todo: Vec<(&PointId, &Point, NodeId)> = Vec::with_capacity(points.len());
        for (id, p) in points {
            match p.node.resolve(&dev.namespace_uri, &self.nss) {
                Ok(n) => todo.push((id, p, n)),
                Err(e) => out.push((id.clone(), Err(DriverError::Point(e)))),
            }
        }
        let chunk = self.chunk(dev);
        let mut chunks = todo.chunks(chunk);
        while let Some(batch) = chunks.next() {
            let ids: Vec<ReadValueId> = batch
                .iter()
                .map(|(_, _, n)| ReadValueId::from(n.clone()))
                .collect();
            match self.read(&ids).await {
                Ok(values) => {
                    for ((id, p, _), dv) in batch.iter().zip(values) {
                        out.push(((*id).clone(), point_value(p, dv)));
                    }
                }
                Err(e) => {
                    let broken = matches!(e, DriverError::Transport(_));
                    out.extend(
                        batch
                            .iter()
                            .map(|(id, _, _)| ((*id).clone(), Err(e.clone()))),
                    );
                    if broken {
                        // The session is gone: the rest fails with it.
                        for rest in chunks.by_ref() {
                            out.extend(
                                rest.iter()
                                    .map(|(id, _, _)| ((*id).clone(), Err(e.clone()))),
                            );
                        }
                    }
                }
            }
        }
        out
    }

    /// The type a write to `node` needs: its DataType (built-in), else the
    /// type of its current value; array or scalar from its ValueRank.
    async fn write_type(
        &mut self,
        node: &NodeId,
    ) -> Result<(VariantScalarTypeId, bool), DriverError> {
        if let Some(t) = self.types.get(node) {
            return Ok(*t);
        }
        let attr = |a: AttributeId| ReadValueId {
            node_id: node.clone(),
            attribute_id: a as u32,
            ..Default::default()
        };
        let r = self
            .read(&[
                attr(AttributeId::DataType),
                attr(AttributeId::ValueRank),
                attr(AttributeId::Value),
            ])
            .await?;
        if !r[0].status().is_good() {
            return Err(DriverError::Point(format!(
                "read the data type: {}",
                r[0].status().sub_code().name()
            )));
        }
        let current = r[2].value.as_ref();
        let current_array = matches!(current, Some(Variant::Array(_)));
        let builtin = match &r[0].value {
            Some(Variant::NodeId(dt)) => conv::builtin_type(dt),
            _ => None,
        };
        let t = builtin
            .or_else(|| current.and_then(|v| v.scalar_type_id()))
            .ok_or_else(|| {
                DriverError::Point(format!(
                    "data type {:?} is not a built-in type this link writes",
                    r[0].value
                ))
            })?;
        let rank = match &r[1].value {
            Some(Variant::Int32(n)) => *n,
            _ => -1,
        };
        let array = match rank {
            n if n >= 0 => true,
            -1 => false,
            _ => current_array,
        };
        self.types.insert(node.clone(), (t, array));
        Ok((t, array))
    }

    pub async fn write(&mut self, dev: &Dev, point: &Point, v: &Value) -> Result<(), DriverError> {
        self.check_alive()?;
        let node = point
            .node
            .resolve(&dev.namespace_uri, &self.nss)
            .map_err(DriverError::Point)?;
        let (t, array) = self.write_type(&node).await?;
        let raw = conv::unscale(v, point.p.scale, point.p.offset).map_err(DriverError::Point)?;
        let variant = conv::to_variant(&raw, t, array).map_err(DriverError::Point)?;
        let wv = WriteValue {
            node_id: node,
            attribute_id: AttributeId::Value as u32,
            index_range: Default::default(),
            value: DataValue {
                value: Some(variant),
                ..Default::default()
            },
        };
        let t0 = Instant::now();
        match self.session.write(&[wv]).await {
            Ok(codes) => {
                let code = codes
                    .first()
                    .copied()
                    .unwrap_or(StatusCode::BadUnexpectedError);
                if code.is_good() {
                    self.outcomes.push(Outcome::Reply(t0.elapsed()));
                    Ok(())
                } else {
                    self.outcomes.push(Outcome::Exception(t0.elapsed()));
                    Err(DriverError::Point(format!(
                        "write: {}",
                        code.sub_code().name()
                    )))
                }
            }
            Err(e) => {
                let err = conv::service_error(e.status(), "write");
                self.outcomes.push(match err {
                    DriverError::Device(_) => Outcome::Timeout,
                    _ => Outcome::Error,
                });
                Err(self.check_alive().err().unwrap_or(err))
            }
        }
    }

    // ---------- actions ----------

    /// `browse {node, depth, limit}`: hierarchical references forward from
    /// `node`, `depth` levels, at most `limit` entries.
    pub async fn browse(
        &mut self,
        dev: &Dev,
        start: &NodeRef,
        depth: u32,
        limit: usize,
    ) -> Result<Value, LinkError> {
        self.check_alive().map_err(link_error)?;
        // The start node is any node of the server: without ns= it is in
        // namespace 0 (the device's namespace is for its points).
        let start = start
            .resolve("", &self.nss)
            .map_err(LinkError::invalid_parameter)?;
        // Nodes queued or listed: a node reached by two hierarchical
        // references (Organizes and HasComponent) is listed once.
        let mut seen = HashSet::from([start.clone()]);
        let mut queue = VecDeque::from([(start, 1u32)]);
        let mut found: Vec<(NodeId, BTreeMap<String, Value>, NodeClass)> = Vec::new();
        'outer: while let Some((node, level)) = queue.pop_front() {
            let desc = BrowseDescription {
                node_id: node,
                browse_direction: BrowseDirection::Forward,
                reference_type_id: ReferenceTypeId::HierarchicalReferences.into(),
                include_subtypes: true,
                node_class_mask: 0,
                result_mask: BrowseResultMask::All as u32,
            };
            let t0 = Instant::now();
            let mut results = self
                .session
                .browse(&[desc], limit as u32, None)
                .await
                .map_err(|e| self.action_error(e.status(), "browse"))?;
            self.outcomes.push(Outcome::Reply(t0.elapsed()));
            while let Some(r) = results.pop() {
                if !r.status_code.is_good() {
                    return Err(LinkError::new(
                        Status::InvalidParameter,
                        format!("browse: {}", r.status_code.sub_code().name()),
                    ));
                }
                for rd in r.references.unwrap_or_default() {
                    if found.len() >= limit {
                        if !r.continuation_point.is_null() {
                            let _ = self
                                .session
                                .browse_next(true, &[r.continuation_point])
                                .await;
                        }
                        break 'outer;
                    }
                    if rd.node_id.server_index != 0 {
                        continue;
                    }
                    let id = rd.node_id.node_id.clone();
                    if !seen.insert(id.clone()) {
                        continue;
                    }
                    let mut m = BTreeMap::new();
                    m.insert("node_id".into(), Value::Str(id.to_string()));
                    let uri = self
                        .nss
                        .known_namespaces()
                        .iter()
                        .find(|(_, i)| **i == id.namespace)
                        .map(|(u, _)| u.clone())
                        .unwrap_or_default();
                    m.insert("namespace_uri".into(), Value::Str(uri));
                    m.insert(
                        "browse_name".into(),
                        Value::Str(rd.browse_name.name.value().clone().unwrap_or_default()),
                    );
                    m.insert(
                        "display_name".into(),
                        Value::Str(rd.display_name.text.value().clone().unwrap_or_default()),
                    );
                    m.insert(
                        "node_class".into(),
                        Value::Str(format!("{:?}", rd.node_class)),
                    );
                    if level < depth && matches!(rd.node_class, NodeClass::Object | NodeClass::View)
                    {
                        queue.push_back((id.clone(), level + 1));
                    }
                    found.push((id, m, rd.node_class));
                }
                if r.continuation_point.is_null() {
                    break;
                }
                let t0 = Instant::now();
                results = self
                    .session
                    .browse_next(false, &[r.continuation_point])
                    .await
                    .map_err(|e| self.action_error(e.status(), "browse_next"))?;
                self.outcomes.push(Outcome::Reply(t0.elapsed()));
            }
        }
        // data types of the variables, in batches
        let vars: Vec<usize> = (0..found.len())
            .filter(|i| found[*i].2 == NodeClass::Variable)
            .collect();
        let chunk = self.chunk(dev);
        for batch in vars.chunks(chunk) {
            let ids: Vec<ReadValueId> = batch
                .iter()
                .map(|i| ReadValueId {
                    node_id: found[*i].0.clone(),
                    attribute_id: AttributeId::DataType as u32,
                    ..Default::default()
                })
                .collect();
            let values = self.read(&ids).await.map_err(link_error)?;
            for (i, dv) in batch.iter().zip(values) {
                let dt = match &dv.value {
                    Some(Variant::NodeId(n)) => conv::builtin_type(n)
                        .map(|t| conv::type_name(t).to_owned())
                        .unwrap_or_else(|| n.to_string()),
                    _ => String::new(),
                };
                found[*i].1.insert("data_type".into(), Value::Str(dt));
            }
        }
        Ok(Value::Array(
            found
                .into_iter()
                .map(|(_, mut m, _)| {
                    m.entry("data_type".into())
                        .or_insert_with(|| Value::Str(String::new()));
                    Value::Map(m)
                })
                .collect(),
        ))
    }

    /// `get_endpoints`: the server's endpoints, policies and user tokens.
    pub async fn get_endpoints(&mut self) -> Result<Value, LinkError> {
        let t0 = Instant::now();
        let eps = tokio::time::timeout(
            self.request_timeout * 2,
            self.client.get_server_endpoints_from_url(self.url.as_str()),
        )
        .await
        .map_err(|_| LinkError::timeout("get_endpoints"))?
        .map_err(|e| {
            LinkError::new(
                Status::NotAvailable,
                format!("get_endpoints: {}", e.status().sub_code().name()),
            )
        })?;
        self.outcomes.push(Outcome::Reply(t0.elapsed()));
        Ok(Value::Array(eps.iter().map(endpoint_value).collect()))
    }

    fn action_error(&self, code: StatusCode, what: &str) -> LinkError {
        match self.check_alive() {
            Err(e) => link_error(e),
            Ok(()) => link_error(conv::service_error(code, what)),
        }
    }
}

/// A driver error as an action reply; `disconnected` makes the framework
/// reconnect.
fn link_error(e: DriverError) -> LinkError {
    match e {
        DriverError::Transport(m) => LinkError::new(Status::Disconnected, m),
        DriverError::Device(m) => LinkError::timeout(m),
        DriverError::Point(m) => LinkError::new(Status::InvalidParameter, m),
    }
}

fn endpoint_value(e: &EndpointDescription) -> Value {
    let mut m = BTreeMap::new();
    m.insert(
        "endpoint_url".into(),
        Value::Str(e.endpoint_url.to_string()),
    );
    let policy = SecurityPolicy::from_uri(e.security_policy_uri.as_ref());
    m.insert(
        "security_policy".into(),
        Value::Str(policy.to_str().to_owned()),
    );
    let mode = match e.security_mode {
        MessageSecurityMode::None => "none",
        MessageSecurityMode::Sign => "sign",
        MessageSecurityMode::SignAndEncrypt => "sign_and_encrypt",
        _ => "invalid",
    };
    m.insert("security_mode".into(), Value::Str(mode.into()));
    m.insert(
        "security_level".into(),
        Value::UInt(u64::from(e.security_level)),
    );
    let tokens = e
        .user_identity_tokens
        .as_deref()
        .unwrap_or_default()
        .iter()
        .map(|t| {
            Value::Str(
                match t.token_type {
                    UserTokenType::Anonymous => "anonymous",
                    UserTokenType::UserName => "username",
                    UserTokenType::Certificate => "certificate",
                    UserTokenType::IssuedToken => "issued_token",
                }
                .into(),
            )
        })
        .collect();
    m.insert("user_tokens".into(), Value::Array(tokens));
    let thumb = X509::from_byte_string(&e.server_certificate)
        .map(|c| c.thumbprint().as_hex_string())
        .unwrap_or_default();
    m.insert("server_certificate_thumbprint".into(), Value::Str(thumb));
    Value::Map(m)
}

/// The server's `MaxNodesPerRead` (i=11705); 0 when it gives none.
async fn read_max_nodes(session: &Session) -> usize {
    let id = ReadValueId::from(NodeId::from(
        VariableId::Server_ServerCapabilities_OperationLimits_MaxNodesPerRead,
    ));
    match session.read(&[id], TimestampsToReturn::Neither, 0.0).await {
        Ok(v) => match v.first().and_then(|d| d.value.as_ref()) {
            Some(Variant::UInt32(n)) => *n as usize,
            _ => 0,
        },
        Err(_) => 0,
    }
}

/// One read item as the point's value: Good only, scaled.
fn point_value(p: &Point, dv: DataValue) -> Result<Value, DriverError> {
    conv::item_status(dv.status)?;
    let v = match &dv.value {
        Some(v) => conv::to_value(v).map_err(DriverError::Point)?,
        None => Value::Null,
    };
    conv::scale(v, p.p.scale, p.p.offset).map_err(DriverError::Point)
}

/// Where the PKI of a link lives under its `data_dir`.
pub fn pki_root(data_dir: &std::path::Path) -> PathBuf {
    data_dir.join("opcua-pki")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hosts() {
        assert_eq!(host_of("opc.tcp://plc1:4840/path"), "plc1");
        assert_eq!(host_of("opc.tcp://10.0.0.5:4840"), "10.0.0.5");
        assert_eq!(host_of("opc.tcp://[::1]:4840/"), "::1");
        assert!(is_loopback("opc.tcp://127.0.0.1:4840/"));
        assert!(is_loopback("opc.tcp://127.1.2.3:4840/"));
        assert!(is_loopback("opc.tcp://LOCALHOST:4840/"));
        assert!(is_loopback("opc.tcp://[::1]:4840/"));
        assert!(!is_loopback("opc.tcp://plc1:4840/"));
        assert!(!is_loopback("opc.tcp://[::ffff:10.0.0.1]:4840/"));
        // the host checked is the host the library connects to
        for (url, host) in [
            ("opc.tcp://plc1:4840/a/b", "plc1"),
            ("opc.tcp://plc1/", "plc1"),
            ("opc.tcp://[fe80::1]:4840/", "fe80::1"),
        ] {
            assert_eq!(host_of(url), host);
            let lib = opcua::core::comms::url::hostname_from_url(url)
                .ok()
                .map(|h| h.trim_matches(['[', ']']).to_owned());
            assert_eq!(lib.as_deref(), Some(host), "{url}");
        }
        // differentials are refused, never read as loopback
        for bad in [
            "opc.tcp://127.0.0.1@evil:4840/",
            "opc.tcp://user:pw@127.0.0.1:4840/",
            "opc.tcp://evil:4840/?127.0.0.1",
            "opc.tcp://evil:4840/#127.0.0.1",
            "opc.tcp://[::1:4840/",
            "opc.tcp://",
            "opc.tcp:///path",
            "http://127.0.0.1:4840/",
            "127.0.0.1:4840",
        ] {
            assert!(parse_endpoint(bad).is_err(), "{bad}");
            assert!(!is_loopback(bad), "{bad}");
            assert_eq!(host_of(bad), "", "{bad}");
        }
    }

    #[test]
    fn endpoint_keys_are_normalised() {
        let k = endpoint_key("opc.tcp://plc1:4840/");
        assert_eq!(k, "opc.tcp://plc1:4840/");
        for same in [
            "opc.tcp://plc1:4840",
            "opc.tcp://PLC1:4840/",
            "opc.tcp://plc1/",
            "opc.tcp://plc1",
        ] {
            assert_eq!(endpoint_key(same), k, "{same}");
        }
        assert_ne!(endpoint_key("opc.tcp://plc1:4841/"), k);
        assert_ne!(endpoint_key("opc.tcp://plc1:4840/a"), k);
        assert_eq!(
            endpoint_key("opc.tcp://[::1]:4840"),
            "opc.tcp://[::1]:4840/"
        );
    }

    #[test]
    fn identities_need_security_off_loopback() {
        let remote = "opc.tcp://plc1:4840/";
        let local = "opc.tcp://127.0.0.1:4840/";
        assert!(identity_allowed(Identity::Anonymous, Mode::None, remote).is_ok());
        // whatever a server's token policy says: refused before GetEndpoints
        assert!(identity_allowed(Identity::Username, Mode::None, remote).is_err());
        assert!(identity_allowed(Identity::Certificate, Mode::None, remote).is_err());
        assert!(identity_allowed(Identity::Username, Mode::Sign, remote).is_ok());
        assert!(identity_allowed(Identity::Certificate, Mode::SignAndEncrypt, remote).is_ok());
        assert!(identity_allowed(Identity::Username, Mode::None, local).is_ok());
        assert!(
            identity_allowed(Identity::Username, Mode::None, "opc.tcp://127.0.0.1@plc1/").is_err()
        );
    }
}
