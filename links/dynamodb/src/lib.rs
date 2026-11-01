//! History sync to Amazon DynamoDB (ADR 0026): the [`Dynamo`] target writes a history sink's
//! batches with `BatchWriteItem`, 25 puts per request, signed with SigV4. One item per row:
//! partition key `key` (the point's full key), sort key `t` (µs), `site`, `value` (a number,
//! a bool, text or null), `quality`, and `expiration` (epoch seconds) when `ttl_days` is set, for
//! the table's TTL. A put replaces the item, so a batch sent twice changes nothing; a `(key, t)`
//! that comes twice in one batch keeps its last row (one request may not touch an item twice).
//!
//! Params (besides `sink`, `batch`, `idle_s`, `retry_s`): `region`, `table`, `access_key_id`,
//! `endpoint` (default `https://dynamodb.<region>.amazonaws.com`; `http://` only to loopback,
//! for DynamoDB Local, unless `insecure_plaintext`), `ttl_days` (0: no `expiration`),
//! `create_table` (false: CreateTable with on-demand billing; the TTL itself is switched on in
//! AWS), `ca_pem`, `timeout_ms` (10 000). The secret access key goes in with ▸ Set Password.

use std::collections::HashMap;
use wyrm_core::Value;
use wyrm_history_sync::http::{json_string, loopback, parse_url, Client, Response};
use wyrm_history_sync::sigv4::{amz_date, authorization, Signing};
use wyrm_history_sync::{Limits, Map, Row, SyncApp, Target, TargetError};
use wyrm_link_api::Host;

/// The app: `Portable<DynamoSync>` embedded or as a process, `export!(DynamoSync)` in WASM.
pub type DynamoSync = SyncApp<Dynamo>;

const KEYS: [&str; 9] = [
    "region",
    "table",
    "access_key_id",
    "endpoint",
    "ttl_days",
    "create_table",
    "ca_pem",
    "timeout_ms",
    "insecure_plaintext",
];
const DEFAULT_TIMEOUT_MS: u32 = 10_000;
/// Puts per BatchWriteItem (the API's bound).
const PER_REQUEST: usize = 25;
/// Sends of one request while DynamoDB leaves items unprocessed.
const TRIES: usize = 3;

#[derive(Debug, Clone, PartialEq)]
struct Cfg {
    region: String,
    table: String,
    access_key: String,
    tls: bool,
    host: String,
    port: u16,
    base: String,
    ttl_s: Option<u64>,
    create_table: bool,
    ca_pem: Option<String>,
    timeout_ms: u32,
}

fn text(cfg: &Map, key: &str) -> Result<Option<String>, String> {
    match cfg.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.trim().to_owned())),
        Some(_) => Err(format!("params.{key}: text")),
    }
}

fn parse(cfg: &Map) -> Result<Cfg, String> {
    if let Some(k) = cfg.keys().find(|k| !KEYS.contains(&k.as_str())) {
        return Err(format!("params.{k}: unknown"));
    }
    let region = text(cfg, "region")?.ok_or("params.region: e.g. eu-central-1")?;
    if !region
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    {
        return Err(format!("params.region: {region:?}"));
    }
    let table = text(cfg, "table")?.ok_or("params.table: the table")?;
    if !(3..=255).contains(&table.len())
        || !table
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "_-.".contains(c))
    {
        return Err(format!(
            "params.table: {table:?}: 3 to 255 of letters, digits, _ - ."
        ));
    }
    let access_key = text(cfg, "access_key_id")?.ok_or("params.access_key_id: the key id")?;
    if !access_key.chars().all(|c| c.is_ascii_alphanumeric()) {
        return Err("params.access_key_id: letters and digits".into());
    }
    let endpoint = text(cfg, "endpoint")?
        .unwrap_or_else(|| format!("https://dynamodb.{region}.amazonaws.com"));
    let (tls, host, port, base) = parse_url(&endpoint)?;
    let insecure = matches!(cfg.get("insecure_plaintext"), Some(Value::Bool(true)));
    if !tls && !loopback(&host) && !insecure {
        return Err(format!(
            "params.endpoint: {endpoint} sends the requests in the clear; use https://, or \
             insecure_plaintext"
        ));
    }
    let ttl_s = match cfg.get("ttl_days") {
        None => None,
        Some(v) => {
            let d = v
                .as_f64()
                .filter(|d| (0.0..=36_500.0).contains(d))
                .ok_or("params.ttl_days: 0 to 36500")?;
            // 0: no expiration
            (d > 0.0).then_some((d * 86_400.0) as u64)
        }
    };
    let timeout_ms = match cfg.get("timeout_ms") {
        None => DEFAULT_TIMEOUT_MS,
        Some(v) => v
            .as_f64()
            .filter(|t| (100.0..=60_000.0).contains(t))
            .map(|t| t as u32)
            .ok_or("params.timeout_ms: 100 to 60000")?,
    };
    Ok(Cfg {
        region,
        table,
        access_key,
        tls,
        host,
        port,
        base: if base.is_empty() { "/".into() } else { base },
        ttl_s,
        create_table: matches!(cfg.get("create_table"), Some(Value::Bool(true))),
        ca_pem: text(cfg, "ca_pem")?,
        timeout_ms,
    })
}

/// A number DynamoDB takes: finite, within its range (±1E-130 to ±9.99E+125).
fn number(f: f64) -> Option<String> {
    let a = f.abs();
    (f.is_finite() && (a == 0.0 || (1e-130..1e125).contains(&a))).then(|| format!("{f}"))
}

/// One row as a DynamoDB item, or `None` for a value it cannot hold.
fn item(r: &Row, expiration: Option<u64>) -> Option<String> {
    let value = match &r.v {
        Value::Float(f) => format!("{{\"N\":\"{}\"}}", number(*f)?),
        Value::Int(i) => format!("{{\"N\":\"{i}\"}}"),
        Value::UInt(u) => format!("{{\"N\":\"{u}\"}}"),
        Value::Bool(b) => format!("{{\"BOOL\":{b}}}"),
        Value::Str(s) => format!("{{\"S\":{}}}", json_string(s)),
        Value::Null => "{\"NULL\":true}".into(),
        Value::Bytes(_) | Value::Array(_) | Value::Map(_) => return None,
    };
    let mut out = format!(
        "{{\"key\":{{\"S\":{}}},\"t\":{{\"N\":\"{}\"}},\"site\":{{\"S\":{}}},\"value\":{value},\
         \"quality\":{{\"N\":\"{}\"}}",
        json_string(&r.key),
        r.t,
        json_string(&r.site),
        r.q.code()
    );
    if let Some(e) = expiration {
        out.push_str(&format!(",\"expiration\":{{\"N\":\"{e}\"}}"));
    }
    out.push('}');
    Some(out)
}

/// The batch as BatchWriteItem bodies of at most 25 puts, the last row of each `(key, t)`.
pub fn requests(table: &str, ttl_s: Option<u64>, rows: &[Row]) -> Vec<String> {
    let mut last: HashMap<(&str, u64), usize> = HashMap::new();
    for (i, r) in rows.iter().enumerate() {
        last.insert((r.key.as_str(), r.t), i);
    }
    let puts: Vec<String> = rows
        .iter()
        .enumerate()
        .filter(|(i, r)| last.get(&(r.key.as_str(), r.t)) == Some(i))
        .filter_map(|(_, r)| item(r, ttl_s.map(|s| r.t / 1_000_000 + s)))
        .map(|i| format!("{{\"PutRequest\":{{\"Item\":{i}}}}}"))
        .collect();
    puts.chunks(PER_REQUEST)
        .map(|c| {
            format!(
                "{{\"RequestItems\":{{{}:[{}]}}}}",
                json_string(table),
                c.join(",")
            )
        })
        .collect()
}

/// The `__type` of an error answer, without its namespace (`…#ThrottlingException`).
fn error_type(r: &Response) -> String {
    let body = String::from_utf8_lossy(&r.body);
    body.split("\"__type\"")
        .nth(1)
        .and_then(|rest| rest.split('"').nth(1))
        .map(|t| t.rsplit('#').next().unwrap_or(t).to_owned())
        .unwrap_or_default()
}

/// What an answer means for the batch.
fn judge(r: &Response, what: &str) -> Result<(), TargetError> {
    if (200..300).contains(&r.status) {
        return Ok(());
    }
    let kind = error_type(r);
    let msg = format!("dynamodb {what}: {} {}", r.status, r.text(300));
    let wait = r.status >= 500
        || matches!(
            kind.as_str(),
            "ProvisionedThroughputExceededException"
                | "ThrottlingException"
                | "RequestLimitExceeded"
                | "LimitExceededException"
                | "InternalServerError"
                // a table just made is not active yet; a missing one shows its error meanwhile
                | "ResourceNotFoundException"
        );
    // an item over the size limit refuses that row; any other validation error (a key that
    // does not fit the table) stops (review HS-1)
    let too_large = kind == "ValidationException" && msg.to_ascii_lowercase().contains("size");
    Err(if wait {
        TargetError::Retry(msg)
    } else if too_large {
        TargetError::Refused(msg)
    } else {
        TargetError::Fatal(msg)
    })
}

/// Nothing left unprocessed in a BatchWriteItem answer.
fn all_processed(r: &Response) -> bool {
    let body: String = String::from_utf8_lossy(&r.body)
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect();
    body.contains("\"UnprocessedItems\":{}")
}

/// DynamoDB over one keep-alive connection.
pub struct Dynamo {
    cfg: Cfg,
    secret: String,
    http: Client,
}

impl Dynamo {
    /// One signed call of the JSON API (`target` = `DynamoDB_20120810.<Action>`).
    fn call(
        &mut self,
        net: &mut dyn Host,
        action: &str,
        body: &str,
    ) -> Result<Response, TargetError> {
        let date = amz_date(net.now_us());
        let target = format!("DynamoDB_20120810.{action}");
        let host = self.http.host_header();
        let content_type = "application/x-amz-json-1.0";
        let signed = [
            ("host", host.as_str()),
            ("x-amz-date", date.as_str()),
            ("x-amz-target", target.as_str()),
            ("content-type", content_type),
        ];
        let auth = authorization(
            &Signing {
                access_key: &self.cfg.access_key,
                secret_key: &self.secret,
                region: &self.cfg.region,
                service: "dynamodb",
                amz_date: &date,
            },
            "POST",
            &self.cfg.base,
            "",
            &signed,
            body.as_bytes(),
        );
        let headers = [
            ("X-Amz-Date", date.as_str()),
            ("X-Amz-Target", target.as_str()),
            ("Content-Type", content_type),
            ("Authorization", auth.as_str()),
        ];
        let path = self.cfg.base.clone();
        self.http
            .request(net, "POST", &path, &headers, body.as_bytes())
    }
}

impl Target for Dynamo {
    const KIND: &'static str = "dynamodb";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn check(cfg: &Map) -> Result<(), String> {
        parse(cfg).map(|_| ())
    }

    fn connect(net: &mut dyn Host, cfg: &Map, secret: Option<&str>) -> Result<Self, TargetError> {
        let cfg = parse(cfg).map_err(TargetError::Fatal)?;
        let secret = secret
            .ok_or_else(|| {
                TargetError::Fatal("dynamodb: no secret access key: Set Password".into())
            })?
            .to_owned();
        let mut http = Client::new(
            cfg.tls,
            cfg.host.clone(),
            cfg.port,
            cfg.ca_pem.clone(),
            cfg.timeout_ms,
        );
        http.open(net)?;
        Ok(Dynamo { cfg, secret, http })
    }

    fn prepare(&mut self, net: &mut dyn Host) -> Result<(), TargetError> {
        if !self.cfg.create_table {
            return Ok(());
        }
        let body = format!(
            "{{\"TableName\":{},\"AttributeDefinitions\":[{{\"AttributeName\":\"key\",\
             \"AttributeType\":\"S\"}},{{\"AttributeName\":\"t\",\"AttributeType\":\"N\"}}],\
             \"KeySchema\":[{{\"AttributeName\":\"key\",\"KeyType\":\"HASH\"}},\
             {{\"AttributeName\":\"t\",\"KeyType\":\"RANGE\"}}],\"BillingMode\":\"PAY_PER_REQUEST\"}}",
            json_string(&self.cfg.table)
        );
        let r = self.call(net, "CreateTable", &body)?;
        if error_type(&r) == "ResourceInUseException" {
            return Ok(()); // it exists
        }
        judge(&r, "create table")
    }

    fn write(&mut self, net: &mut dyn Host, rows: &[Row]) -> Result<(), TargetError> {
        for body in requests(&self.cfg.table, self.cfg.ttl_s, rows) {
            let mut done = false;
            for _ in 0..TRIES {
                let r = self.call(net, "BatchWriteItem", &body)?;
                judge(&r, "write")?;
                if all_processed(&r) {
                    done = true;
                    break;
                }
            }
            if !done {
                // a put replaces: the whole request goes again later
                return Err(TargetError::Retry(
                    "dynamodb write: items left unprocessed (throughput)".into(),
                ));
            }
        }
        Ok(())
    }

    fn ping(&mut self, net: &mut dyn Host) -> Result<(), TargetError> {
        let body = format!("{{\"TableName\":{}}}", json_string(&self.cfg.table));
        let r = self.call(net, "DescribeTable", &body)?;
        judge(&r, "describe table")
    }

    fn limits(&self) -> Limits {
        // a batch is up to 20 requests in one call of the app
        Limits { rows: 500 }
    }

    fn close(mut self, net: &mut dyn Host) {
        self.http.close(net);
    }
}

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(DynamoSync);

#[cfg(test)]
mod tests;
